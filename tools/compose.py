#!/usr/bin/env python3
"""Adds the hook to a recorded run: a cold open that flashes forward to the run's
biggest moment, then an "EARLIER..." card, then the full clip. Shorts viewers decide
in the first second, so the best moment goes first and the story follows.

Usage: tools/compose.py <video.mp4> <summary.json> <out.mp4>
Needs ffmpeg with drawtext (libfreetype) and a bold TrueType font (DejaVu Sans Bold).
"""
import json
import os
import subprocess
import sys
import tempfile
import textwrap

FONTS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
]

# the biggest moment: first of these kinds present in the run's event log, with the
# seconds to show before and after it. A jump is logged when the car lands, so it needs
# a long lead-in to include the flight.
MOMENTS = [
    ("heli_down", "HELICOPTER DOWN", 1.8, 2.0),
    ("mega_jump", "THE CAR JUMPED THE WHOLE STREET", 3.0, 0.8),
    ("trap", "THE COPS NEVER SAW THIS COMING", 0.9, 1.6),
    ("collapse", "THE WHOLE TOWER CAME DOWN", 0.9, 1.8),
    ("gas", "ONE GAS STATION. ONE CAR.", 0.9, 1.6),
    ("chain", "CHAIN REACTION", 0.9, 1.6),
    ("near_miss", "THIS WAS TOO CLOSE", 1.4, 1.0),
    ("swat_down", "THE SWAT TRUCK GOT WRECKED", 1.0, 1.4),
    ("big_air", "WAIT FOR THE JUMP", 2.0, 0.8),
    ("cop_wrecked", "COPS ARE GOING DOWN", 1.0, 1.4),
    ("smash", "STRAIGHT THROUGH A BUILDING", 1.0, 1.4),
]
CARD = 0.8      # length of the EARLIER card


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,r_frame_rate:format=duration", "-of", "json", path],
        capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    st = d["streams"][0]
    num, den = st["r_frame_rate"].split("/")
    return int(st["width"]), int(st["height"]), float(num) / float(den), float(d["format"]["duration"])


def has_audio(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                          "stream=codec_name", "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return bool(out.strip())


def pick_moment(summary, duration):
    events = summary.get("events", [])
    for kind, text, lead, tail in MOMENTS:
        for e in events:
            if e.get("type") == kind:
                t = float(e["t"])
                if lead < t < duration - 0.5:
                    return t, text, lead, tail
    return None, "", 0.0, 0.0


def font():
    for f in FONTS:
        if os.path.isfile(f):
            return f
    return None


def drawtext(textfile, size, y, color="#ffd633"):
    f = font()
    return (f"drawtext=fontfile={f}:textfile={textfile}:fontsize={size}:fontcolor={color}:"
            f"borderw={max(4, size // 10)}:bordercolor=black:x=(w-text_w)/2:y={y}")


def drawlines(tmp, tag, lines, size, y0, color="#ffd633"):
    """One drawtext per line: multi-line text files render a stray box with some ffmpeg builds."""
    out = []
    for i, line in enumerate(lines):
        path = os.path.join(tmp, f"{tag}{i}.txt")
        with open(path, "w") as f:
            f.write(line)
        out.append(drawtext(path, size, f"{y0}+{i}*{int(size * 1.2)}", color))
    return ",".join(out)


def main(src, summary_path, out):
    with open(summary_path) as f:
        summary = json.load(f)
    w, h, fps, dur = probe(src)
    t, text, lead, tail = pick_moment(summary, dur)
    if t is None or font() is None:
        print("no teaser (no big moment found or no font); copying the video")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-c", "copy", out], check=True)
        return 0
    a = max(0.0, t - lead)
    b = min(dur, t + tail)
    size = int(w * 0.085)
    audio = has_audio(src)
    with tempfile.TemporaryDirectory() as tmp:
        hook = drawlines(tmp, "hook", textwrap.wrap(text, 16), size, "h*0.31")
        card = drawlines(tmp, "card", ["EARLIER..."], int(size * 0.9), "(h-text_h)/2", "#ffffff")
        fmt = f"fps={fps:.3f},format=yuv420p,setsar=1"
        graph = [
            "[0:v]split=2[v1][v2]",
            f"[v1]trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS,{hook},{fmt}[tv]",
            f"color=c=black:s={w}x{h}:r={fps:.3f}:d={CARD},{card},{fmt}[cv]",
            f"[v2]setpts=PTS-STARTPTS,{fmt}[mv]",
        ]
        if audio:
            norm = "aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo"
            graph += [
                "[0:a]asplit=2[a1][a2]",
                f"[a1]atrim=start={a:.3f}:end={b:.3f},asetpts=PTS-STARTPTS,{norm}[ta]",
                f"anullsrc=r=44100:cl=stereo,atrim=duration={CARD},{norm}[ca]",
                f"[a2]asetpts=PTS-STARTPTS,{norm}[ma]",
                "[tv][ta][cv][ca][mv][ma]concat=n=3:v=1:a=1[v][a]",
            ]
            maps = ["-map", "[v]", "-map", "[a]"]
        else:
            graph.append("[tv][cv][mv]concat=n=3:v=1:a=0[v]")
            maps = ["-map", "[v]"]
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-filter_complex", ";".join(graph)] + maps + [
            "-c:v", "libx264", "-preset", "medium", "-crf", "26", "-maxrate", "8M", "-bufsize", "16M",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out]
        subprocess.run(cmd, check=True)
    print(f"teaser: {a:.1f}s-{b:.1f}s ({text}), {CARD}s card, then the full clip")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
