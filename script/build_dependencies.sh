#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p Vendor/Sources Vendor/Build Vendor/Install Vendor/Opus
if [[ ! -d Vendor/Sources/pjproject/.git ]]; then
  git clone --depth 1 --branch 2.17 https://github.com/pjsip/pjproject.git Vendor/Sources/pjproject
fi
if [[ ! -d Vendor/Sources/opus/.git ]]; then
  git clone --depth 1 --branch v1.5.2 https://github.com/xiph/opus.git Vendor/Sources/opus
fi
[[ "$(git -C Vendor/Sources/pjproject rev-parse HEAD)" == "5a457451fa2712ba18e12b01738e8ff3af2b26fd" ]]
[[ "$(git -C Vendor/Sources/opus rev-parse HEAD)" == "ddbe48383984d56acd9e1ab6a090c54ca6b735a6" ]]
certificate_patch="$ROOT_DIR/script/patches/pjsip-missing-certificate-oid.patch"
if git -C Vendor/Sources/pjproject apply --check "$certificate_patch" 2>/dev/null; then
  git -C Vendor/Sources/pjproject apply "$certificate_patch"
else
  git -C Vendor/Sources/pjproject apply --reverse --check "$certificate_patch"
fi
cmake -S Vendor/Sources/opus -B Vendor/Build/opus \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_INSTALL_PREFIX="$ROOT_DIR/Vendor/Opus" -DBUILD_SHARED_LIBS=OFF -DOPUS_BUILD_TESTING=OFF
cmake --build Vendor/Build/opus --parallel 8
cmake --install Vendor/Build/opus
# Use upstream's mature Autoconf path: the experimental CMake path does not yet
# implement Apple's TLS backend and excludes WebRTC AEC3 on macOS.
cp script/pj_config_site.h Vendor/Sources/pjproject/pjlib/include/pj/config_site.h
(
  cd Vendor/Sources/pjproject
  ./configure --prefix="$ROOT_DIR/Vendor/Install" --with-opus="$ROOT_DIR/Vendor/Opus" \
    --disable-video --disable-libyuv --disable-g7221-codec --disable-gsm-codec \
    --disable-ilbc-codec --disable-speex-aec --disable-l16-codec --enable-speex-resample \
    --disable-libwebrtc --enable-libwebrtc-aec3 \
    CC="clang -Wno-deprecated-declarations" \
    CFLAGS="-arch arm64 -O2 -mmacosx-version-min=26.0" \
    CXXFLAGS="-arch arm64 -O2 -mmacosx-version-min=26.0"
  make clean
  make dep
  make -j8 lib
  make install
)
if ! rg -q '^#define PJ_HAS_SSL_SOCK 1' Vendor/Install/include/pj/compat/os_auto.h; then
  echo "TLS was not built. Refusing an incomplete telephony engine." >&2
  exit 1
fi
cp Vendor/Opus/lib/libopus.a Vendor/Install/lib/libopus.a
# A single static archive keeps all dependencies inside the app; no Homebrew runtime paths.
# Explicit allow-list: stale archives from an older toolchain/configuration must
# never silently reintroduce a codec, architecture or license dependency.
target_name="$(sed -n 's/^export TARGET_NAME := //p' Vendor/Sources/pjproject/build.mak)"
[[ "$target_name" == aarch64-apple-* ]]
libs=(Vendor/Install/lib/libopus.a)
for component in pj pjlib-util pjmedia pjmedia-audiodev pjmedia-codec pjmedia-videodev pjnath pjsip pjsip-simple pjsip-ua pjsua speex srtp webrtc-aec3; do
  file="Vendor/Install/lib/lib${component}-${target_name}.a"
  [[ -f "$file" ]] || { echo "Missing library: $file" >&2; exit 1; }
  libs+=("$file")
done
/usr/bin/libtool -static -o Vendor/Install/lib/libTelefonSIP.a "${libs[@]}"
