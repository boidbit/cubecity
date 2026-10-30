#!/usr/bin/env bash
# Headless smoke test: imports the project, plays it with nobody at the wheel, then
# lets the bot play every mode faster than real time (nothing is drawn). Fails on
# any script error, a crash, a hang, or a bot run that wrote no summary.
# Usage: tools/smoke.sh <godot binary> [out dir] [seconds per bot mode]
set -uo pipefail
GODOT=$1
OUT=${2:-smoke-out}
SECS=${3:-45}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
status=0

run() {
  local name=$1
  shift
  echo "::group::$name"
  timeout 300 "$GODOT" --headless "$@" > "$OUT/$name.log" 2>&1
  local rc=$?
  cat "$OUT/$name.log"
  echo "::endgroup::"
  if [ $rc -ne 0 ]; then
    echo "::error::$name exited with code $rc"
    status=1
  fi
  # "resources still in use at exit" is Godot's shutdown housekeeping (a sound still
  # playing when the process ends), not a script error: warn, don't fail
  if grep -nE "SCRIPT ERROR|ERROR:" "$OUT/$name.log" | grep -vE "resources still in use at exit" | grep -n .; then
    echo "::error::$name: errors in the log (lines above)"
    status=1
  fi
  if grep -qE "resources still in use at exit" "$OUT/$name.log"; then
    echo "::warning::$name: sounds still loaded at exit"
  fi
}

run import --import
run play --fixed-fps 60 --quit-after 1200
for mode in chase destroy survive stunt heli rush; do
  for seed in 11 12 13 14; do
    # the director quits at the end of the clip; --quit-after is a safety net
    run "bot-$mode-$seed" --fixed-fps 60 --quit-after $(( (SECS + 15) * 60 )) -- \
      --bot="$mode" --duration="$SECS" --seed="$seed" --trace --summary="$OUT/$mode-$seed.json"
    if [ ! -s "$OUT/$mode-$seed.json" ]; then
      echo "::error::bot-$mode-$seed wrote no summary"
      status=1
    fi
  done
done
# story lab: the characters must play their lines (no recording needed)
if [ -f story/story.gd ]; then
  run bot-story --fixed-fps 60 --quit-after $(( (SECS + 15) * 60 )) -- \
    --bot=chase --duration="$SECS" --seed=11 --story=1 --story_log="$OUT/story_log.out" --summary="$OUT/story-run.out"
  n=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['lines']))" "$OUT/story_log.out" 2>/dev/null || echo 0)
  echo "story lines played: $n"
  if [ "$n" -lt 3 ]; then
    echo "::error::the story played only $n lines"
    status=1
  fi
  # on foot: park, get out, kneel, hug, run, fall
  run bot-story-foot --fixed-fps 60 --quit-after $(( 75 * 60 )) -- \
    --bot=chase --duration=60 --seed=11 --story=res://story/screenplays/ep3_proposal.json --story_log="$OUT/story_foot.out"
  if ! python3 - "$OUT/story_foot.out" <<'PY'
import json, sys
log = json.load(open(sys.argv[1]))
seen = {e["type"] for e in log.get("events", [])}
print(f"on-foot story: {len(log['lines'])} lines, events {sorted(seen & {'parked', 'exited', 'arrived'})}, ending {log['ending']}")
sys.exit(0 if {"parked", "exited", "arrived"} <= seen and len(log["lines"]) >= 8 else 1)
PY
  then
    echo "::error::the on-foot story did not play through (park, get out, walk)"
    status=1
  fi
  # a set on the pavement: the ice-cream cart, its vendor, handing things over
  run bot-story-spot --fixed-fps 60 --quit-after $(( 75 * 60 )) -- \
    --bot=chase --duration=60 --seed=7 --story=res://story/screenplays/ep4_icecream.json --story_log="$OUT/story_spot.out"
  if ! python3 - "$OUT/story_spot.out" <<'PY'
import json, sys
log = json.load(open(sys.argv[1]))
done = {a["do"] for a in log.get("actions", [])}
print(f"stall story: {len(log['lines'])} lines, actions {sorted(done & {'park', 'give', 'dance'})}, ending {log['ending']}")
sys.exit(0 if {"park", "give", "dance"} <= done and len(log["lines"]) >= 12 else 1)
PY
  then
    echo "::error::the stall story did not play through (park at the cart, vendor, give)"
    status=1
  fi
  # the music for every mood (needs numpy; the story workflow installs it)
  if ! python3 -c "import numpy" 2>/dev/null; then
    echo "numpy is not installed: music check skipped"
  elif ! python3 -c "
import sys; sys.path.insert(0, 'tools/story')
import music
for m in music.MOODS:
    x = music.make(m, 8.0, 1)
    assert len(x) == 8 * music.SR and abs(x).max() > 0.3, m
print('music: all moods ok')
"; then
    echo "::error::the music generator failed"
    status=1
  fi
fi
python3 tools/report.py "$OUT"/*.json || status=1
exit $status
