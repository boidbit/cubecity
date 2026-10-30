#!/usr/bin/env python3
"""Story lab: lays the voice clips over the recorded video.

The game wrote story_log.json with the real start time of every line (reactions fire when
the chase produces an event, so the times are only known after the recording). Each
voice clip is placed at its start time, cut short if the line was interrupted, and the
game's own sound is ducked while somebody talks. The result gets one steady loudness.

Usage: tools/story/mix.py video.mp4 story_log.json timed.json out.mp4
       (voice paths in timed.json are relative to timed.json)
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE_GAIN = 1.8


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("command failed: " + " ".join(cmd[:4]) + "\n" + r.stderr[-1500:])
    return r


def main(video, log_path, timed_path, out):
    with open(log_path) as f:
        log = json.load(f)
    with open(timed_path, encoding="utf-8") as f:
        sp = json.load(f)
    base = os.path.dirname(os.path.abspath(timed_path))
    spoken = [b for b in sp.get("beats", []) if "say" in b] + sp.get("lines", []) + sp.get("reactions", [])
    by_id = {l["id"]: l for l in spoken}
    cast = sp.get("cast", {})
    clips = []
    for p in log.get("lines", []):
        line = by_id.get(p["id"])
        if not line or not line.get("audio"):
            continue
        path = os.path.join(base, line["audio"])
        who = cast.get(line.get("say", line.get("who", "")), {})
        if os.path.exists(path):
            clips.append((path, float(p["t"]), p.get("cut"), bool(who.get("radio"))))
    if not clips:
        print("no voice clips to mix: keeping the game sound")
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-c", "copy", out])
        return 0

    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", video]
    parts = ["[0:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[g]"]
    for i, (path, t, cut, radio) in enumerate(clips, start=1):
        cmd += ["-i", path]
        f = f"[{i}:a]"
        if radio:
            # megaphone / police radio: thin and a little crunchy
            f += "highpass=f=450,lowpass=f=3200,acompressor=threshold=0.1:ratio=6,"
        if cut is not None:
            cut = max(float(cut), 0.2)
            f += f"atrim=0:{cut:.2f},afade=t=out:st={max(cut - 0.07, 0):.2f}:d=0.07,"
        ms = int(round(t * 1000))
        f += f"volume={VOICE_GAIN},aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms}[v{i}]"
        parts.append(f)
    n = len(clips)
    ins = "".join(f"[v{i}]" for i in range(1, n + 1))
    parts.append(f"{ins}amix=inputs={n}:normalize=0:dropout_transition=0[vb]" if n > 1 else "[v1]anull[vb]")
    parts += [
        "[vb]asplit=2[vb1][vb2]",
        # the game's sound sinks while a voice is on
        "[g][vb1]sidechaincompress=threshold=0.015:ratio=10:attack=8:release=350:makeup=1[gd]",
        "[gd][vb2]amix=inputs=2:normalize=0:duration=first[mix]",
    ]
    with tempfile.TemporaryDirectory() as tmp:
        mix = os.path.join(tmp, "mix.wav")
        run(cmd + ["-filter_complex", ";".join(parts), "-map", "[mix]", "-ar", "48000", mix])
        af = run([sys.executable, os.path.join(HERE, "..", "loudnorm.py"), mix]).stdout.strip()
        print("loudness filter:", af or "none")
        enc = ["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-i", mix, "-map", "0:v", "-map", "1:a"]
        if af:
            enc += ["-af", af]
        run(enc + ["-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", out])
    print(f"mixed {n} voice clips into {out}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
