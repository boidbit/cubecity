#!/usr/bin/env bash
# Headless physics test for street lamps and trees (tools/tests/props_test.gd): hitting one must
# slow the car a bit, never stop it, and a lamp a metre away must not be hit at all.
# Needs no graphics card and takes about 15 s.
# Usage: tools/test_props.sh <godot binary> [out dir]
set -uo pipefail
GODOT=$1
OUT=${2:-test-out}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# registers the script classes (class_name) the game needs; without it nothing loads
timeout 300 "$GODOT" --headless --import > "$OUT/props-import.log" 2>&1 || true
timeout 300 "$GODOT" --headless --fixed-fps 60 --quit-after 30000 -s tools/tests/props_test.gd -- --seed=1 > "$OUT/props-test.log" 2>&1
rc=$?
grep -E "^(PASS|FAIL|SKIP|INFO|RESULT)" "$OUT/props-test.log"
status=0
if [ $rc -ne 0 ]; then
  echo "::error::props test exited with code $rc"
  status=1
fi
# a script error means the test did not test what it says, whatever it printed
if grep -nE "SCRIPT ERROR|Parse Error" "$OUT/props-test.log" | grep -n .; then
  echo "::error::props test: script errors in the log (lines above)"
  status=1
fi
if ! grep -q "^RESULT:" "$OUT/props-test.log"; then
  echo "::error::props test did not finish"
  status=1
fi
exit $status
