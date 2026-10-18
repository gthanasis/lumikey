#!/bin/sh
# Renders docs/demo.mp4 and docs/demo.gif from the app's own animations.
# Needs ffmpeg (brew install ffmpeg) and a build (./build.sh --no-install).
set -e
cd "$(dirname "$0")/.."
APP="build/Lumikey.app/Contents/MacOS/Lumikey"
FRAMES=$(mktemp -d)
trap 'rm -rf "$FRAMES"' EXIT

"$APP" --render-demo "$FRAMES"

ffmpeg -loglevel error -y -framerate 28 -i "$FRAMES/frame_%05d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart docs/demo.mp4

# The GIF shows the first six effects, smaller, so the README stays quick to load.
ffmpeg -loglevel error -y -framerate 28 -i "$FRAMES/frame_%05d.png" -t 19 \
  -vf "fps=14,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  docs/demo.gif

ls -lh docs/demo.mp4 docs/demo.gif
