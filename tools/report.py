#!/usr/bin/env python3
"""Prints a table of bot-run summaries (and adds it to the GitHub job summary).

Usage: tools/report.py summary.json [summary.json ...]
"""
import json
import os
import sys

COLS = ["mode", "end", "excitement", "avg_kmh", "max_cops", "cops_wrecked", "collapses",
        "chains", "gas", "big_air", "drifts", "smash", "busted_peak", "stuck", "destroyed_pct"]


def main(paths):
    rows = []
    for p in paths:
        with open(p) as f:
            s = json.load(f)
        s["file"] = os.path.basename(os.path.dirname(p)) or os.path.basename(p)
        rows.append(s)
    head = ["file"] + COLS + ["beats"]
    lines = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    for s in rows:
        beats = ", ".join(f"{k}@{v:.0f}s" for k, v in s.get("beats", {}).items())
        lines.append("| " + " | ".join([str(s["file"])] + [str(s.get(c, "")) for c in COLS] + [beats]) + " |")
    text = "\n".join(lines)
    print(text)
    out = os.environ.get("GITHUB_STEP_SUMMARY")
    if out:
        with open(out, "a") as f:
            f.write(text + "\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
