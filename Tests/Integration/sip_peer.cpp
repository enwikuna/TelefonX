// Isolated loopback test peer. Never connects to a user's PBX or audio devices.
#include "Engine.hpp"
#include <iostream>
#include <sstream>
#include <cstring>
#include <cmath>
#include <vector>

static std::mutex outputMutex, handleMutex;
static tx_call current{-1, 0};
static std::vector<tx_call> handles;
static void line(const std::string &value) { std::lock_guard<std::mutex> lock(outputMutex); std::cout << value << std::endl; }
static void callback(const tx_event *event, void *) {
    if (event->kind == 2) {
        std::lock_guard<std::mutex> lock(handleMutex); current = event->call;
        if (std::none_of(handles.begin(), handles.end(), [&](tx_call h) { return h.generation == current.generation; })) { handles.push_back(current); }
    }
    line("EVENT " + std::to_string(event->kind) + " " + std::to_string(event->state) + " " +
         std::to_string(event->status) + " " + std::to_string(event->held) + " " + std::to_string(event->remote_held));
}
static int codec(const std::string &name) {
    return tx::engine.invoke([name]() -> int {
        pjsua_codec_info codecs[64]; unsigned count = 64;
        auto status = pjsua_enum_codecs(codecs, &count); if (status) { return status; }
        bool found = false;
        for (unsigned i = 0; i < count; ++i) {
            const bool enabled = tx::string(codecs[i].codec_id).rfind(name + "/", 0) == 0;
            found = found || enabled;
            pjsua_codec_set_priority(&codecs[i].codec_id, enabled ? 255 : 0);
        }
        return found ? PJ_SUCCESS : PJ_ENOTFOUND;
    });
}
static int aec() {
    return tx::engine.invoke([]() -> int {
        auto *pool = pjsua_pool_create("aec-test", 4096, 4096);
        pjmedia_echo_state *echo = nullptr;
        auto status = pjmedia_echo_create(pool, 48000, 960, 200, 0, PJMEDIA_ECHO_WEBRTC_AEC3, &echo);
        if (status == PJ_SUCCESS) {
            pj_int16_t capture[960]{}, playback[960]{};
            for (int frame = 0; frame < 100; ++frame) {
                for (int i = 0; i < 960; ++i) { playback[i] = 2000 * std::sin((frame * 960 + i) * 2 * 3.1415926535 * 440 / 48000); capture[i] = playback[i] / 2; }
                status = pjmedia_echo_cancel(echo, capture, playback, 0, nullptr); if (status) { break; }
            }
            pjmedia_echo_destroy(echo);
        }
        pj_pool_release(pool); return status;
    });
}
int main(int argc, char **argv) {
    if (argc < 3) { return 2; }
    int status = tx_start(callback, nullptr, std::stoi(argv[1]), 1);
    if (status) { line("START_ERROR " + std::to_string(status)); return 1; }
    status = codec(argv[2]);
    if (status) { line("CODEC_ERROR " + std::to_string(status)); tx_stop(); return 1; }
    tx_account account{};
    account.uuid = "00000000-0000-0000-0000-000000000001";
    account.username = "peer"; account.authname = ""; account.password = "test-only";
    account.domain = "127.0.0.1"; account.registrar = ""; account.proxy = ""; account.stun = "";
    account.interval = 300; account.local_test = 1;
    status = tx_add_account(&account);
    if (status) { line("ACCOUNT_ERROR " + std::to_string(status)); tx_stop(); return 1; }
    line("READY");
    std::string input;
    while (std::getline(std::cin, input)) {
        std::istringstream command(input); std::string verb; command >> verb;
        tx_call call; std::vector<tx_call> all;
        { std::lock_guard<std::mutex> lock(handleMutex); call = current; all = handles; }
        tx::engine.invoke([&]() -> int {
            for (auto i = all.rbegin(); i != all.rend(); ++i) { if (tx::engine.valid(*i)) { call = *i; break; } }
            return 0;
        });
        if (verb == "QUIT") { break; }
        if (verb == "CALL") { std::string uri; command >> uri; tx_call result{}; status = tx_make_call(account.uuid, uri.c_str(), 0, &result); }
        else if (verb == "ANSWER") { status = tx_answer(call); }
        else if (verb == "DECLINE") { status = tx_hangup(call, 1); }
        else if (verb == "HANGUP") { status = tx_hangup(call, 0); }
        else if (verb == "HOLD") { int value; command >> value; status = tx_hold(call, value); }
        else if (verb == "HOLDAT") {
            size_t index; int value; command >> index >> value;
            status = index < all.size() ? tx_hold(all[index], value) : -1;
        }
        else if (verb == "MUSIC") { std::string path; command >> path; status = tx_set_hold_music(path == "-" ? "" : path.c_str()); }
        else if (verb == "HOLDSTATE") {
            int32_t held = 0, pending = 0; status = tx_hold_status(call, &held, &pending);
            line("HOLDSTATE " + std::to_string(held) + " " + std::to_string(pending));
        }
        else if (verb == "RECORD") {
            std::string path; command >> path;
            status = tx::engine.invoke([call, path]() -> int {
                if (!tx::engine.valid(call)) { return PJ_EINVALIDOP; }
                auto &data = tx::engine.calls[call.slot];
                if (data.recorder != PJSUA_INVALID_ID) { pjsua_recorder_destroy(data.recorder); data.recorder = PJSUA_INVALID_ID; }
                if (path == "-") { return PJ_SUCCESS; }
                auto file = tx::pj(path);
                auto result = pjsua_recorder_create(&file, 0, nullptr, 0, 0, &data.recorder);
                if (result == PJ_SUCCESS) { result = pjsua_conf_connect(pjsua_call_get_conf_port(call.slot), pjsua_recorder_get_conf_port(data.recorder)); }
                return result;
            });
        }
        else if (verb == "ROUTES") {
            status = tx::engine.invoke([call]() -> int {
                auto connected = [](int from, int to) {
                    if (from == PJSUA_INVALID_ID || to == PJSUA_INVALID_ID) { return false; }
                    pjsua_conf_port_info info;
                    if (pjsua_conf_get_port_info(from, &info) != PJ_SUCCESS) { return false; }
                    return std::find(info.listeners, info.listeners + info.listener_cnt, to) != info.listeners + info.listener_cnt;
                };
                const auto port = pjsua_call_get_conf_port(call.slot);
                const auto player = tx::engine.calls[call.slot].holdPlayer;
                const auto music = player == PJSUA_INVALID_ID ? PJSUA_INVALID_ID : pjsua_player_get_conf_port(player);
                line("ROUTES " + std::to_string(connected(0, port)) + " " + std::to_string(connected(music, port)) + " " + std::to_string(connected(music, 0)));
                return PJ_SUCCESS;
            });
        }
        else if (verb == "MUTE") { int value; command >> value; status = tx_mute(call, value); }
        else if (verb == "DTMF") { std::string value; command >> value; status = tx_dtmf(call, value.c_str()); }
        else if (verb == "CONFERENCE") {
            int value; command >> value;
            status = all.size() >= 2 ? tx_conference(all[all.size() - 2], all.back(), value) : -1;
        }
        else if (verb == "CONFERENCEROUTES") {
            status = tx::engine.invoke([all]() -> int {
                if (all.size() < 2 || !tx::engine.valid(all[all.size() - 2]) || !tx::engine.valid(all.back())) { return PJ_EINVALIDOP; }
                auto connected = [](int from, int to) {
                    pjsua_conf_port_info info;
                    if (pjsua_conf_get_port_info(from, &info) != PJ_SUCCESS) { return false; }
                    return std::find(info.listeners, info.listeners + info.listener_cnt, to) != info.listeners + info.listener_cnt;
                };
                const auto first = pjsua_call_get_conf_port(all[all.size() - 2].slot);
                const auto second = pjsua_call_get_conf_port(all.back().slot);
                line("CONFERENCEROUTES " + std::to_string(connected(first, second)) + " " + std::to_string(connected(second, first)));
                return PJ_SUCCESS;
            });
        }
        else if (verb == "MEDIA") { std::string play, record; command >> play >> record; status = tx_test_media(call, play.c_str(), record.c_str()); }
        else if (verb == "AEC") { status = aec(); }
        else if (verb == "REGISTER" || verb == "TLSREGISTER") {
            std::string server, password; command >> server >> password;
            tx_remove_account(account.uuid);
            tx_account registered = account;
            registered.domain = server.c_str(); registered.registrar = server.c_str(); registered.password = password.c_str(); registered.local_test = 0;
            if (verb == "TLSREGISTER") { registered.transport = 2; registered.srtp = 1; }
            status = tx_add_account(&registered);
        }
        else if (verb == "UNREGISTER") { status = tx_remove_account(account.uuid); }
        else if (verb == "REFRESH") { status = tx_refresh_account(account.uuid); }
        else if (verb == "NETWORK") { status = tx_network_changed(); }
        else if (verb == "TRANSFER") { status = all.size() >= 2 ? tx_transfer(all[all.size() - 2], all.back()) : -1; }
        else if (verb == "STALE") { call.generation += 1000; status = tx_hangup(call, 0); }
        else if (verb == "STATS") {
            tx_quality quality{}; status = tx_get_quality(call, &quality);
            if (!status) { line("STATS " + std::string(quality.codec) + " " + std::to_string(quality.rx_packets) + " " + std::to_string(quality.tx_packets) + " " + std::to_string(quality.lost_packets)); }
        } else { status = -1; }
        line("RESULT " + verb + " " + std::to_string(status));
    }
    tx_stop(); line("STOPPED"); return 0;
}
