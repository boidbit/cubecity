#!/usr/bin/env python3
"""Keeps the most exciting take, grabs a thumbnail from its biggest moment and
writes the YouTube upload text for it.

Usage: tools/pick.py <takes dir> <out dir> <name>
Each folder in <takes dir> holds video.mp4 and summary.json from tools/record.sh.
"""
import glob
import json
import os
import shutil
import subprocess
import sys

import upload_text

# first event of these kinds (in this order) makes the thumbnail
MOMENTS = ["collapse", "trap", "gas", "chain", "swat_down", "cop_wrecked", "big_air", "smash"]


def moment(s):
    events = s.get("events", [])
    for kind in MOMENTS:
        for e in events:
            if e.get("type") == kind:
                return float(e["t"]) + 0.5
    return float(s.get("duration", 55)) * 0.4


def main(src, out, name):
    takes = []
    for d in sorted(glob.glob(os.path.join(src, "*"))):
        sj = os.path.join(d, "summary.json")
        mp = os.path.join(d, "video.mp4")
        if os.path.isfile(sj) and os.path.isfile(mp):
            with open(sj) as f:
                s = json.load(f)
            takes.append((s.get("excitement", 0), d, s))
    if not takes:
        print("no finished takes")
        return 1
    takes.sort(key=lambda t: t[0], reverse=True)
    score, d, s = takes[0]
    os.makedirs(out, exist_ok=True)
    video = os.path.join(out, name + ".mp4")
    shutil.copy(os.path.join(d, "video.mp4"), video)
    shutil.copy(os.path.join(d, "summary.json"), os.path.join(out, name + ".json"))
    # titles, description and tags for YouTube, filled in with this run's numbers
    text = upload_text.build(s)
    with open(os.path.join(out, name + "-upload.txt"), "w", encoding="utf-8") as f:
        f.write(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("## Upload text\n\nAlso saved as `" + name + "-upload.txt` next to the video.\n\n```\n" + text + "```\n\n")
    t = moment(s)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", video,
                    "-frames:v", "1", "-q:v", "2", os.path.join(out, name + "-thumbnail.jpg")], check=False)
    print(f"best take: {os.path.basename(d)} (excitement {score}), thumbnail at {t:.1f}s")
    for sc, dd, _ in takes:
        print(f"  {os.path.basename(dd)}: {sc}")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
