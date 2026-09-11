#include "Engine.hpp"
#include <cstdio>
#include <os/log.h>

namespace tx {
static os_log_t callLog = os_log_create("de.enwikuna.TelefonX", "NativeCall");

void onCallState(pjsua_call_id slot, pjsip_event *) {
    engine.schedule([slot] {
        pjsua_call_info info;
        if (pjsua_call_get_info(slot, &info) != PJ_SUCCESS) { return; }
        if (info.state == PJSIP_INV_STATE_DISCONNECTED && engine.calls[slot].terminal) { return; }
        auto handle = engine.handle(slot);
        auto &call = engine.calls[slot];
        if (info.acc_id >= 0 && info.acc_id < PJSUA_MAX_ACC && !engine.accounts[info.acc_id].empty()) {
            call.account = engine.accounts[info.acc_id];
        }
        os_log_with_type(callLog, OS_LOG_TYPE_DEBUG,
                         "call state slot=%{public}d generation=%{public}llu state=%{public}d status=%{public}d role=%{public}d held=%{public}d pending=%{public}d",
                         slot, handle.generation, info.state, info.last_status, info.role,
                         call.localMusicHold, call.holdPending);
        if (info.state == PJSIP_INV_STATE_CONFIRMED) { engine.connectAudio(slot); }
        const auto remote = string(info.remote_info);
        tx_event event{}; event.kind = 2; event.call = handle; event.account = call.account.c_str();
        event.remote = remote.c_str(); event.state = info.state; event.status = info.last_status;
        event.incoming = info.role == PJSIP_ROLE_UAS;
        engine.emit(event);
        if (info.state == PJSIP_INV_STATE_DISCONNECTED) {
            engine.clearConference(slot);
            engine.stopHoldMusic(slot);
            if (call.player != PJSUA_INVALID_ID) { pjsua_player_destroy(call.player); }
            if (call.recorder != PJSUA_INVALID_ID) { pjsua_recorder_destroy(call.recorder); }
            call.terminal = true;
        }
    });
}
void onIncoming(pjsua_acc_id, pjsua_call_id slot, pjsip_rx_data *) {
    engine.schedule([slot] { onCallState(slot, nullptr); pjsua_call_answer(slot, 180, nullptr, nullptr); });
}
void onMedia(pjsua_call_id slot) {
    engine.schedule([slot] {
        pjsua_call_info info;
        if (pjsua_call_get_info(slot, &info) != PJ_SUCCESS) { return; }
        if (info.state == PJSIP_INV_STATE_DISCONNECTED) { return; }
        auto &call = engine.calls[slot];
        if (call.holdPending && ((info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD) == call.holdRequested)) {
            call.holdPending = false;
        }
        tx_event event{}; event.kind = 3; event.call = engine.handle(slot);
        event.held = call.localMusicHold || info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD;
        event.remote_held = info.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD;
        event.status = info.media_status == PJSUA_CALL_MEDIA_ERROR ? PJ_EUNKNOWN : engine.connectAudio(slot);
        engine.emit(event);
    });
}
void onTransfer(pjsua_call_id slot, int status, const pj_str_t *, pj_bool_t final, pj_bool_t *more) {
    if (final) { *more = PJ_FALSE; }
    engine.schedule([slot, status, final] {
        tx_event event{}; event.kind = 4; event.call = engine.handle(slot); event.status = status; event.final = final;
        engine.emit(event);
        if (final && status >= 200 && status < 300) { pjsua_call_hangup(slot, 0, nullptr, nullptr); }
    });
}
void onDTMF(pjsua_call_id slot, const pjsua_dtmf_info *info) {
    const auto digit = info->digit;
    engine.schedule([slot, digit] { tx_event event{}; event.kind = 6; event.call = engine.handle(slot); event.status = digit; engine.emit(event); });
}
void onTransaction(pjsua_call_id slot, pjsip_transaction *tsx, pjsip_event *) {
    if (tsx->method.id == PJSIP_BYE_METHOD) {
        os_log_with_type(callLog, OS_LOG_TYPE_DEBUG,
                         "BYE transaction slot=%{public}d role=%{public}d state=%{public}d status=%{public}d",
                         slot, tsx->role, tsx->state, tsx->status_code);
    }
    if (tsx->role != PJSIP_ROLE_UAC || tsx->method.id != PJSIP_INVITE_METHOD ||
        tsx->state < PJSIP_TSX_STATE_COMPLETED || tsx->status_code < 400 ||
        tsx->status_code == 401 || tsx->status_code == 407 || tsx->status_code == 422) { return; }
    if (slot < 0 || slot >= PJSUA_MAX_CALLS || engine.calls[slot].terminal || !engine.calls[slot].holdPending) { return; }
    const tx_call handle{slot, engine.calls[slot].generation};
    const auto status = tsx->status_code;
    // Run after PJSUA has rolled back its provisional SDP, not inside its callback.
    std::lock_guard<std::mutex> lock(engine.mutex);
    engine.jobs.emplace_back([handle, status] {
        if (!engine.valid(handle)) { return; }
        auto &call = engine.calls[handle.slot];
        if (!call.holdPending) { return; }
        call.holdPending = false; call.holdRequested = call.holdPrevious; call.holdError = status;
        engine.connectAudio(handle.slot);
        onMedia(handle.slot);
    });
}
}

extern "C" int32_t tx_make_call(const char *uuid, const char *uri, int32_t suppress_caller_id, tx_call *result) {
    return tx::engine.invoke([=]() -> int {
        if (!uuid || !uri || !result) { return PJ_EINVAL; }
        const auto account = tx::engine.account(uuid);
        if (account == PJSUA_INVALID_ID) { return PJ_ENOTFOUND; }
        auto destination = pj_str(const_cast<char *>(uri));
        pjsua_call_setting setting; pjsua_call_setting_default(&setting); setting.aud_cnt = 1; setting.vid_cnt = 0;
        pjsua_msg_data message; pjsua_msg_data *messagePointer = nullptr;
        pjsip_generic_string_hdr privacy;
        if (suppress_caller_id) {
            pjsua_msg_data_init(&message);
            auto name = pj_str(const_cast<char *>("Privacy"));
            auto value = pj_str(const_cast<char *>("id"));
            pjsip_generic_string_hdr_init2(&privacy, &name, &value);
            pj_list_push_back(&message.hdr_list, &privacy);
            messagePointer = &message;
        }
        pjsua_call_id slot;
        auto status = pjsua_call_make_call(account, &destination, &setting, nullptr, messagePointer, &slot);
        if (status == PJ_SUCCESS) { *result = tx::engine.handle(slot); }
        return status;
    });
}
extern "C" int32_t tx_answer(tx_call call) {
    return tx::engine.invoke([=]() -> int { return tx::engine.valid(call) ? pjsua_call_answer(call.slot, 200, nullptr, nullptr) : PJ_EINVALIDOP; });
}
extern "C" int32_t tx_hangup(tx_call call, int32_t decline) {
    // 486 only rejects this endpoint and lets a proxy keep other forked legs
    // ringing. An explicit user decline must terminate the whole invitation.
    return tx::engine.invoke([=]() -> int { return tx::engine.valid(call) ? pjsua_call_hangup(call.slot, decline ? 603 : 0, nullptr, nullptr) : PJ_EINVALIDOP; });
}
extern "C" int32_t tx_mute(tx_call call, int32_t muted) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(call)) { return PJ_EINVALIDOP; }
        pjsua_call_info info;
        if (pjsua_call_get_info(call.slot, &info) != PJ_SUCCESS) { return PJ_EINVAL; }
        if (info.media_status != PJSUA_CALL_MEDIA_ACTIVE || tx::engine.calls[call.slot].holdRequested) { tx::engine.calls[call.slot].muted = muted; return PJ_SUCCESS; }
        const int slot = pjsua_call_get_conf_port(call.slot);
        if (slot == PJSUA_INVALID_ID) { return PJ_EINVALIDOP; }
        const auto status = muted ? pjsua_conf_disconnect(0, slot) : pjsua_conf_connect(0, slot);
        if (status == PJ_SUCCESS) { tx::engine.calls[call.slot].muted = muted; }
        return status;
    });
}
extern "C" int32_t tx_hold(tx_call call, int32_t held) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(call)) { return PJ_EINVALIDOP; }
        auto &data = tx::engine.calls[call.slot];
        if (data.holdPending) { return PJ_EBUSY; }
        pjsua_call_info info;
        if (pjsua_call_get_info(call.slot, &info) != PJ_SUCCESS || info.state != PJSIP_INV_STATE_CONFIRMED) { return PJ_EINVALIDOP; }
        const bool previous = data.localMusicHold || info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD;
        if (previous == (held != 0)) { return PJ_SUCCESS; }
        if (held && !tx::engine.holdMusic.empty() && data.holdPlayer == PJSUA_INVALID_ID) {
            auto path = tx::pj(tx::engine.holdMusic);
            const auto prepared = pjsua_player_create(&path, 0, &data.holdPlayer);
            if (prepared != PJ_SUCCESS) { return prepared; }
        }
        if (data.localMusicHold || (held && !tx::engine.holdMusic.empty())) {
            data.holdPrevious = previous; data.holdRequested = held != 0; data.holdPending = false; data.holdError = PJ_SUCCESS;
            if (!held && data.holdPlayer != PJSUA_INVALID_ID) {
                pjsua_conf_disconnect(pjsua_player_get_conf_port(data.holdPlayer), info.conf_slot);
            }
            data.localMusicHold = held != 0;
            const auto status = tx::engine.connectAudio(call.slot);
            if (status != PJ_SUCCESS) {
                data.localMusicHold = previous; data.holdRequested = previous; data.holdError = status;
                tx::engine.connectAudio(call.slot);
                return status;
            }
            tx_event event{}; event.kind = 3; event.call = tx::engine.handle(call.slot);
            event.held = data.localMusicHold; event.remote_held = info.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD;
            event.status = PJ_SUCCESS; tx::engine.emit(event);
            return PJ_SUCCESS;
        }
        data.holdPrevious = previous; data.holdRequested = held != 0; data.holdPending = true; data.holdError = PJ_SUCCESS;
        if (!held && data.holdPlayer != PJSUA_INVALID_ID) {
            pjsua_conf_disconnect(pjsua_player_get_conf_port(data.holdPlayer), info.conf_slot);
        }
        if (held) {
            // Stop local routing immediately, before the remote re-INVITE response.
            // Consultation setup must never briefly bridge two people together.
            const auto port = pjsua_call_get_conf_port(call.slot);
            if (port != PJSUA_INVALID_ID) { pjsua_conf_disconnect(0, port); pjsua_conf_disconnect(port, 0); }
            tx::engine.updateConferenceAudio(call.slot);
        }
        const auto status = held ? pjsua_call_set_hold(call.slot, nullptr) : pjsua_call_reinvite(call.slot, PJSUA_CALL_UNHOLD, nullptr);
        if (status != PJ_SUCCESS) {
            data.holdPending = false; data.holdRequested = previous; data.holdError = status;
            tx::engine.connectAudio(call.slot);
        }
        return status;
    });
}
extern "C" int32_t tx_hold_status(tx_call call, int32_t *held, int32_t *pending) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(call) || !held || !pending) { return PJ_EINVALIDOP; }
        pjsua_call_info info;
        const auto status = pjsua_call_get_info(call.slot, &info);
        if (status != PJ_SUCCESS) { return status; }
        const auto &data = tx::engine.calls[call.slot];
        *held = data.localMusicHold || info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD; *pending = data.holdPending;
        return data.holdError;
    });
}
extern "C" int32_t tx_set_hold_music(const char *wav) {
    const std::string path = wav ? wav : "";
    return tx::engine.invoke([path]() -> int {
        if (pjsua_call_get_count() != 0) { return PJ_EBUSY; }
        if (!path.empty()) {
            auto file = tx::pj(path); pjsua_player_id player = PJSUA_INVALID_ID;
            auto status = pjsua_player_create(&file, 0, &player);
            if (status != PJ_SUCCESS) { return status; }
            pjsua_player_destroy(player);
        }
        tx::engine.holdMusic = path;
        return PJ_SUCCESS;
    });
}
extern "C" int32_t tx_dtmf(tx_call call, const char *digits) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(call) || !digits) { return PJ_EINVALIDOP; }
        pjsua_call_send_dtmf_param param; pjsua_call_send_dtmf_param_default(&param);
        param.digits = pj_str(const_cast<char *>(digits));
        auto status = pjsua_call_send_dtmf(call.slot, &param);
        if (status == PJMEDIA_RTP_EREMNORFC2833) { param.method = PJSUA_DTMF_METHOD_SIP_INFO; status = pjsua_call_send_dtmf(call.slot, &param); }
        return status;
    });
}
extern "C" int32_t tx_conference(tx_call first, tx_call second, int32_t enabled) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(first) || !tx::engine.valid(second) || first.slot == second.slot) { return PJ_EINVALIDOP; }
        pjsua_call_info firstInfo, secondInfo;
        if (pjsua_call_get_info(first.slot, &firstInfo) != PJ_SUCCESS ||
            pjsua_call_get_info(second.slot, &secondInfo) != PJ_SUCCESS) { return PJ_EINVALIDOP; }
        if (enabled && (firstInfo.state != PJSIP_INV_STATE_CONFIRMED || secondInfo.state != PJSIP_INV_STATE_CONFIRMED ||
                        firstInfo.media_status != PJSUA_CALL_MEDIA_ACTIVE || secondInfo.media_status != PJSUA_CALL_MEDIA_ACTIVE ||
                        tx::engine.calls[first.slot].holdRequested || tx::engine.calls[second.slot].holdRequested)) {
            return PJ_EINVALIDOP;
        }
        const auto disconnect = [&] {
            if (firstInfo.conf_slot == PJSUA_INVALID_ID || secondInfo.conf_slot == PJSUA_INVALID_ID) { return; }
            pjsua_conf_disconnect(firstInfo.conf_slot, secondInfo.conf_slot);
            pjsua_conf_disconnect(secondInfo.conf_slot, firstInfo.conf_slot);
        };
        if (!enabled) { disconnect(); }
        tx::engine.calls[first.slot].conferencePeers[second.slot] = enabled != 0;
        tx::engine.calls[second.slot].conferencePeers[first.slot] = enabled != 0;
        const auto status = tx::engine.updateConferenceAudio(first.slot);
        if (status != PJ_SUCCESS && enabled) {
            disconnect();
            tx::engine.calls[first.slot].conferencePeers[second.slot] = false;
            tx::engine.calls[second.slot].conferencePeers[first.slot] = false;
        }
        return status;
    });
}
extern "C" int32_t tx_transfer(tx_call source, tx_call consultation) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(source) || !tx::engine.valid(consultation) || source.slot == consultation.slot) { return PJ_EINVALIDOP; }
        return pjsua_call_xfer_replaces(source.slot, consultation.slot, PJSUA_XFER_NO_REQUIRE_REPLACES, nullptr);
    });
}
extern "C" int32_t tx_get_quality(tx_call call, tx_quality *result) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.valid(call) || !result) { return PJ_EINVALIDOP; }
        pjsua_stream_info info; pjsua_stream_stat stats;
        auto status = pjsua_call_get_stream_info(call.slot, 0, &info);
        if (status != PJ_SUCCESS || info.type != PJMEDIA_TYPE_AUDIO) { return status ? status : PJ_EINVALIDOP; }
        status = pjsua_call_get_stream_stat(call.slot, 0, &stats);
        if (status != PJ_SUCCESS) { return status; }
        *result = {};
        std::snprintf(result->codec, sizeof(result->codec), "%.*s", (int)info.info.aud.fmt.encoding_name.slen, info.info.aud.fmt.encoding_name.ptr);
        result->clock_rate = info.info.aud.fmt.clock_rate; result->rx_packets = stats.rtcp.rx.pkt; result->tx_packets = stats.rtcp.tx.pkt;
        result->lost_packets = stats.rtcp.rx.loss; result->jitter_ms = stats.rtcp.rx.jitter.mean / 1000.0;
        result->rtt_ms = stats.rtcp.rtt.mean / 1000.0;
        pjmedia_transport_info transport; pjmedia_transport_info_init(&transport);
        if (pjsua_call_get_med_transport_info(call.slot, 0, &transport) == PJ_SUCCESS) {
            auto *srtp = (pjmedia_srtp_info *)pjmedia_transport_info_get_spc_info(&transport, PJMEDIA_TRANSPORT_TYPE_SRTP);
            result->srtp = srtp && srtp->active;
        }
        return PJ_SUCCESS;
    });
}
extern "C" int32_t tx_test_media(tx_call call, const char *play_wav, const char *record_wav) {
    return tx::engine.invoke([=]() -> int {
        if (!tx::engine.nullAudio || !tx::engine.valid(call)) { return PJ_EINVALIDOP; }
        const int port = pjsua_call_get_conf_port(call.slot);
        auto &data = tx::engine.calls[call.slot];
        if (play_wav && play_wav[0]) {
            auto file = pj_str(const_cast<char *>(play_wav));
            auto status = pjsua_player_create(&file, 0, &data.player);
            if (status != PJ_SUCCESS) { return status; }
            pjsua_conf_connect(pjsua_player_get_conf_port(data.player), port);
        }
        if (record_wav && record_wav[0]) {
            auto file = pj_str(const_cast<char *>(record_wav));
            auto status = pjsua_recorder_create(&file, 0, nullptr, 0, 0, &data.recorder);
            if (status != PJ_SUCCESS) { return status; }
            pjsua_conf_connect(port, pjsua_recorder_get_conf_port(data.recorder));
        }
        return PJ_SUCCESS;
    });
}
