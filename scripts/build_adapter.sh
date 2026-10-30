#!/bin/bash
# Builds ungive/mediaremote-adapter (BSD-3-Clause) at a pinned commit, for both Apple Silicon and Intel.
# Output: .build/mediaremote-adapter/build/{MediaRemoteAdapter.framework,MediaRemoteAdapterTestClient}
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT="0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd"
DIR=".build/mediaremote-adapter"
if [[ -d "$DIR/build/MediaRemoteAdapter.framework" && "$(cat "$DIR/.perch-commit" 2>/dev/null)" == "$COMMIT" ]]; then
  echo "==> mediaremote-adapter already built at $COMMIT"; exit 0
fi
rm -rf "$DIR"
mkdir -p .build
git clone --quiet https://github.com/ungive/mediaremote-adapter.git "$DIR"
git -C "$DIR" checkout --quiet "$COMMIT"
cmake -S "$DIR" -B "$DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 >/dev/null
cmake --build "$DIR/build" --config Release >/dev/null
echo "$COMMIT" > "$DIR/.perch-commit"
ls "$DIR/build"
