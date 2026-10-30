#!/usr/bin/env bash
# Records one bot run with Godot's Movie Maker on a virtual screen and encodes it to
# MP4. Movie Maker renders every frame at a fixed rate, so the video is smooth even
# on a machine with no graphics card (it just takes longer).
#
# Usage: tools/record.sh <godot> <out dir>
# Settings come from the environment (all optional):
#   MODE=chase|destroy|survive  ORIENTATION=vertical|horizontal  DURATION=55  FPS=60
#   SEED=123  TIME=dusk|day|night  TITLE="..."  SCALE=1 (0.5 for a quick half-size preview)
#   EXTRA_ARGS="--story=... --story_log=..."  more game arguments (the story lab uses this)
set -euo pipefail
GODOT=$1
OUT=$2
MODE=${MODE:-chase}
ORIENTATION=${ORIENTATION:-vertical}
DURATION=${DURATION:-55}
FPS=${FPS:-60}
SEED=${SEED:-$RANDOM}
TIME=${TIME:-dusk}
TITLE=${TITLE:-}
SCALE=${SCALE:-1}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

if [ "$ORIENTATION" = vertical ]; then W=1080; H=1920; else W=1920; H=1080; fi
W=$(python3 -c "print(int($W * $SCALE) // 2 * 2)")
H=$(python3 -c "print(int($H * $SCALE) // 2 * 2)")
echo "Recording $MODE $ORIENTATION ${W}x${H} ${DURATION}s @ ${FPS}fps seed=$SEED time=$TIME"

export LIBGL_ALWAYS_SOFTWARE=1
# registers the script classes (class_name) the game needs; without it nothing loads
timeout 300 "$GODOT" --headless --import > "$OUT/import.log" 2>&1 || true
start=$(date +%s)
set +e
timeout 18000 xvfb-run -a -s "-screen 0 1920x1920x24" \
  "$GODOT" --path . --rendering-driver opengl3 --write-movie "$OUT/take.avi" \
  --fixed-fps "$FPS" --resolution "${W}x${H}" --quit-after $(( (${DURATION%.*} + 20) * FPS )) -- \
  --bot="$MODE" --orientation="$ORIENTATION" --duration="$DURATION" --seed="$SEED" --trace \
  --time="$TIME" --title="$TITLE" --summary="$OUT/summary.json" ${EXTRA_ARGS:-} > "$OUT/godot.log" 2>&1
rc=$?
set -e
tail -n 40 "$OUT/godot.log"
echo "Godot finished with code $rc after $(( $(date +%s) - start ))s"
if grep -nE "SCRIPT ERROR" "$OUT/godot.log"; then
  echo "::warning::script errors while recording (see godot.log)"
fi
[ -s "$OUT/take.avi" ] || { echo "::error::no video was written"; exit 1; }
[ -s "$OUT/summary.json" ] || { echo "::error::the bot run did not finish (no summary.json), see godot.log"; exit 1; }

# one steady gain so every clip has the same loudness (sirens and crashes vary a lot)
AF=$(python3 tools/loudnorm.py "$OUT/take.avi" || true)
echo "audio filter: ${AF:-none}"
ffmpeg -y -loglevel error -i "$OUT/take.avi" ${AF:+-af "$AF"} -c:v libx264 -preset medium -crf 24 -maxrate 10M -bufsize 20M \
  -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart "$OUT/video.mp4"
rm -f "$OUT/take.avi"
# loudness numbers and a spectrogram of the soundtrack, to check the sounds are there
ffmpeg -hide_banner -nostats -i "$OUT/video.mp4" -vn -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary:/,$p' > "$OUT/loudness.txt" || true
cat "$OUT/loudness.txt"
ffmpeg -y -loglevel error -i "$OUT/video.mp4" -lavfi "showspectrumpic=s=1400x480:legend=0:stop=6000" "$OUT/audio.png" || true
mkdir -p "$OUT/frames"
ffmpeg -y -loglevel error -i "$OUT/video.mp4" -vf "fps=1/3,scale=360:-2" "$OUT/frames/f_%02d.jpg"
echo "$SEED" > "$OUT/seed.txt"
ls -la "$OUT"
