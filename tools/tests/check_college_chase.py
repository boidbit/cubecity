"""Check that the benchmark recorded the intended spoken and visual beats."""
import json
import sys
from pathlib import Path

timed, log = [json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[1:]]
lines = {b["id"]: b for b in timed["beats"] if "say" in b}
played = log["lines"]
if [line["id"] for line in played] != list(lines):
    sys.exit("The render did not play all five lines in order.")
if any(not line.get("audio") for line in lines.values()):
    sys.exit("The render is missing spoken dialogue.")
events = {e["type"]: e["t"] for e in log["events"]}
actions = {(a["do"], a["type"]): a["t"] for a in log["actions"]}
if not events["location_college_gate"] <= played[0]["t"] < events["foot_chase_started"]:
    sys.exit("The voiced hook must start at the gate before the chase.")
reply_gap = played[3]["t"] - events["foot_caught"]
reaction_gap = events["reaction_shock_freeze"] - (played[3]["t"] + lines["b04"]["dur"])
if not (-0.05 <= reply_gap <= 0.3 and -0.05 <= reaction_gap <= 0.15):
    sys.exit(f"Unplanned pause around the reveal: reply={reply_gap:.2f}s reaction={reaction_gap:.2f}s")
if abs(actions["sfx", "scratch"] - events["reaction_shock_freeze"]) > 0.04:
    sys.exit("The record scratch does not line up with the reaction.")
print(f"Verified five voiced lines, college gate, chase and reaction. Reveal gap: {reply_gap:.2f}s.")
