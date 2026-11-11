#!/usr/bin/env bash
# The same --seed must give the same run, whatever the machine is doing: three bot runs side by
# side (so they compete for the CPU) must end with the same events at the same moments.
# Before the engine sound got its own random numbers, three runs of one seed averaged 84, 88 and
# 38 km/h: the sound made as many random samples as the audio thread asked for, and that follows
# the wall clock. Needs no graphics card and takes about 15 s.
# Usage: tools/test_determinism.sh <godot binary> [out dir]
set -uo pipefail
GODOT=$1
OUT=${2:-test-out}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# registers the script classes (class_name) the game needs; without it nothing loads
timeout 300 "$GODOT" --headless --import > "$OUT/det-import.log" 2>&1 || true
rm -f "$OUT"/det-?.json
for i in 1 2 3; do
  timeout 200 "$GODOT" --headless --fixed-fps 60 --quit-after $(( 35 * 60 )) -- \
    --bot=chase --duration=25 --seed=11 --summary="$OUT/det-$i.json" > "$OUT/det-$i.log" 2>&1 &
done
wait

status=0
if grep -lE "SCRIPT ERROR" "$OUT"/det-?.log; then
  echo "::error::determinism test: script errors in the logs (files above)"
  status=1
fi
python3 - "$OUT" <<'PY' || status=1
import json, os, sys
out = sys.argv[1]
runs = []
for i in (1, 2, 3):
    p = os.path.join(out, f"det-{i}.json")
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        print(f"FAIL  run {i} wrote no summary")
        sys.exit(1)
    runs.append(json.load(open(p)))
events = [[(e["type"], round(e["t"], 2)) for e in r["events"]] for r in runs]
speeds = [r.get("avg_kmh") for r in runs]
same = all(e == events[0] for e in events) and len(set(speeds)) == 1
if same:
    print(f"PASS  the same seed gave the same run three times: {len(events[0])} events, {speeds[0]} km/h on average")
    sys.exit(0)
print(f"FAIL  the same seed gave different runs: average speeds {speeds}")
for i, e in enumerate(events[1:], 2):
    diff = [(a, b) for a, b in zip(events[0], e) if a != b][:3]
    print(f"      run {i} differs from run 1 (events {len(e)} against {len(events[0])}), first differences: {diff}")
sys.exit(1)
PY
exit $status
