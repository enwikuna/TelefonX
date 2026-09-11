#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TELEFONX_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build
APP_BUNDLE="$ROOT_DIR/dist/TelefonX.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/TelefonX"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
ARCHIVE="$ROOT_DIR/dist/TelefonX-${VERSION}-${BUILD}-macOS26-arm64-test.zip"
CHECKSUM="$ARCHIVE.sha256"

if [[ "$(lipo -archs "$EXECUTABLE")" != arm64 ]]; then
    echo "Release executable must contain only arm64." >&2
    exit 1
fi
if [[ "$(lipo -archs "$ROOT_DIR/Vendor/Install/lib/libTelefonSIP.a")" != arm64 ]]; then
    echo "SIP library must contain only arm64." >&2
    exit 1
fi
if [[ "$(vtool -show-build "$EXECUTABLE" | awk '/minos/{print $2; exit}')" != 26.0 ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist")" != 26.0 ]]; then
    echo "Release bundle must target macOS 26.0." >&2
    exit 1
fi
UNEXPECTED_RPATHS="$(otool -l "$EXECUTABLE" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | grep -vFx '/usr/lib/swift' || true)"
if [[ -n "$UNEXPECTED_RPATHS" ]]; then
    echo "Release executable contains an unexpected RPATH: $UNEXPECTED_RPATHS" >&2
    exit 1
fi
UNEXPECTED_DEPENDENCIES="$(otool -L "$EXECUTABLE" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
if [[ -n "$UNEXPECTED_DEPENDENCIES" ]]; then
    echo "Release executable contains a non-system dependency: $UNEXPECTED_DEPENDENCIES" >&2
    exit 1
fi
if otool -l "$EXECUTABLE" | grep '__DWARF' >/dev/null; then
    echo "Release executable still contains DWARF debug sections." >&2
    exit 1
fi
if strings "$EXECUTABLE" | grep -Eq 'PreviewHarness|preview-apple-|UI-Vorschau'; then
    echo "Release executable contains UI preview fixtures." >&2
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_BUNDLE/Contents/Info.plist")" != TelefonXAppIcon ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_BUNDLE/Contents/Info.plist")" != TelefonXAppIcon ]]; then
    echo "Release bundle references an unexpected app icon." >&2
    exit 1
fi

rm -f "$ARCHIVE" "$CHECKSUM"
ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
codesign --verify --deep --strict "$APP_BUNDLE"
if zipinfo -1 "$ARCHIVE" | grep -Eq '^__MACOSX/|TelefonXAppIconV[0-9]'; then
    echo "Archive contains Finder metadata or a legacy icon." >&2
    exit 1
fi
(
    cd "$ROOT_DIR/dist"
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo "$ARCHIVE"
echo "$CHECKSUM"

# Packaging may target a different registered Mac. Always restore and launch a
# locally provisioned production build after the portable archive is complete.
env -u TELEFONX_TARGET_DEVICE_ID -u TELEFONX_PROVISIONING_PROFILE \
    TELEFONX_BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify
