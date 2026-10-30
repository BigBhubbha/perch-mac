#!/bin/bash
# Builds "Perch.app" without Xcode. Needs the Command Line Tools (xcode-select --install) and cmake.
#   ./build.sh            build a release app into ./build/Perch.app
#   ./build.sh --run      build, then open it
#   ./build.sh --install  build, then copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Perch"
EXEC="Perch"
BUNDLE_ID="com.bigbhubbha.perch"
OUT="build"
APP="$OUT/$APP_NAME.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This builds a Mac app, so run it on a Mac." >&2
  exit 1
fi

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  echo "==> Compiling (universal: arm64 + x86_64, release)"
else
  ARCH_FLAGS=(--arch "$(uname -m)")
  echo "==> Compiling ($(uname -m), release)"
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> Building the now playing helper"
./scripts/build_adapter.sh
MRA=".build/mediaremote-adapter"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
# The agent board read key comes from CI (a GitHub secret), never from the repo.
if [[ -n "${PERCH_BOARD_READ_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :PerchBoardReadKey $PERCH_BOARD_READ_KEY" "$APP/Contents/Info.plist"
fi

# Sparkle ships as a prebuilt framework; SwiftPM links it but does not embed it.
SPARKLE_FW=""
for candidate in \
    "$BIN_DIR/Sparkle.framework" \
    "$BIN_DIR/PackageFrameworks/Sparkle.framework" \
    $(find .build/artifacts -type d -path "*Sparkle.xcframework/macos-*/Sparkle.framework" 2>/dev/null); do
  if [[ -d "$candidate" ]]; then SPARKLE_FW="$candidate"; break; fi
done
[[ -n "$SPARKLE_FW" ]] || { echo "Could not find Sparkle.framework after the build." >&2; exit 1; }
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/$EXEC" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$EXEC"
fi

# Now playing helper: the framework is loaded by /usr/bin/perl, not by Perch, so it is bundled but not linked.
ditto "$MRA/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$MRA/build/MediaRemoteAdapterTestClient" "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
cp "$MRA/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp Resources/MEDIAREMOTE-ADAPTER-LICENSE.txt "$APP/Contents/Resources/"

cp Resources/Sounds/*.wav "$APP/Contents/Resources/Sounds/"
if command -v iconutil >/dev/null 2>&1 && [[ -d Resources/AppIcon.iconset ]]; then
  iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf "APPL????" > "$APP/Contents/PkgInfo"

# Signing. CI sets SIGN_IDENTITY to the SHA-1 of the long-lived "Perch Signing" certificate.
# That gives a fixed designated requirement (bundle id + certificate), so macOS keeps
# permissions (like Automation for Spotify) across every update.
SIGN="${SIGN_IDENTITY:--}"
KEYCHAIN_ARGS=()
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN"); fi
sign() { codesign --force --sign "$SIGN" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --timestamp=none "$@"; }
[[ "$SIGN" == "-" ]] && echo "==> Signing (ad hoc)" || echo "==> Signing with certificate $SIGN"
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$SP/XPCServices/Installer.xpc" "$SP/XPCServices/Downloader.xpc" "$SP/Autoupdate" "$SP/Updater.app"; do
  if [[ -e "$item" ]]; then sign --preserve-metadata=identifier,entitlements "$item"; fi
done
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
sign --identifier "$BUNDLE_ID.adapter-test" "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
if [[ "$SIGN" == "-" ]]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
else
  REQ="designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGN\""
  sign --identifier "$BUNDLE_ID" --requirements "=$REQ" "$APP"
fi
codesign --verify --verbose=1 "$APP" || true
echo ""
echo "Built: $(pwd)/$APP"

case "${1:-}" in
  --run) pkill -x "$EXEC" 2>/dev/null || true; open "$APP" ;;
  --install)
    pkill -x "$EXEC" 2>/dev/null || true
    ditto "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app" ;;
esac
