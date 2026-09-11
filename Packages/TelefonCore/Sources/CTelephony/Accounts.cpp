#include "Engine.hpp"
#include <algorithm>

namespace tx {
void onRegistration(pjsua_acc_id slot) {
    engine.schedule([slot] {
        pjsua_acc_info info;
        if (pjsua_acc_get_info(slot, &info) != PJ_SUCCESS || engine.accounts[slot].empty()) { return; }
        tx_event event{}; event.kind = 1; event.account = engine.accounts[slot].c_str();
        event.status = info.status; event.state = info.has_registration && info.expires > 0 && info.status == 200;
        engine.emit(event);
    });
}
void onSDP(pjsua_call_id id, pjmedia_sdp_session *sdp, pj_pool_t *, const pjmedia_sdp_session *) {
    pjsua_call_info info;
    if (pjsua_call_get_info(id, &info) != PJ_SUCCESS || !engine.g711[info.acc_id]) { return; }
    for (unsigned i = 0; i < sdp->media_count; ++i) {
        auto *media = sdp->media[i];
        if (pj_strcmp2(&media->desc.media, "audio")) { continue; }
        unsigned kept = 0;
        for (unsigned j = 0; j < media->desc.fmt_count; ++j) {
            auto format = media->desc.fmt[j];
            auto attr = pjmedia_sdp_media_find_attr2(media, "rtpmap", &format);
            const bool event = attr && string(attr->value).find("telephone-event") != std::string::npos;
            if (pj_strcmp2(&format, "0") == 0 || pj_strcmp2(&format, "8") == 0 || event) {
                media->desc.fmt[kept++] = format;
            } else {
                if (attr) { pjmedia_sdp_attr_remove(&media->attr_count, media->attr, attr); }
                auto fmtp = pjmedia_sdp_media_find_attr2(media, "fmtp", &format);
                if (fmtp) { pjmedia_sdp_attr_remove(&media->attr_count, media->attr, fmtp); }
            }
        }
        media->desc.fmt_count = kept;
    }
}
}
extern "C" int32_t tx_add_account(const tx_account *account) {
    if (!account) { return PJ_EINVAL; }
    // The synchronous command completes before the caller releases these strings.
    return tx::engine.invoke([account]() -> int {
        using namespace tx;
        if (engine.account(account->uuid) != PJSUA_INVALID_ID) { return PJ_EEXISTS; }
        pjsua_acc_config cfg; pjsua_acc_config_default(&cfg);
        std::string identity = "sip:" + std::string(account->username) + "@" + account->domain;
        std::string registrar = "sip:" + std::string(account->registrar[0] ? account->registrar : account->domain);
        std::string proxy;
        const char *transport = account->transport == 2 ? "tls" : (account->transport == 1 ? "tcp" : "udp");
        registrar += ";transport=" + std::string(transport);
        cfg.id = pj(identity); cfg.reg_uri = account->local_test ? pj_str(const_cast<char *>("")) : pj(registrar);
        cfg.reg_timeout = account->interval; cfg.reg_retry_interval = 15; cfg.reg_first_retry_interval = 2;
        cfg.reg_delay_before_refresh = 15; cfg.register_on_acc_add = PJ_FALSE;
        cfg.cred_count = 1; cfg.cred_info[0].realm = pj_str(const_cast<char *>("*"));
        cfg.cred_info[0].scheme = pj_str(const_cast<char *>("digest"));
        cfg.cred_info[0].username = pj_str(const_cast<char *>(account->authname[0] ? account->authname : account->username));
        cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
        cfg.cred_info[0].data = pj_str(const_cast<char *>(account->password));
        const int index = account->transport + (account->domain[0] == '[' ? 3 : 0);
        cfg.transport_id = engine.transports[index];
        if (cfg.transport_id == PJSUA_INVALID_ID) { return PJ_EAFNOTSUP; }
        cfg.use_srtp = account->srtp ? PJMEDIA_SRTP_MANDATORY : PJMEDIA_SRTP_DISABLED;
        cfg.srtp_secure_signaling = 1;
        cfg.ice_cfg_use = PJSUA_ICE_CONFIG_USE_CUSTOM; cfg.ice_cfg.enable_ice = account->ice;
        cfg.sip_stun_use = PJSUA_STUN_USE_DISABLED; cfg.media_stun_use = PJSUA_STUN_USE_DISABLED;
        cfg.allow_contact_rewrite = PJ_TRUE; cfg.allow_via_rewrite = PJ_TRUE; cfg.allow_sdp_nat_rewrite = PJ_TRUE;
        cfg.rtp_cfg.qos_type = PJ_QOS_TYPE_VOICE;
        if (account->local_test) {
            cfg.rtp_cfg.bound_addr = pj_str(const_cast<char *>("127.0.0.1"));
            cfg.rtp_cfg.public_addr = cfg.rtp_cfg.bound_addr;
        }
        if (account->proxy[0]) {
            proxy = "sip:" + std::string(account->proxy) + ";transport=" + transport + ";lr";
            cfg.proxy_cnt = 1; cfg.proxy[0] = pj(proxy);
        }
        // PJSIP has a process-global STUN list. Different per-account STUN servers
        // are intentionally not accepted by this first adapter.
        if (account->stun[0]) { return PJ_ENOTSUP; }
        pjsua_acc_id slot;
        auto status = pjsua_acc_add(&cfg, PJ_FALSE, &slot);
        if (status != PJ_SUCCESS) { return status; }
        engine.accounts[slot] = account->uuid; engine.g711[slot] = account->g711_only;
        if (account->local_test) { onRegistration(slot); return PJ_SUCCESS; }
        status = pjsua_acc_set_registration(slot, PJ_TRUE);
        if (status != PJ_SUCCESS) { pjsua_acc_del(slot); engine.accounts[slot].clear(); }
        return status;
    });
}
extern "C" int32_t tx_remove_account(const char *uuid) {
    if (!uuid) { return PJ_EINVAL; }
    return tx::engine.invoke([uuid]() -> int {
        auto slot = tx::engine.account(uuid);
        if (slot == PJSUA_INVALID_ID) { return PJ_SUCCESS; }
        auto status = pjsua_acc_del2(slot, 0);
        if (status == PJ_SUCCESS) { tx::engine.accounts[slot].clear(); }
        return status;
    });
}
extern "C" int32_t tx_refresh_account(const char *uuid) {
    if (!uuid) { return PJ_EINVAL; }
    return tx::engine.invoke([uuid]() -> int {
        const auto slot = tx::engine.account(uuid);
        if (slot == PJSUA_INVALID_ID) { return PJ_ENOTFOUND; }
        return pjsua_acc_set_registration(slot, PJ_TRUE);
    });
}
