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
  if grep -nE "SCRIPT ERROR|ERROR:" "$OUT/$name.log"; then
    echo "::error::$name: errors in the log (lines above)"
    status=1
  fi
}

run import --import
run play --fixed-fps 60 --quit-after 1200
for mode in chase destroy survive stunt; do
  for seed in 11 12; do
    # the director quits at the end of the clip; --quit-after is a safety net
    run "bot-$mode-$seed" --fixed-fps 60 --quit-after $(( (SECS + 15) * 60 )) -- \
      --bot="$mode" --duration="$SECS" --seed="$seed" --trace --summary="$OUT/$mode-$seed.json"
    if [ ! -s "$OUT/$mode-$seed.json" ]; then
      echo "::error::bot-$mode-$seed wrote no summary"
      status=1
    fi
  done
done
python3 tools/report.py "$OUT"/*.json || status=1
exit $status
