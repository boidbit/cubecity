#!/usr/bin/env bash
# The swarm show (director mode "swarm", swarm.gd and oracle.gd): 30 to 40 police on one car from every
# side, normal traffic too, and the director reading every car to steer the bot's car through. Plays
# 8 clips of 45 s headless (4 seeds, each once calm and once wild; 4 at a time, about 30 s) and checks
#   every clip: the car survives, 28 or more police at the peak, the bot keeps moving (average speed,
#     no teleport rescue worth the name, few "stuck"), a few near misses, police came from behind, from
#     side streets and head-on, and across the road ahead;
#   all the clips together: near misses on average, a wild clip takes more hits than a calm one
#     ("sometimes more, sometimes less"), and the director's last-second saves stay rare.
# The same seed gives the same run (see test_determinism.sh), so these numbers are exact; the limits
# leave room for the changes that come with later work.
# Usage: tools/test_swarm.sh <godot binary> [out dir]
set -uo pipefail
GODOT=$1
OUT=${2:-test-out}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# registers the script classes (class_name) the game needs; without it nothing loads
timeout 300 "$GODOT" --headless --import > "$OUT/swarm-import.log" 2>&1 || true
rm -f "$OUT"/swarm-*.json "$OUT"/swarm-*.log
export GODOT OUT
printf '%s\n' 11:0.1 12:0.1 13:0.1 14:0.1 11:0.9 12:0.9 13:0.9 14:0.9 | xargs -P 4 -I{} bash -c '
  p={}; seed=${p%%:*}; inten=${p##*:}
  timeout 280 "$GODOT" --headless --fixed-fps 60 --quit-after $(( 65 * 60 )) -- \
    --bot=swarm --duration=45 --seed=$seed --intensity=$inten --summary="$OUT/swarm-s${seed}-i${inten}.json" \
    > "$OUT/swarm-s${seed}-i${inten}.log" 2>&1'

status=0
if grep -lE "SCRIPT ERROR|ERROR:" "$OUT"/swarm-*.log | while read -r f; do grep -E "SCRIPT ERROR|ERROR:" "$f" | grep -vq "resources still in use at exit" && echo "$f"; done | grep .; then
  echo "::error::swarm test: errors in the logs (files above)"
  status=1
fi
python3 - "$OUT" <<'PY' || status=1
import collections, glob, json, os, re, sys
out = sys.argv[1]
fails = 0

def check(ok, name, detail):
    global fails
    print(("PASS  " if ok else "FAIL  ") + name + ": " + detail)
    if not ok:
        fails += 1

clips = {}
for seed in (11, 12, 13, 14):
    for inten in ("0.1", "0.9"):
        p = os.path.join(out, f"swarm-s{seed}-i{inten}.json")
        if not os.path.exists(p) or os.path.getsize(p) == 0:
            check(False, f"seed {seed} intensity {inten}", "wrote no summary")
            continue
        clips[(seed, inten)] = json.load(open(p))

for (seed, inten), s in sorted(clips.items()):
    ev = collections.Counter(e["type"] for e in s["events"])
    sw = s.get("swarm", {})
    name = f"seed {seed} intensity {inten}"
    problems = []
    if s["end"] != "survived":
        problems.append(f"ended '{s['end']}'")
    if s["max_cops"] < 28:
        problems.append(f"only {s['max_cops']} police at the peak (28 wanted)")
    if s["avg_kmh"] < 40:
        problems.append(f"average speed {s['avg_kmh']} km/h (40 wanted)")
    if ev.get("rescue", 0) > 1:
        problems.append(f"{ev['rescue']} teleport rescues (1 allowed)")
    if s["stuck"] > 4:
        problems.append(f"stuck {s['stuck']} times (4 allowed)")
    if s["near_miss"] < 2:
        problems.append(f"{s['near_miss']} near misses (2 wanted)")
    if s["player_hits"] > 9:
        problems.append(f"{s['player_hits']} hits (9 allowed)")
    for k in ("rears", "sides", "jousts", "crossers"):
        if sw.get(k, 0) < 1:
            problems.append(f"no police from '{k}'")
    detail = (f"{s['max_cops']} cops, {s['near_miss']} near misses, {s['player_hits']} hits, {s['saves']} saves, "
              f"{s['avg_kmh']} km/h, {sw.get('jousts')} head-on, {sw.get('crossers')} crossing")
    check(not problems, name, "; ".join(problems) if problems else detail)

if len(clips) == 8:
    calm = [s for (seed, i), s in clips.items() if i == "0.1"]
    wild = [s for (seed, i), s in clips.items() if i == "0.9"]
    mean = lambda xs: sum(xs) / len(xs)
    nm = mean([s["near_miss"] for s in clips.values()])
    check(nm >= 4.0, "near misses", f"{nm:.1f} a clip on average (4 wanted)")
    hc, hw = mean([s["player_hits"] for s in calm]), mean([s["player_hits"] for s in wild])
    check(hw >= hc + 0.75, "wild clips take more hits than calm ones", f"calm {hc:.2f} a clip, wild {hw:.2f} (at least 0.75 more wanted)")
    most = max(s["player_hits"] for s in wild)
    check(most >= 3, "a wild clip has a real crash", f"the most hits in one wild clip: {most} (3 wanted)")
    sv = mean([s["saves"] for s in clips.values()])
    check(sv <= 3.0, "last-second saves stay rare", f"{sv:.1f} a clip on average (3 allowed)")
    resc = sum(sum(1 for e in s["events"] if e["type"] == "rescue") for s in clips.values())
    check(resc <= 4, "the director rarely has to teleport the car", f"{resc} rescues in 8 clips (4 allowed)")
print(f"RESULT: {fails} failed")
sys.exit(1 if fails else 0)
PY
exit $status
