#!/usr/bin/env python3
"""Story lab: lays the voice clips over the recorded video.

The game wrote story_log.json with the real start time of every line (reactions fire when
the chase produces an event, so the times are only known after the recording). Each
voice clip is placed at its start time, cut short if the line was interrupted, and the
game's own sound is ducked while somebody talks. The score (tools/story/score.py) puts music
under it that changes with the story (it dips under the voices and comes up for the end card)
and sound effects on the moments that need them. The result gets one steady loudness; a copy
without the music (<out>_nomusic.mp4) is made too, to put a trending sound under in the app.

Usage: tools/story/mix.py video.mp4 story_log.json timed.json out.mp4 [--music auto|none|MOOD]
       (voice paths in timed.json are relative to timed.json; auto = the screenplay's mood)
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
VOICE_GAIN = 1.8
MUSIC_GAIN = 0.45       # under the talking (it dips further while somebody speaks)
MUSIC_END_GAIN = 0.95   # for the end card
SFX_GAIN = 0.9


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("command failed: " + " ".join(cmd[:4]) + "\n" + r.stderr[-1500:])
    return r


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


def main(video, log_path, timed_path, out, music="auto"):
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
    mood = (sp.get("mood") or "romantic") if music == "auto" else music
    if not clips and mood == "none":
        print("no voice clips and no music: keeping the game sound")
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
    tmp_dir = tempfile.TemporaryDirectory()
    tmp = tmp_dir.name
    if n == 0:
        parts.append("anullsrc=r=48000:cl=stereo[vb]")
    else:
        ins = "".join(f"[v{i}]" for i in range(1, n + 1))
        parts.append(f"{ins}amix=inputs={n}:normalize=0:dropout_transition=0[vb]" if n > 1 else "[v1]anull[vb]")
    has_music = mood != "none"
    secs = duration(video)
    import music as music_mod
    import score as score_mod
    seed = music_mod.seed_of(str(sp.get("title", "")) + str(sp.get("episode", "")))
    # the score: music that follows the story, and the sound effects on its moments
    score_mood = mood if has_music else str(sp.get("mood") or "romantic")
    mtrack, fxtrack, report = score_mod.build(sp, log, score_mood, secs, seed)
    print(f"score: {score_mood} ({secs:.1f}s, seed {seed})" + ("" if has_music else ", music off"))
    for r in report:
        if has_music or "sfx" in r:
            print("  " + r)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(os.path.splitext(out)[0] + "_score.txt", "w") as f:
        f.write("\n".join(report) + "\n")
    k = n + 1
    if has_music:
        mpath = os.path.join(tmp, "music.wav")
        music_mod.write_wav(mpath, mtrack)
        cmd += ["-i", mpath]
        end = float(log.get("end", -1.0))
        end = end if end > 0 else secs - 3.0
        # louder for the end card, then the music's own fade-out
        parts.append(f"[{k}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,"
                     f"volume='{MUSIC_GAIN}+{MUSIC_END_GAIN - MUSIC_GAIN}*min(max((t-{end:.2f})/1.2,0),1)':eval=frame[m]")
        k += 1
    fpath = os.path.join(tmp, "sfx.wav")
    music_mod.write_wav(fpath, fxtrack)
    cmd += ["-i", fpath]
    parts.append(f"[{k}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,volume={SFX_GAIN},asplit=2[fx1][fx2]")
    parts += [
        # padded with silence: a sidechain stops when its key input does, and the voices end
        # before the end card
        "[vb]apad,asplit=4[vb1][vb2][vb3][vb4]",
        # the game's sound sinks while a voice is on
        "[g][vb1]sidechaincompress=threshold=0.015:ratio=10:attack=8:release=350:makeup=1,asplit=2[gd1][gd2]",
    ]
    if has_music:
        parts += [
            # the music dips under the voices too, more gently
            "[m][vb3]sidechaincompress=threshold=0.02:ratio=4:attack=20:release=600:makeup=1[md]",
            "[gd1][vb2][md][fx1]amix=inputs=4:normalize=0:duration=first[mix]",
            # and a version without the music, to put a trending sound under it in the app
            "[gd2][vb4][fx2]amix=inputs=3:normalize=0:duration=first[bare]",
        ]
    else:
        parts += ["[gd1][vb2][fx1]amix=inputs=3:normalize=0:duration=first[mix]",
                  "[gd2]anullsink", "[vb3]anullsink", "[vb4]anullsink", "[fx2]anullsink"]
    with tmp_dir:
        mix = os.path.join(tmp, "mix.wav")
        bare = os.path.join(tmp, "bare.wav")
        maps = ["-map", "[mix]", "-ar", "48000", mix]
        if has_music:
            maps += ["-map", "[bare]", "-ar", "48000", bare]
        run(cmd + ["-filter_complex", ";".join(parts)] + maps)
        outs = [(mix, out)]
        if has_music:
            outs.append((bare, os.path.splitext(out)[0] + "_nomusic.mp4"))
        for wav, dst in outs:
            af = run([sys.executable, os.path.join(HERE, "..", "loudnorm.py"), wav]).stdout.strip()
            print("loudness filter:", af or "none")
            enc = ["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-i", wav, "-map", "0:v", "-map", "1:a"]
            if af:
                enc += ["-af", af]
            run(enc + ["-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", dst])
    print(f"mixed {n} voice clips{', the music' if has_music else ''} and the sound effects into {out}"
          + (" (and a copy without the music)" if has_music else ""))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument("video")
    ap.add_argument("log")
    ap.add_argument("timed")
    ap.add_argument("out")
    ap.add_argument("--music", default="auto")
    a = ap.parse_args()
    sys.exit(main(a.video, a.log, a.timed, a.out, a.music))
