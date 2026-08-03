#!/usr/bin/env bash
# Turns the recorded .webm into things you can actually paste somewhere.
#
#   ./convert.sh [out/character-creation.webm]
#
# MP4 for a PR or a doc. GIF for places that will not play video — scaled down
# and dropped to 12fps, because a full-size GIF of this is enormous for no gain.
set -euo pipefail

SRC="${1:-out/character-creation.webm}"
BASE="${SRC%.webm}"
GIF_WIDTH="${GIF_WIDTH:-960}"
GIF_FPS="${GIF_FPS:-12}"

[ -f "$SRC" ] || { echo "no such file: $SRC (run 'npm run record' first)" >&2; exit 1; }

echo "mp4 ..."
ffmpeg -v error -y -i "$SRC" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart -crf 23 \
  "$BASE.mp4"

echo "gif ..."
# Two passes: one palette for the whole clip, then apply it. Defaults favour
# looking good over being small, because the usual destination is somewhere
# that re-encodes it anyway. For a README, drop the size with:
#
#     GIF_WIDTH=720 GIF_FPS=10 ./convert.sh
ffmpeg -v error -y -i "$SRC" \
  -vf "fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos,palettegen=stats_mode=diff" \
  "$BASE.palette.png"

ffmpeg -v error -y -i "$SRC" -i "$BASE.palette.png" \
  -lavfi "fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  "$BASE.gif"

rm -f "$BASE.palette.png"

for f in "$SRC" "$BASE.mp4" "$BASE.gif"; do
  printf "  %-42s %s\n" "$f" "$(du -h "$f" | cut -f1)"
done
