#!/bin/sh
# Perch installer. Paste into Terminal:
#   curl -fsSL https://raw.githubusercontent.com/BigBhubbha/perch-mac/main/scripts/install.sh | sh
#
# Why a script: Perch is not signed with a paid Apple Developer ID. On macOS 26 a copy downloaded by a
# browser carries a quarantine flag, and Gatekeeper can hold it before it starts: the Dock icon bounces
# forever and nothing opens. curl adds no quarantine flag, so this copy just opens.
#
# What it does:
#   1. stops any stuck Perch and moves old copies (Downloads, /Applications, the disk image) to the Trash
#   2. downloads the newest release, checks it is signed by the Perch Signing certificate (and its SHA-256)
#   3. installs into /Applications, or ~/Applications when your account cannot write /Applications
#   4. opens it. Your notes, fit and settings are kept. Updates then install themselves in place.
set -eu
REPO="${PERCH_REPO:-BigBhubbha/perch-mac}"
BASE="https://github.com/$REPO/releases/latest/download"
REQ='identifier "com.bigbhubbha.perch" and certificate leaf = H"80e6a50cbe739c115b054307a2986d74f7d7f73a"'
say() { printf '%s\n' "$*"; }
fail() { say "Perch was not installed: $*"; exit 1; }
[ "$(uname)" = "Darwin" ] || fail "this installer is for macOS."
TMP="$(mktemp -d /tmp/perch-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${PERCH_LOCAL_ZIP:-}" ]; then # CI only: test with a freshly built zip
  cp "$PERCH_LOCAL_ZIP" "$TMP/perch.zip"; URL="$PERCH_LOCAL_ZIP"; VER="local"; LEN=""
else
  say "Checking the newest version..."
  curl -fsSL "$BASE/appcast.xml" -o "$TMP/appcast.xml" || fail "could not reach GitHub."
  URL="$(sed -n 's/.*enclosure url="\([^"]*\)".*/\1/p' "$TMP/appcast.xml" | head -1)"
  VER="$(sed -n 's/.*<sparkle:shortVersionString>\([^<]*\)<.*/\1/p' "$TMP/appcast.xml" | head -1)"
  LEN="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' "$TMP/appcast.xml" | head -1)"
  [ -n "$URL" ] && [ -n "$VER" ] || fail "the update feed could not be read."
  say "Downloading Perch $VER..."
  curl -fL --progress-bar "$URL" -o "$TMP/perch.zip" || fail "the download did not finish."
fi
[ -z "$LEN" ] || [ "$(stat -f%z "$TMP/perch.zip")" = "$LEN" ] || fail "the download is the wrong size, so it was thrown away."
if [ -z "${PERCH_LOCAL_ZIP:-}" ] && curl -fsSL "$BASE/SHA256SUMS" -o "$TMP/sums" 2>/dev/null; then
  WANT="$(awk -v f="$(basename "$URL")" '$2==f {print $1}' "$TMP/sums")"
  GOT="$(shasum -a 256 "$TMP/perch.zip" | cut -d' ' -f1)"
  [ -z "$WANT" ] || [ "$WANT" = "$GOT" ] || fail "the download did not match its checksum, so it was thrown away."
fi
/usr/bin/ditto -x -k "$TMP/perch.zip" "$TMP/x" || fail "could not unpack the download."
NEW="$TMP/x/Perch.app"
[ -d "$NEW" ] || fail "the download did not contain Perch.app."
/usr/bin/codesign --verify --strict -R "=$REQ" "$NEW" 2>/dev/null \
  || fail "the download is not signed by the Perch Signing certificate, so it was thrown away."
/usr/bin/xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true

# Newer builds can prove they start on this Mac before anything is replaced.
if /usr/libexec/PlistBuddy -c 'Print :PerchHealthCheck' "$NEW/Contents/Info.plist" >/dev/null 2>&1; then
  say "Test-starting the new copy..."
  "$NEW/Contents/MacOS/Perch" --perch-health-check "$TMP/health.json" >/dev/null 2>&1 &
  HP=$!; i=0
  while [ $i -lt 150 ] && [ ! -s "$TMP/health.json" ] && kill -0 $HP 2>/dev/null; do i=$((i+1)); sleep 0.2; done
  { kill -9 $HP; wait $HP; } 2>/dev/null || true
  grep -q '"ok":true' "$TMP/health.json" 2>/dev/null || fail "the new copy did not start on this Mac within 30 seconds. Nothing was changed."
fi

say "Stopping any stuck Perch..."
if pgrep -f "Perch.app/Contents/MacOS/Perch" >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application id "com.bigbhubbha.perch" to quit' >/dev/null 2>&1 &
  sleep 2
fi
pkill -9 -f "Perch.app/Contents/MacOS/Perch" 2>/dev/null || true
pkill -9 -f "mediaremote-adapter.pl" 2>/dev/null || true
for v in /Volumes/Perch*; do [ -d "$v" ] && hdiutil detach -quiet -force "$v" 2>/dev/null || true; done

trash() { # move to the Trash instead of deleting, so nothing is lost
  mkdir -p "$HOME/.Trash"
  mv "$1" "$HOME/.Trash/Perch $(date +%H%M%S) $2.app" 2>/dev/null
}
if [ -n "${PERCH_DEST:-}" ]; then DEST="$PERCH_DEST"
elif [ -w /Applications ]; then DEST=/Applications
else DEST="$HOME/Applications"; fi
mkdir -p "$DEST"
LEFTOVER=""
for old in "$HOME/Downloads/Perch.app" "$HOME/Desktop/Perch.app" "/Applications/Perch.app" "$HOME/Applications/Perch.app"; do
  [ -d "$old" ] || continue
  if trash "$old" "old"; then say "Moved an old copy to the Trash: $old"; else LEFTOVER="$old"; fi
done
[ ! -d "$DEST/Perch.app" ] || fail "could not move the old $DEST/Perch.app out of the way."

/usr/bin/ditto "$NEW" "$DEST/Perch.app" || fail "could not copy into $DEST."
/usr/bin/xattr -dr com.apple.quarantine "$DEST/Perch.app" 2>/dev/null || true
say "Installed Perch $VER in $DEST."
if [ -n "$LEFTOVER" ]; then
  say "Note: an old copy is still at $LEFTOVER and your account cannot remove it. Drag it to the Trash in Finder (macOS asks for an administrator password) so Spotlight opens the new one."
fi
[ -n "${PERCH_NO_OPEN:-}" ] || /usr/bin/open "$DEST/Perch.app"
