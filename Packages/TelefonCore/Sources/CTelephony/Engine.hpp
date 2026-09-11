#pragma once
#include "TelefonSIP.h"
#define PJ_AUTOCONF 1
#include <pjsua-lib/pjsua.h>
#include <pjmedia-codec/opus.h>
#include <pjmedia/transport_srtp.h>
#include <array>
#include <atomic>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <string>
#include <thread>

namespace tx {
struct CallData {
    uint64_t generation = 0;
    std::string account;
    bool muted = false;
    bool terminal = true;
    int player = PJSUA_INVALID_ID;
    int recorder = PJSUA_INVALID_ID;
    int holdPlayer = PJSUA_INVALID_ID;
    bool localMusicHold = false;
    bool holdRequested = false;
    bool holdPending = false;
    bool holdPrevious = false;
    int holdError = PJ_SUCCESS;
    std::array<bool, PJSUA_MAX_CALLS> conferencePeers{};
};
struct Engine {
    tx_callback callback = nullptr;
    void *context = nullptr;
    std::thread worker;
    std::thread::id owner;
    std::mutex mutex;
    std::deque<std::function<void()>> jobs;
    std::atomic<bool> accepting{false};
    std::atomic<bool> stopping{false};
    std::array<CallData, PJSUA_MAX_CALLS> calls;
    std::array<std::string, PJSUA_MAX_ACC> accounts;
    std::array<bool, PJSUA_MAX_ACC> g711{};
    std::array<pjsua_transport_id, 6> transports{};
    uint64_t nextGeneration = 1;
    bool nullAudio = false;
    bool realAudioActive = false;
    bool releaseAudioPending = false;
    std::string holdMusic;
    int input = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
    int output = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
    int invoke(std::function<int()> action);
    void schedule(std::function<void()> action);
    void emit(tx_event event);
    bool valid(tx_call handle) const;
    tx_call handle(int slot);
    int account(const std::string &uuid) const;
    int initialize(int port);
    int connectAudio(int slot);
    int updateConferenceAudio(int slot);
    void clearConference(int slot);
    void stopHoldMusic(int slot);
    void releaseAudioIfIdle();
};
extern Engine engine;
std::string string(pj_str_t value);
pj_str_t pj(const std::string &value);
void onCallState(pjsua_call_id, pjsip_event *);
void onIncoming(pjsua_acc_id, pjsua_call_id, pjsip_rx_data *);
void onMedia(pjsua_call_id);
void onRegistration(pjsua_acc_id);
void onSDP(pjsua_call_id, pjmedia_sdp_session *, pj_pool_t *, const pjmedia_sdp_session *);
void onTransfer(pjsua_call_id, int, const pj_str_t *, pj_bool_t, pj_bool_t *);
void onDTMF(pjsua_call_id, const pjsua_dtmf_info *);
void onTransaction(pjsua_call_id, pjsip_transaction *, pjsip_event *);
}
