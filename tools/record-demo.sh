#!/usr/bin/env bash
# Capture an animated demo of the Lights window cycling through states.
# Requires Lights.app to be running and ffmpeg installed (`brew install ffmpeg`).
# Output: docs/demo.gif (~75KB) + docs/demo.mp4 (~80KB).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! curl -s --max-time 1 http://127.0.0.1:9876/status >/dev/null; then
    echo "✗ Lights not running. Launch Lights.app first." >&2
    exit 1
fi

if ! command -v ffmpeg >/dev/null; then
    echo "✗ ffmpeg not installed. brew install ffmpeg" >&2
    exit 1
fi

FRAMES=$(mktemp -d)
trap "rm -rf $FRAMES" EXIT

STATES=("idle" "executing" "permission" "executing" "idle")

echo "→ Capturing 5 frames…"
for i in "${!STATES[@]}"; do
    state="${STATES[$i]}"
    n=$(printf "%02d" $((i+1)))
    curl -s "http://127.0.0.1:9876/$state" >/dev/null
    sleep 0.4
    SNAP=$(curl -s http://127.0.0.1:9876/snapshot)
    [ -f "$SNAP" ] || { echo "✗ frame $n ($state) failed: $SNAP"; exit 1; }
    cp "$SNAP" "$FRAMES/frame_$n.png"
    rm -f "$SNAP"
    echo "  ✓ frame_$n.png ← $state"
done

mkdir -p docs

echo "→ Building GIF…"
ffmpeg -y -framerate 1 -i "$FRAMES/frame_%02d.png" \
    -vf "scale=120:-1:flags=lanczos,palettegen=stats_mode=full" \
    "$FRAMES/palette.png" >/dev/null 2>&1
ffmpeg -y -framerate 1 -i "$FRAMES/frame_%02d.png" -i "$FRAMES/palette.png" \
    -lavfi "scale=120:-1:flags=lanczos[x];[x][1:v]paletteuse" \
    -loop 0 docs/demo.gif >/dev/null 2>&1

echo "→ Building MP4…"
ffmpeg -y -framerate 1 -i "$FRAMES/frame_%02d.png" \
    -vf "scale=240:-2:flags=lanczos,fps=30" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart \
    docs/demo.mp4 >/dev/null 2>&1

curl -s http://127.0.0.1:9876/idle >/dev/null

echo
echo "✓ Done:"
ls -lh docs/demo.gif docs/demo.mp4
