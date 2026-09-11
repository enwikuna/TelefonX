#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct { int32_t slot; uint64_t generation; } tx_call;
typedef struct {
    int32_t kind; /* 1 registration, 2 call, 3 media, 4 transfer, 5 failure, 6 DTMF */
    tx_call call;
    const char *account;
    const char *remote;
    int32_t state;
    int32_t status;
    int32_t incoming;
    int32_t held;
    int32_t remote_held;
    int32_t final;
} tx_event;
typedef void (*tx_callback)(const tx_event *, void *);
typedef struct {
    const char *uuid;
    const char *username;
    const char *authname;
    const char *password;
    const char *domain;
    const char *registrar;
    const char *proxy;
    const char *stun;
    int32_t transport; /* 0 UDP, 1 TCP, 2 TLS */
    int32_t srtp;
    int32_t ice;
    int32_t g711_only;
    int32_t interval;
    int32_t local_test; /* only used by isolated integration harness */
} tx_account;
typedef struct {
    char codec[64]; int32_t clock_rate; uint32_t rx_packets; uint32_t tx_packets;
    uint32_t lost_packets; double jitter_ms; double rtt_ms; int32_t srtp;
} tx_quality;
typedef struct { int32_t index; char name[128]; int32_t inputs; int32_t outputs; } tx_audio_device;

int32_t tx_start(tx_callback callback, void *context, int32_t port, int32_t null_audio);
void tx_stop(void);
int32_t tx_add_account(const tx_account *account);
int32_t tx_remove_account(const char *uuid);
int32_t tx_refresh_account(const char *uuid);
int32_t tx_make_call(const char *uuid, const char *uri, int32_t suppress_caller_id, tx_call *result);
int32_t tx_answer(tx_call call);
int32_t tx_hangup(tx_call call, int32_t decline);
int32_t tx_mute(tx_call call, int32_t muted);
int32_t tx_hold(tx_call call, int32_t held);
int32_t tx_hold_status(tx_call call, int32_t *held, int32_t *pending);
int32_t tx_set_hold_music(const char *wav);
int32_t tx_dtmf(tx_call call, const char *digits);
int32_t tx_conference(tx_call first, tx_call second, int32_t enabled);
int32_t tx_transfer(tx_call source, tx_call consultation);
int32_t tx_get_quality(tx_call call, tx_quality *result);
int32_t tx_audio_devices(tx_audio_device *devices, int32_t capacity, int32_t *count);
int32_t tx_set_audio(int32_t input, int32_t output);
int32_t tx_release_audio(void);
int32_t tx_network_changed(void);
/* File-based audio injection/capture used exclusively by the integration executable. */
int32_t tx_test_media(tx_call call, const char *play_wav, const char *record_wav);
#ifdef __cplusplus
}
#endif
