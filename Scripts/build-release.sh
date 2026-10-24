#!/bin/sh
# Universal release build + zip -> build/LanGuard.zip. The build is signed ad hoc; the bundle is then
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
  # The only Mach-O is the main binary (the root helper is a shell script), so one pass signs it all.
  codesign --force --deep -s "$ID" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "No signing identity found: leaving the build ad-hoc signed" >&2
fi
rm -f build/LanGuard.zip
ditto -c -k --keepParent "$APP" build/LanGuard.zip
echo build/LanGuard.zip
