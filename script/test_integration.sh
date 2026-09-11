#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build
clang++ -std=c++17 -arch arm64 -mmacosx-version-min=26.0 -O1 -g \
    -I Vendor/Install/include -I Packages/TelefonCore/Sources/CTelephony/include \
    -I Packages/TelefonCore/Sources/CTelephony \
    Tests/Integration/sip_peer.cpp Packages/TelefonCore/Sources/CTelephony/Engine.cpp \
    Packages/TelefonCore/Sources/CTelephony/Accounts.cpp Packages/TelefonCore/Sources/CTelephony/Calls.cpp \
    Vendor/Install/lib/libTelefonSIP.a -framework AudioToolbox -framework CoreAudio \
    -framework Security -framework CoreFoundation -framework AVFoundation -framework Foundation -framework Network \
    -o .build/sip-peer
if [[ "${1:-}" == "--tls-only" ]]; then
    python3 Tests/Integration/tls_validation.py
    exit 0
fi
if [[ "${1:-}" == "--hold-music-only" ]]; then
    python3 Tests/Integration/hold_music.py
    exit 0
fi
python3 Tests/Integration/loopback.py "$@"
python3 Tests/Integration/hold_music.py
python3 Tests/Integration/conference.py
python3 Tests/Integration/registration.py
python3 Tests/Integration/transfer.py
python3 Tests/Integration/tls_validation.py
