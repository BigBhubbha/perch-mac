#!/usr/bin/env bash
# Turns the motion frames from the design-snapshots artifact into MP4 and GIF clips.
# Usage: scripts/make_previews.sh <snapshots dir> <out dir>
set -euo pipefail
SRC="$1"; OUT="$2"
mkdir -p "$OUT/stills" "$OUT/keyframes" "$OUT/clips"
cp "$SRC"/*.png "$OUT/stills/"
for d in "$SRC"/motion/*/; do
  clip=$(basename "$d")
  n=$(ls "$d" | wc -l)
  # Hold the last frame for half a second so each loop reads clearly.
  ffmpeg -loglevel error -y -framerate 30 -i "$d/f%03d.png" -vf "tpad=stop_mode=clone:stop_duration=0.6,scale=1100:-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -crf 18 -preset slow -movflags +faststart "$OUT/clips/$clip.mp4"
  ffmpeg -loglevel error -y -framerate 30 -i "$d/f%03d.png" -vf "tpad=stop_mode=clone:stop_duration=0.6,fps=30,scale=880:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
    "$OUT/clips/$clip.gif"
  # Keyframes: start, a quarter, middle, three quarters, end.
  for k in 0 $((n/4)) $((n/2)) $((3*n/4)) $((n-1)); do
    cp "$d/$(printf 'f%03d.png' $k)" "$OUT/keyframes/$clip-$(printf '%03d' $k).png"
  done
done
ls -la "$OUT/clips"
