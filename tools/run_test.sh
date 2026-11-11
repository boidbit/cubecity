#!/usr/bin/env bash
# Runs one headless physics test, tools/tests/<name>_test.gd (see test_props.sh and test_fire.sh,
# which call this). The test prints PASS / FAIL / SKIP / INFO lines and a RESULT line, and exits 1
# if anything failed. A script error in the log fails the run too: it means the test did not test
# what it says, whatever it printed. Needs no graphics card.
# Usage: tools/run_test.sh <godot binary> <name> [out dir]
set -uo pipefail
GODOT=$1
NAME=$2
OUT=${3:-test-out}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# registers the script classes (class_name) the game needs; without it nothing loads
timeout 300 "$GODOT" --headless --import > "$OUT/$NAME-import.log" 2>&1 || true
timeout 400 "$GODOT" --headless --fixed-fps 60 --quit-after 60000 -s "tools/tests/${NAME}_test.gd" -- --seed=1 > "$OUT/$NAME-test.log" 2>&1
rc=$?
grep -E "^(PASS|FAIL|SKIP|INFO|RESULT)" "$OUT/$NAME-test.log"
status=0
if [ $rc -ne 0 ]; then
  echo "::error::$NAME test exited with code $rc"
  status=1
fi
if grep -nE "SCRIPT ERROR|Parse Error" "$OUT/$NAME-test.log" | grep -n .; then
  echo "::error::$NAME test: script errors in the log (lines above)"
  status=1
fi
if ! grep -q "^RESULT:" "$OUT/$NAME-test.log"; then
  echo "::error::$NAME test did not finish"
  status=1
fi
exit $status
