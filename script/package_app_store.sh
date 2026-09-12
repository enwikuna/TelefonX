#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEAM_ID="AQYNC445G8"
APP_IDENTITY="${TELEFONX_CODESIGN_IDENTITY:-Apple Distribution: Enwikuna UG (haftungsbeschrankt) ($TEAM_ID)}"
INSTALLER_IDENTITY="${TELEFONX_INSTALLER_IDENTITY:-}"

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY="$(security find-identity -v -p basic | awk -F '"' -v team="$TEAM_ID" '
        ($2 ~ /^Mac Installer Distribution:/ || $2 ~ /^3rd Party Mac Developer Installer:/) && $2 ~ team { print $2; exit }
    ')"
fi
if [[ -z "$INSTALLER_IDENTITY" ]]; then
    echo "No Mac Installer Distribution identity for team $TEAM_ID is installed." >&2
    echo "Create and install that certificate, or set TELEFONX_INSTALLER_IDENTITY." >&2
    exit 1
fi

APP_BUNDLE="$(TELEFONX_CODESIGN_IDENTITY="$APP_IDENTITY" ./script/build_and_run.sh --app-store)"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
PACKAGE_DIR="$ROOT_DIR/dist/AppStore"
PACKAGE="$PACKAGE_DIR/TelefonX-$VERSION-$BUILD.pkg"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNED_ENTITLEMENTS="$(mktemp /tmp/TelefonXStoreEntitlements.XXXXXX)"
trap 'rm -f -- "$SIGNED_ENTITLEMENTS"' EXIT
codesign -d --entitlements :- "$APP_BUNDLE" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$SIGNED_ENTITLEMENTS")" == "true" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNED_ENTITLEMENTS")" == "$TEAM_ID.de.enwikuna.TelefonX" ]]
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$SIGNED_ENTITLEMENTS" 2>/dev/null || true)" == "true" ]]; then
    echo "Refusing to package a debuggable App Store build." >&2
    exit 1
fi
[[ "$(lipo -archs "$APP_BUNDLE/Contents/MacOS/TelefonX")" == "arm64" ]]
if otool -l "$APP_BUNDLE/Contents/MacOS/TelefonX" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | grep -Fq "$(xcode-select -p)"; then
    echo "Release executable still contains an Xcode runtime search path." >&2
    exit 1
fi
if strings "$APP_BUNDLE/Contents/MacOS/TelefonX" | grep -Eq 'PreviewHarness|PreviewControls|PreviewFixtures'; then
    echo "Release executable contains UI preview fixtures." >&2
    exit 1
fi
[[ -f "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy" ]]
[[ -d "$APP_BUNDLE/Contents/Resources/ThirdParty" ]]

rm -f "$PACKAGE"
productbuild \
    --component "$APP_BUNDLE" /Applications \
    --sign "$INSTALLER_IDENTITY" \
    "$PACKAGE"
pkgutil --check-signature "$PACKAGE"

echo "$PACKAGE"
echo "Local Mac App Store package checks passed. Validate and upload this package with Transporter."
