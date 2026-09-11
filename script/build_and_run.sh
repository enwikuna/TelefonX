#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--build|--debug|--logs|--telemetry|--preview) ;; *) echo "Usage: $0 [--build|--verify|--debug|--logs|--telemetry|--preview]" >&2; exit 2 ;; esac
BUILD_CONFIGURATION="${TELEFONX_BUILD_CONFIGURATION:-debug}"
case "$BUILD_CONFIGURATION" in debug|release) ;; *) echo "TELEFONX_BUILD_CONFIGURATION must be debug or release." >&2; exit 2 ;; esac
APP_NAME="TelefonX"
BUNDLE_ID="de.enwikuna.TelefonX"
TEAM_ID="AQYNC445G8"
ENTITLEMENTS="script/TelefonX.entitlements"
SIGNING_IDENTITY="${TELEFONX_CODESIGN_IDENTITY:-}"
PROVISIONING_PROFILE="${TELEFONX_PROVISIONING_PROFILE:-}"
BUILD_TEMP="$(mktemp -d /tmp/TelefonXBuild.XXXXXX)"
trap 'rm -rf -- "$BUILD_TEMP"' EXIT
if [[ "$MODE" == --preview ]]; then
    APP_NAME="TelefonXPreview"
    BUNDLE_ID="de.enwikuna.TelefonX.preview"
    ENTITLEMENTS="script/Preview.entitlements"
    SIGNING_IDENTITY="-"
fi
if [[ "$(uname -m)" != arm64 ]]; then echo "TelefonX requires Apple Silicon." >&2; exit 1; fi
if [[ "$MODE" != --preview ]]; then
    TARGET_DEVICE_ID="${TELEFONX_TARGET_DEVICE_ID:-}"
    if [[ -z "$TARGET_DEVICE_ID" ]]; then
        TARGET_DEVICE_ID="$(system_profiler SPHardwareDataType | awk -F': ' '/Provisioning UDID/{print $2; exit}')"
        if [[ -z "$TARGET_DEVICE_ID" ]]; then
            echo "Could not determine this Mac's Provisioning UDID." >&2
            exit 1
        fi
    fi

    profile_matches_app() {
        local candidate="$1"
        local decoded="$BUILD_TEMP/candidate.plist"
        security cms -D -i "$candidate" > "$decoded" 2>/dev/null || return 1
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$decoded" 2>/dev/null)" == "$TEAM_ID.$BUNDLE_ID" ]] || return 1
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.usernotifications.communication' "$decoded" 2>/dev/null)" == "true" ]] || return 1
        /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' "$decoded" 2>/dev/null | grep -Fq "iCloud.$BUNDLE_ID" || return 1
        /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$decoded" 2>/dev/null | grep -Fq "$TARGET_DEVICE_ID" || return 1
        [[ "$(plutil -extract ExpirationDate raw "$decoded" 2>/dev/null)" > "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]] || return 1
    }

    if [[ -n "$PROVISIONING_PROFILE" ]]; then
        if [[ ! -f "$PROVISIONING_PROFILE" ]] || ! profile_matches_app "$PROVISIONING_PROFILE"; then
            echo "TELEFONX_PROVISIONING_PROFILE is not a valid current TelefonX development profile for the target Mac." >&2
            exit 1
        fi
    else
        newest_profile_mtime=0
        shopt -s nullglob
        for profile_dir in \
            "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
            "$HOME/Library/MobileDevice/Provisioning Profiles"; do
            [[ -d "$profile_dir" ]] || continue
            for candidate in "$profile_dir"/*.provisionprofile "$profile_dir"/*.mobileprovision; do
                if profile_matches_app "$candidate"; then
                    candidate_mtime="$(stat -f %m "$candidate")"
                    if (( candidate_mtime > newest_profile_mtime )); then
                        PROVISIONING_PROFILE="$candidate"
                        newest_profile_mtime="$candidate_mtime"
                    fi
                fi
            done
        done
        shopt -u nullglob
        if [[ -z "$PROVISIONING_PROFILE" ]]; then
            echo "No valid TelefonX development profile for the target Mac was found. Install it in Xcode or set TELEFONX_PROVISIONING_PROFILE." >&2
            exit 1
        fi
    fi

    PROFILE_PLIST="$BUILD_TEMP/profile.plist"
    security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"
    PROFILE_CERTIFICATE_FINGERPRINTS=()
    certificate_index=0
    while certificate_data="$(plutil -extract "DeveloperCertificates.$certificate_index" raw "$PROFILE_PLIST" 2>/dev/null)"; do
        PROFILE_CERT="$BUILD_TEMP/profile-certificate-$certificate_index.der"
        printf '%s' "$certificate_data" | base64 -D > "$PROFILE_CERT"
        PROFILE_CERTIFICATE_FINGERPRINTS+=("$(openssl x509 -inform DER -in "$PROFILE_CERT" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)")
        certificate_index=$((certificate_index + 1))
    done
    if (( ${#PROFILE_CERTIFICATE_FINGERPRINTS[@]} == 0 )); then
        echo "The TelefonX provisioning profile contains no signing certificate." >&2
        exit 1
    fi

    AVAILABLE_IDENTITIES="$(security find-identity -p codesigning -v)"
    if [[ -n "$SIGNING_IDENTITY" ]]; then
        RESOLVED_SIGNING_IDENTITY="$(printf '%s\n' "$AVAILABLE_IDENTITIES" | awk -F '"' -v identity="$SIGNING_IDENTITY" '$2 == identity {print $1; exit}' | awk '{print $2}')"
        if [[ -z "$RESOLVED_SIGNING_IDENTITY" ]] && printf '%s\n' "$AVAILABLE_IDENTITIES" | grep -Fq "$SIGNING_IDENTITY"; then
            RESOLVED_SIGNING_IDENTITY="$SIGNING_IDENTITY"
        fi
        SIGNING_IDENTITY="$RESOLVED_SIGNING_IDENTITY"
    else
        for fingerprint in "${PROFILE_CERTIFICATE_FINGERPRINTS[@]}"; do
            if printf '%s\n' "$AVAILABLE_IDENTITIES" | grep -Fq "$fingerprint"; then
                SIGNING_IDENTITY="$fingerprint"
                break
            fi
        done
    fi
    identity_is_allowed=false
    for fingerprint in "${PROFILE_CERTIFICATE_FINGERPRINTS[@]}"; do
        if [[ "$SIGNING_IDENTITY" == "$fingerprint" ]]; then
            identity_is_allowed=true
            break
        fi
    done
    if [[ "$identity_is_allowed" != true ]]; then
        echo "No locally available signing identity permitted by the TelefonX provisioning profile was selected." >&2
        exit 1
    fi

    SIGNING_ENTITLEMENTS="$BUILD_TEMP/TelefonX.entitlements"
    cp "$ENTITLEMENTS" "$SIGNING_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$SIGNING_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$SIGNING_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-environment string Development' "$SIGNING_ENTITLEMENTS"
    ENTITLEMENTS="$SIGNING_ENTITLEMENTS"
fi
if [[ ! -f Vendor/Install/lib/libTelefonSIP.a ]]; then ./script/build_dependencies.sh; fi
# Graceful quit preserves history and lets the app ask about active calls.
if pgrep -x "$APP_NAME" >/dev/null; then
    if ! osascript \
        -e 'with timeout of 5 seconds' \
        -e "tell application id \"$BUNDLE_ID\" to quit" \
        -e 'end timeout'; then
        echo "$APP_NAME did not immediately accept the quit request; waiting for an open call confirmation." >&2
    fi
    for attempt in {1..20}; do if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi; sleep 0.5; done
    if pgrep -x "$APP_NAME" >/dev/null; then echo "$APP_NAME is still running; build cancelled without forcing calls to end." >&2; exit 1; fi
fi
SWIFT_BUILD_ARGUMENTS=(-c "$BUILD_CONFIGURATION")
if [[ "$BUILD_CONFIGURATION" == release ]]; then
    SWIFT_BUILD_ARGUMENTS+=(--disable-local-rpath)
fi
./script/swift.sh build "${SWIFT_BUILD_ARGUMENTS[@]}"
BIN_DIR="$(./script/swift.sh build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
if [[ -d "$APP_BUNDLE" ]]; then
    rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/TelefonX" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ "$BUILD_CONFIGURATION" == release ]]; then
    strip -S "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    DEVELOPER_DIR="$(xcode-select -p)"
    while IFS= read -r rpath; do
        case "$rpath" in
            "$DEVELOPER_DIR"/*) install_name_tool -delete_rpath "$rpath" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
        esac
    done < <(otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
fi
cp script/Info.plist "$APP_BUNDLE/Contents/Info.plist"
CURRENT_YEAR="$(date +%Y)"
plutil -replace NSHumanReadableCopyright \
    -string "Copyright © 2025–$CURRENT_YEAR Enwikuna. All rights reserved." \
    "$APP_BUNDLE/Contents/Info.plist"
if [[ "$MODE" == --preview ]]; then
    plutil -replace CFBundleExecutable -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
    plutil -replace CFBundleName -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
    plutil -remove CFBundleURLTypes "$APP_BUNDLE/Contents/Info.plist"
    plutil -remove NSServices "$APP_BUNDLE/Contents/Info.plist"
fi
ditto App/Resources "$APP_BUNDLE/Contents/Resources"
ASSET_OUTPUT="$BUILD_TEMP/AssetCatalog"
mkdir -p "$ASSET_OUTPUT"
ASSET_INFO="$ASSET_OUTPUT/asset-info.plist"
xcrun actool Design/AppIcon/TelefonXAppIcon.icon \
    --compile "$ASSET_OUTPUT" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon TelefonXAppIcon \
    --output-partial-info-plist "$ASSET_INFO" >/dev/null
if [[ ! -f "$ASSET_OUTPUT/TelefonXAppIcon.icns" || ! -f "$ASSET_OUTPUT/Assets.car" ]]; then
    echo "Icon Composer compilation did not produce TelefonXAppIcon.icns and Assets.car." >&2
    exit 1
fi
ditto "$ASSET_OUTPUT/TelefonXAppIcon.icns" "$APP_BUNDLE/Contents/Resources/TelefonXAppIcon.icns"
ditto "$ASSET_OUTPUT/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
NOTICES="$APP_BUNDLE/Contents/Resources/ThirdParty"
mkdir -p "$NOTICES"
cp Vendor/Sources/pjproject/COPYING "$NOTICES/PJSIP.txt"
cp Vendor/Sources/opus/COPYING "$NOTICES/Opus.txt"
cp Vendor/Sources/pjproject/third_party/speex/COPYING "$NOTICES/Speex.txt"
cp Vendor/Sources/pjproject/third_party/srtp/LICENSE "$NOTICES/libsrtp.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/LICENSE "$NOTICES/WebRTC-AEC3.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/src/absl/LICENSE "$NOTICES/Abseil.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/src/common_audio/third_party/ooura/LICENSE "$NOTICES/Ooura.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/src/common_audio/third_party/spl_sqrt_floor/LICENSE "$NOTICES/Sqrt.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/src/third_party/rnnoise/COPYING "$NOTICES/RNNoise.txt"
cp Vendor/Sources/pjproject/third_party/webrtc_aec3/src/third_party/pffft/src/pffft.h "$NOTICES/PFFFT-header.txt"
cp LICENSE "$NOTICES/TelefonX-GPL-3.0.txt"
if [[ "$MODE" != --preview ]]; then
    cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
fi
xattr -cr "$APP_BUNDLE"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
if [[ "$MODE" != --preview ]]; then
    SIGNED_ENTITLEMENTS="$BUILD_TEMP/signed-entitlements.plist"
    EMBEDDED_PROFILE="$BUILD_TEMP/embedded-profile.plist"
    codesign -d --entitlements :- "$APP_BUNDLE" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
    security cms -D -i "$APP_BUNDLE/Contents/embedded.provisionprofile" > "$EMBEDDED_PROFILE"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNED_ENTITLEMENTS")" == "$TEAM_ID.$BUNDLE_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.usernotifications.communication' "$SIGNED_ENTITLEMENTS")" == "true" ]]
    /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers' "$SIGNED_ENTITLEMENTS" | grep -Fq "iCloud.$BUNDLE_ID"
    [[ "$(plutil -extract UUID raw "$EMBEDDED_PROFILE")" == "$(plutil -extract UUID raw "$PROFILE_PLIST")" ]]
fi
if [[ "$MODE" != --preview && "$MODE" != --build ]]; then
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$LSREGISTER" -f "$APP_BUNDLE"
    /System/Library/CoreServices/pbs -update
fi
case "$MODE" in
    --build) echo "$APP_BUNDLE" ;;
    run) open -n "$APP_BUNDLE" ;;
    --preview) open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "Isolated UI preview launched successfully." ;;
    --verify) open -n "$APP_BUNDLE"; sleep 2; pgrep -x TelefonX >/dev/null; echo "TelefonX launched successfully." ;;
    --debug) open -n "$APP_BUNDLE"; lldb -n TelefonX ;;
    --logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "TelefonX"' ;;
    --telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "de.enwikuna.TelefonX"' ;;
esac
