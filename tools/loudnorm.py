#!/usr/bin/env python3
"""Prints the ffmpeg -af filter that brings a recording's soundtrack to a YouTube-like
loudness (-14 LUFS), or nothing if the file has no usable audio.

Two passes: this script measures, the caller applies the result with linear=true so the
whole clip gets one steady gain instead of the volume pumping up and down.

Usage: tools/loudnorm.py <video or avi>
"""
import json
import re
import subprocess
import sys

TARGET = "I=-14:TP=-2:LRA=11"


def main(path):
    p = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vn", "-af", f"loudnorm={TARGET}:print_format=json",
         "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p.stderr, re.S)
    if p.returncode != 0 or not m:
        return 0
    s = json.loads(m.group(0))
    try:
        if float(s["input_i"]) < -60:       # silent
            return 0
    except ValueError:                       # "-inf"
        return 0
    print(f"loudnorm={TARGET}:measured_I={s['input_i']}:measured_TP={s['input_tp']}:"
          f"measured_LRA={s['input_lra']}:measured_thresh={s['input_thresh']}:offset={s['target_offset']}:linear=true,"
          "alimiter=limit=0.85:level=disabled")      # catches the odd peak the steady gain pushes over
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
