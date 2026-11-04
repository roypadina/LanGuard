#!/bin/sh
# Universal release build + zip -> build/LanGuard.zip, plus build/appcast.xml (Sparkle feed) when the
# maintainer's Sparkle EdDSA key is in the login keychain. Upload both to the release.
# The build is signed ad hoc; the bundle is then
# re-signed with a stable identity when one is available, so macOS keeps permission grants across
# updates. Identity: $LANGUARD_SIGN_IDENTITY, else "KeyLayoutSwitcher Dev" if in the keychain,
# else stays ad hoc (CI, contributors).
set -e
cd "$(dirname "$0")/.."
xcodebuild -workspace LanGuard.xcworkspace -scheme LanGuard -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build build
APP=build/Build/Products/Release/LanGuard.app
ID="${LANGUARD_SIGN_IDENTITY:-}"
if [ -z "$ID" ] && security find-identity -v -p codesigning | grep -q "KeyLayoutSwitcher Dev"; then
  ID="KeyLayoutSwitcher Dev"
fi
if [ -n "$ID" ]; then
  # Inside-out: Sparkle's nested helpers and framework, then the app (the root helper is a shell script).
  find "$APP/Contents" -depth \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' -o -name '*.dylib' \
    -o \( -name Autoupdate -type f \) \) -not -path "$APP" | while read -r f; do
    codesign --force --preserve-metadata=identifier,entitlements,flags -s "$ID" "$f"
  done
  codesign --force -s "$ID" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "No signing identity found: leaving the build ad-hoc signed" >&2
fi
rm -f build/LanGuard.zip
ditto -c -k --keepParent "$APP" build/LanGuard.zip
echo build/LanGuard.zip

# Sparkle feed for this release only (served as the latest release's appcast.xml asset).
# Only with the key whose public half the app ships; any other key makes a feed every copy refuses.
SPARKLE=build/SourcePackages/artifacts/sparkle/Sparkle/bin
if [ "$("$SPARKLE/generate_keys" -p 2>/dev/null)" = "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")" ]; then
  VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
  D=$(mktemp -d)
  cp build/LanGuard.zip "$D/"
  # This version's CHANGELOG section becomes the update prompt's release notes.
  awk -v v="## [$VER]" 'index($0, v) == 1 {f=1; next} /^## \[/ {f=0} f' CHANGELOG.md > "$D/LanGuard.md"
  rm -f build/appcast.xml  # generate_appcast merges into an existing file
  "$SPARKLE/generate_appcast" --embed-release-notes \
    --download-url-prefix "https://github.com/roypadina/LanGuard/releases/download/v$VER/" \
    -o build/appcast.xml "$D"
  rm -rf "$D"
  echo build/appcast.xml
else
  echo "Sparkle signing key (matching SUPublicEDKey) not in the keychain: no appcast.xml"
fi
