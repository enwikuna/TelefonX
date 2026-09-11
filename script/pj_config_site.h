#define PJSUA_MAX_CALLS 32
#define PJSUA_MAX_ACC 32
#define PJ_HAS_IPV6 1
#define PJMEDIA_HAS_VIDEO 0
#define PJMEDIA_AUDIO_DEV_HAS_PORTAUDIO 0
#define PJMEDIA_HAS_SPEEX_AEC 0
#define PJMEDIA_HAS_SPEEX_CODEC 0
#define PJMEDIA_RTP_PT_TELEPHONE_EVENTS 101
// macOS 26+ uses Apple's current Network framework, not deprecated SecureTransport.
#undef PJ_SSL_SOCK_IMP
#define PJ_SSL_SOCK_IMP PJ_SSL_SOCK_IMP_APPLE
