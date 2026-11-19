#!/usr/bin/env python3
"""Reject an incomplete story recording or an on-foot chase that was not actually staged."""
import argparse
import json
from pathlib import Path


def problems(screenplay, log, engine_log=""):
    errors = []
    if "SCRIPT ERROR" in engine_log or "Parse Error" in engine_log or "ERROR: foot_chase" in engine_log:
        errors.append("Godot reported a story script error; inspect take/godot.log.")
    if float(log.get("end", -1)) < 0:
        errors.append("The story did not finish before recording stopped.")
    expected = [b for b in screenplay.get("beats", []) if b.get("do") == "foot_chase"]
    events = [e.get("type") for e in log.get("events", [])]
    results = [e for e in events if e in ("foot_caught", "foot_escaped")]
    if events.count("foot_chase_started") != len(expected) or events.count("foot_chase_done") != len(expected):
        errors.append("The requested on-foot chase did not start and finish successfully.")
    wanted = ["foot_caught" if b.get("outcome") == "caught" else "foot_escaped" for b in expected]
    if results != wanted:
        errors.append("The recorded on-foot chase outcome does not match the screenplay.")
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("screenplay", type=Path)
    ap.add_argument("story_log", type=Path)
    ap.add_argument("engine_log", type=Path)
    a = ap.parse_args()
    try:
        errors = problems(json.loads(a.screenplay.read_text(encoding="utf-8")),
                          json.loads(a.story_log.read_text(encoding="utf-8")),
                          a.engine_log.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError, TypeError) as e:
        errors = [f"Could not verify the recorded story: {e}"]
    for error in errors:
        print("::error::" + error)
    if not errors:
        print("Story recording verified: completed with all requested on-foot chase outcomes.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
