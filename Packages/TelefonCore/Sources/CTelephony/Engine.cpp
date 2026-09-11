#include "Engine.hpp"
#include <cstring>
#include <os/log.h>

namespace tx {
Engine engine;
static os_log_t audioLog = os_log_create("de.enwikuna.TelefonX", "NativeAudio");
std::string string(pj_str_t value) { return value.ptr && value.slen > 0 ? std::string(value.ptr, value.slen) : ""; }
pj_str_t pj(const std::string &value) { return pj_str(const_cast<char *>(value.c_str())); }

int Engine::invoke(std::function<int()> action) {
    if (std::this_thread::get_id() == owner) { return action(); }
    auto task = std::make_shared<std::packaged_task<int()>>(std::move(action));
    auto result = task->get_future();
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!accepting) { return PJ_EINVALIDOP; }
        jobs.emplace_back([task] { (*task)(); });
    }
    return result.get();
}
void Engine::schedule(std::function<void()> action) {
    if (std::this_thread::get_id() == owner) { action(); return; }
    std::lock_guard<std::mutex> lock(mutex);
    if (accepting) { jobs.emplace_back(std::move(action)); }
}
void Engine::emit(tx_event event) { if (callback) { callback(&event, context); } }
bool Engine::valid(tx_call h) const {
    return h.slot >= 0 && h.slot < PJSUA_MAX_CALLS && h.generation != 0 &&
           calls[h.slot].generation == h.generation && !calls[h.slot].terminal && pjsua_call_is_active(h.slot);
}
tx_call Engine::handle(int slot) {
    if (!calls[slot].generation || calls[slot].terminal) {
        calls[slot] = CallData{}; calls[slot].generation = nextGeneration++; calls[slot].terminal = false;
    }
    return {slot, calls[slot].generation};
}
int Engine::account(const std::string &uuid) const {
    for (int i = 0; i < PJSUA_MAX_ACC; ++i) { if (accounts[i] == uuid && pjsua_acc_is_valid(i)) { return i; } }
    return PJSUA_INVALID_ID;
}
int Engine::initialize(int port) {
    auto status = pjsua_create();
    if (status != PJ_SUCCESS) { return status; }
    pjsua_config config; pjsua_config_default(&config);
    config.max_calls = 32; config.thread_cnt = 0;
    config.user_agent = pj_str(const_cast<char *>("TelefonX/0.1 PJSIP/2.17"));
    config.cb.on_call_state = onCallState; config.cb.on_incoming_call = onIncoming;
    config.cb.on_call_media_state = onMedia; config.cb.on_reg_state = onRegistration;
    config.cb.on_call_sdp_created = onSDP; config.cb.on_call_transfer_status = onTransfer;
    config.cb.on_dtmf_digit2 = onDTMF;
    config.cb.on_call_tsx_state = onTransaction;
    config.cb.on_transport_state = [](pjsip_transport *, pjsip_transport_state state, const pjsip_transport_state_info *info) {
        if (state == PJSIP_TP_STATE_DISCONNECTED && info && info->status == PJSIP_TLS_ECERTVERIF) {
            engine.schedule([] { tx_event event{}; event.kind = 5; event.status = PJSIP_TLS_ECERTVERIF; engine.emit(event); });
        }
    };
    pjsua_logging_config logging; pjsua_logging_config_default(&logging);
    logging.level = 0; logging.console_level = 0; logging.msg_logging = PJ_FALSE;
    pjsua_media_config media; pjsua_media_config_default(&media);
    media.clock_rate = 48000; media.snd_clock_rate = 48000; media.channel_count = 1;
    media.audio_frame_ptime = 20; media.quality = 10; media.no_vad = PJ_TRUE;
    media.ec_tail_len = 200;
    media.ec_options = PJMEDIA_ECHO_USE_SW_ECHO | PJMEDIA_ECHO_WEBRTC_AEC3;
    media.jb_init = -1; media.jb_min_pre = -1; media.jb_max_pre = -1; media.jb_max = 200;
    // PJSIP's delayed CoreAudio close can race the stream teardown and abort in
    // pjmedia_aud_stream_get_param. Keep the selected device open for the engine
    // lifetime so subsequent calls retain a stable playback path.
    media.snd_auto_close_time = -1;
    status = pjsua_init(&config, &logging, &media);
    if (status != PJ_SUCCESS) { return status; }
    transports.fill(PJSUA_INVALID_ID);
    const pjsip_transport_type_e types[] = {PJSIP_TRANSPORT_UDP, PJSIP_TRANSPORT_TCP, PJSIP_TRANSPORT_TLS,
                                          PJSIP_TRANSPORT_UDP6, PJSIP_TRANSPORT_TCP6, PJSIP_TRANSPORT_TLS6};
    for (int i = 0; i < 6; ++i) {
        pjsua_transport_config transport; pjsua_transport_config_default(&transport);
        transport.port = i == 0 ? port : 0;
        if (nullAudio) { transport.bound_addr = pj_str(const_cast<char *>(i < 3 ? "127.0.0.1" : "::1")); }
        transport.qos_type = PJ_QOS_TYPE_VOICE;
        transport.tls_setting.verify_server = PJ_TRUE;
        transport.tls_setting.verify_client = PJ_FALSE;
        transport.tls_setting.proto = PJ_SSL_SOCK_PROTO_TLS1_2 | PJ_SSL_SOCK_PROTO_TLS1_3;
        status = pjsua_transport_create(types[i], &transport, &transports[i]);
        if (i < 3 && status != PJ_SUCCESS) { return status; }
    }
    status = pjsua_start();
    if (status != PJ_SUCCESS) { return status; }
    pjsua_codec_info codecs[64]; unsigned count = 64;
    pjsua_enum_codecs(codecs, &count);
    for (unsigned i = 0; i < count; ++i) {
        std::string name = string(codecs[i].codec_id);
        pj_uint8_t priority = 0;
        if (name.rfind("opus/", 0) == 0) { priority = 240; }
        else if (name.rfind("G722/", 0) == 0) { priority = 230; }
        else if (name.rfind("PCMA/", 0) == 0) { priority = 220; }
        else if (name.rfind("PCMU/", 0) == 0) { priority = 210; }
        pjsua_codec_set_priority(&codecs[i].codec_id, priority);
    }
    pjmedia_codec_opus_config opus; pjmedia_codec_opus_get_config(&opus);
    opus.sample_rate = 48000; opus.channel_cnt = 1; opus.bit_rate = 32000; opus.packet_loss = 5;
    pjmedia_codec_param param;
    auto opusID = pj_str(const_cast<char *>("opus/48000/2"));
    if (pjsua_codec_get_param(&opusID, &param) == PJ_SUCCESS) {
        param.setting.vad = 0; param.setting.plc = 1;
        pjmedia_codec_opus_set_default_param(&opus, &param);
    }
    // Null audio keeps the clock running without requesting the microphone at launch.
    return pjsua_set_null_snd_dev();
}
int Engine::connectAudio(int slot) {
    pjsua_call_info info;
    if (pjsua_call_get_info(slot, &info) != PJ_SUCCESS) { return PJ_EINVAL; }
    auto &call = calls[slot];
    const auto finish = [this, slot](int status) {
        const auto conferenceStatus = updateConferenceAudio(slot);
        return status == PJ_SUCCESS ? conferenceStatus : status;
    };
    if (info.conf_slot == PJSUA_INVALID_ID) { return PJ_SUCCESS; }
    if (call.localMusicHold) {
        pjsua_conf_disconnect(0, info.conf_slot);
        pjsua_conf_disconnect(info.conf_slot, 0);
        if (info.media_status == PJSUA_CALL_MEDIA_ACTIVE &&
            (info.media_dir & PJMEDIA_DIR_ENCODING) && call.holdPlayer != PJSUA_INVALID_ID) {
            // The file has exactly one destination: this held remote call, never port 0.
            return finish(pjsua_conf_connect(pjsua_player_get_conf_port(call.holdPlayer), info.conf_slot));
        }
        return finish(PJ_SUCCESS);
    }
    if (info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD || call.holdRequested) {
        pjsua_conf_disconnect(0, info.conf_slot);
        pjsua_conf_disconnect(info.conf_slot, 0);
        return finish(PJ_SUCCESS);
    }
    if (!call.holdPending) { stopHoldMusic(slot); }
    if (info.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_disconnect(0, info.conf_slot);
        return finish((info.media_dir & PJMEDIA_DIR_DECODING) ? pjsua_conf_connect(info.conf_slot, 0) : PJ_SUCCESS);
    }
    if (info.media_status != PJSUA_CALL_MEDIA_ACTIVE) { return finish(PJ_SUCCESS); }
    auto status = pjsua_conf_connect(info.conf_slot, 0);
    if (status != PJ_SUCCESS) {
        os_log_with_type(audioLog, OS_LOG_TYPE_ERROR,
                         "speaker route failed slot=%{public}d status=%{public}d", slot, status);
    }
    if (status == PJ_SUCCESS && info.state == PJSIP_INV_STATE_CONFIRMED && !calls[slot].muted) {
        status = pjsua_conf_connect(0, info.conf_slot);
        if (status != PJ_SUCCESS) {
            os_log_with_type(audioLog, OS_LOG_TYPE_ERROR,
                             "microphone route failed slot=%{public}d status=%{public}d", slot, status);
        }
    }
    return finish(status);
}
int Engine::updateConferenceAudio(int slot) {
    if (slot < 0 || slot >= PJSUA_MAX_CALLS) { return PJ_EINVAL; }
    pjsua_call_info info;
    if (pjsua_call_get_info(slot, &info) != PJ_SUCCESS || info.conf_slot == PJSUA_INVALID_ID) { return PJ_SUCCESS; }
    auto conferenceReady = [this](int candidate, const pjsua_call_info &candidateInfo) {
        const auto &data = calls[candidate];
        return !data.terminal && !data.localMusicHold && !data.holdRequested && !data.holdPending
            && candidateInfo.state == PJSIP_INV_STATE_CONFIRMED
            && candidateInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE
            && candidateInfo.conf_slot != PJSUA_INVALID_ID;
    };
    int result = PJ_SUCCESS;
    for (int peer = 0; peer < PJSUA_MAX_CALLS; ++peer) {
        if (!calls[slot].conferencePeers[peer]) { continue; }
        pjsua_call_info peerInfo;
        if (!pjsua_call_is_active(peer) || pjsua_call_get_info(peer, &peerInfo) != PJ_SUCCESS) {
            calls[slot].conferencePeers[peer] = false;
            calls[peer].conferencePeers[slot] = false;
            continue;
        }
        pjsua_conf_disconnect(info.conf_slot, peerInfo.conf_slot);
        pjsua_conf_disconnect(peerInfo.conf_slot, info.conf_slot);
        if (!conferenceReady(slot, info) || !conferenceReady(peer, peerInfo)) { continue; }
        auto status = pjsua_conf_connect(info.conf_slot, peerInfo.conf_slot);
        if (status == PJ_SUCCESS) { status = pjsua_conf_connect(peerInfo.conf_slot, info.conf_slot); }
        if (result == PJ_SUCCESS && status != PJ_SUCCESS) { result = status; }
    }
    return result;
}
void Engine::clearConference(int slot) {
    if (slot < 0 || slot >= PJSUA_MAX_CALLS) { return; }
    for (int peer = 0; peer < PJSUA_MAX_CALLS; ++peer) {
        if (!calls[slot].conferencePeers[peer]) { continue; }
        calls[slot].conferencePeers[peer] = false;
        calls[peer].conferencePeers[slot] = false;
    }
}
void Engine::stopHoldMusic(int slot) {
    auto &call = calls[slot];
    if (call.holdPlayer != PJSUA_INVALID_ID) { pjsua_player_destroy(call.holdPlayer); call.holdPlayer = PJSUA_INVALID_ID; }
}
void Engine::releaseAudioIfIdle() {
    if (!releaseAudioPending || nullAudio || pjsua_call_get_count() != 0) { return; }
    pjsua_set_no_snd_dev();
    realAudioActive = false;
    releaseAudioPending = false;
    os_log_with_type(audioLog, OS_LOG_TYPE_INFO, "audio hardware released after final call");
}
}

extern "C" int32_t tx_start(tx_callback cb, void *context, int32_t port, int32_t null_audio) {
    using namespace tx;
    if (engine.worker.joinable()) { return PJ_EEXISTS; }
    engine.callback = cb; engine.context = context; engine.nullAudio = null_audio != 0;
    engine.stopping = false;
    auto ready = std::make_shared<std::promise<int>>(); auto result = ready->get_future();
    engine.worker = std::thread([ready, port] {
        engine.owner = std::this_thread::get_id();
        auto status = engine.initialize(port);
        engine.accepting = status == PJ_SUCCESS;
        ready->set_value(status);
        if (status == PJ_SUCCESS) {
            while (!engine.stopping) {
                std::deque<std::function<void()>> jobs;
                { std::lock_guard<std::mutex> lock(engine.mutex); jobs.swap(engine.jobs); }
                for (auto &job : jobs) { job(); }
                pjsua_handle_events(10);
                engine.releaseAudioIfIdle();
            }
        }
        pjsua_destroy();
        engine.accounts.fill(""); engine.calls.fill(tx::CallData{}); engine.holdMusic.clear();
        engine.realAudioActive = false; engine.releaseAudioPending = false;
        engine.owner = std::thread::id{};
    });
    const int status = result.get();
    if (status != PJ_SUCCESS) { engine.worker.join(); }
    return status;
}
extern "C" void tx_stop() {
    using namespace tx;
    if (!engine.worker.joinable()) { return; }
    engine.invoke([]() -> int { engine.accepting = false; engine.stopping = true; return PJ_SUCCESS; });
    engine.worker.join(); engine.callback = nullptr; engine.context = nullptr;
}
extern "C" int32_t tx_audio_devices(tx_audio_device *devices, int32_t capacity, int32_t *count) {
    return tx::engine.invoke([=]() -> int {
        if (!devices || !count || capacity < 1) { return PJ_EINVAL; }
        pjmedia_aud_dev_refresh();
        const unsigned n = pjmedia_aud_dev_count(); *count = 0;
        for (unsigned i = 0; i < n && *count < capacity; ++i) {
            pjmedia_aud_dev_info info;
            if (pjmedia_aud_dev_get_info(i, &info) != PJ_SUCCESS) { continue; }
            auto &item = devices[(*count)++]; item = {};
            item.index = i; item.inputs = info.input_count; item.outputs = info.output_count;
            std::snprintf(item.name, sizeof(item.name), "%s", info.name);
        }
        return PJ_SUCCESS;
    });
}
extern "C" int32_t tx_set_audio(int32_t input, int32_t output) {
    return tx::engine.invoke([=]() -> int {
        if (tx::engine.nullAudio) { return pjsua_set_null_snd_dev(); }
        tx::engine.releaseAudioPending = false;
        int currentInput = PJSUA_INVALID_ID, currentOutput = PJSUA_INVALID_ID;
        pjsua_get_snd_dev(&currentInput, &currentOutput);
        os_log_with_type(tx::audioLog, OS_LOG_TYPE_INFO,
                         "set audio requested input=%{public}d output=%{public}d currentInput=%{public}d currentOutput=%{public}d tracked=%{public}d active=%{public}d",
                         input, output, currentInput, currentOutput, tx::engine.realAudioActive, pjsua_snd_is_active());
        if (tx::engine.realAudioActive && tx::engine.input == input && tx::engine.output == output && pjsua_snd_is_active()) {
            return PJ_SUCCESS;
        }
        const auto status = pjsua_set_snd_dev(input, output);
        os_log_with_type(tx::audioLog, status == PJ_SUCCESS ? OS_LOG_TYPE_INFO : OS_LOG_TYPE_ERROR,
                         "set audio result status=%{public}d active=%{public}d", status, pjsua_snd_is_active());
        if (status != PJ_SUCCESS) { return status; }
        pjsua_get_snd_dev(&currentInput, &currentOutput);
        os_log_with_type(tx::audioLog, OS_LOG_TYPE_INFO,
                         "active audio devices input=%{public}d output=%{public}d", currentInput, currentOutput);
        tx::engine.input = input; tx::engine.output = output; tx::engine.realAudioActive = true;
        // Reopening CoreAudio replaces conference port 0. Restore every route
        // explicitly so device changes during a call cannot leave silent audio.
        for (int slot = 0; slot < PJSUA_MAX_CALLS; ++slot) {
            if (!pjsua_call_is_active(slot)) { continue; }
            const auto routeStatus = tx::engine.connectAudio(slot);
            if (routeStatus != PJ_SUCCESS) { return routeStatus; }
        }
        return PJ_SUCCESS;
    });
}
extern "C" int32_t tx_network_changed() {
    return tx::engine.invoke([]() -> int {
        pjsua_ip_change_param param; pjsua_ip_change_param_default(&param);
        param.restart_lis_delay = 250;
        return pjsua_handle_ip_change(&param);
    });
}
extern "C" int32_t tx_release_audio() {
    return tx::engine.invoke([]() -> int {
        if (tx::engine.nullAudio) { return PJ_SUCCESS; }
        // The final disconnected call may still exist inside PJSIP while its
        // callback is unwinding. The worker loop performs the close as soon as
        // the native call count reaches zero, safely outside that callback.
        tx::engine.releaseAudioPending = true;
        tx::engine.releaseAudioIfIdle();
        return PJ_SUCCESS;
    });
}
