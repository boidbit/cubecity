#!/usr/bin/env python3
"""Story lab: turns a screenplay into voice clips and a timed screenplay.

For every line (and reaction) it makes a voice clip, measures it, and writes
  <out>/voices/<id>.wav   the voice (mono, 44.1 kHz, silence trimmed)
  <out>/timed.json        the screenplay with "dur" (seconds), "env" (loudness 0..1 at 20 Hz,
                          the game uses it to flap the mouth) and "audio" added to each line
The game reads timed.json; tools/story/mix.py lays the clips over the recorded video.

Voice providers (--provider):
  gemini  Google Gemini speech (needs GEMINI_API_KEY): the most natural
  edge    Microsoft Edge read-aloud voices through the edge-tts package (free, good Hindi)
  espeak  espeak-ng, offline and robotic, only a fallback
  none    no voice: subtitles only, lengths are estimated from the text
  auto    gemini (if there is a key), then edge, then espeak, then none (the default)
A provider that fails part way is dropped for the whole story, so one episode never mixes
two sets of voices.
Set CUBE_CA_BUNDLE to a CA file if edge-tts must go through a TLS-inspecting proxy.

Usage: tools/story/voices.py screenplay.json out_dir [--provider auto]
"""
import argparse
import array
import asyncio
import json
import math
import os
import shutil
import subprocess
import sys
import wave

SR = 44100
ENV_HZ = 20
# how much faster / higher an emotion speaks, added to the character's own rate (%) and pitch (Hz)
EMO_EDGE = {"shock": (6, 3), "angry": (4, 2), "sad": (-8, -3), "love": (-3, 1), "laugh": (3, 3)}
# Gemini is given only the line itself. Directions such as "Say angrily:" were read out as
# part of the line (an extra phrase and a pause at the start of the clip), so the emotion
# has to come from the words and punctuation the writer chose.


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def est_dur(line):
    return max(1.2, min(6.0, 0.075 * len(line.get("sub", ""))))


# ------------------------------------------------------------ providers

def _num(text, default=0):
    try:
        return int("".join(c for c in str(text) if c in "+-0123456789"))
    except ValueError:
        return default


def edge_prosody(voice, emotion):
    dr, dp = EMO_EDGE.get(emotion, (0, 0))
    rate = _num(voice.get("rate", "+0%")) + dr
    pitch = _num(voice.get("pitch", "+0Hz")) + dp
    return f"{rate:+d}%", f"{pitch:+d}Hz"


def synth_edge(text, voice, rate, pitch, out_mp3, tries=3):
    import edge_tts
    if os.environ.get("CUBE_CA_BUNDLE"):
        import ssl
        import edge_tts.communicate as ec
        ec._SSL_CTX = ssl.create_default_context(cafile=os.environ["CUBE_CA_BUNDLE"])

    async def go():
        c = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        await asyncio.wait_for(c.save(out_mp3), 60)

    last = None
    for i in range(tries):
        try:
            asyncio.run(go())
            if os.path.getsize(out_mp3) > 1000:
                return
        except Exception as e:      # network, throttling, bad voice name
            last = e
        import time
        time.sleep(1.5 * (i + 1))
    raise RuntimeError(f"edge-tts failed: {last}")


def synth_gemini(line, voice, out_wav):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gemini
    text = line.get("tts") or line.get("sub", "")
    pcm, rate, _ = gemini.speak(text, voice.get("gemini", "Kore"))
    raw = out_wav + ".pcm"
    with open(raw, "wb") as f:
        f.write(pcm)
    to_wav(raw, out_wav, ["-f", "s16le", "-ar", str(rate), "-ac", "1"])
    os.remove(raw)


def synth_espeak(text, pitch, out_wav):
    r = sh(["espeak-ng", "-v", "hi", "-s", "150", "-p", str(pitch), "-w", out_wav, text])
    if r.returncode != 0 or not os.path.exists(out_wav):
        raise RuntimeError("espeak-ng failed: " + r.stderr[:200])


def to_wav(src, dst, in_args=()):
    """Mono 44.1 kHz wav with the leading and trailing silence cut off."""
    af = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.04,"
          "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12,areverse")
    r = sh(["ffmpeg", "-y", "-v", "error", *in_args, "-i", src, "-ac", "1", "-ar", str(SR), "-af", af, dst])
    if r.returncode != 0 or not os.path.exists(dst):
        raise RuntimeError("ffmpeg failed: " + r.stderr[:200])


def analyze(path):
    """(duration in seconds, loudness envelope 0..1 at ENV_HZ)."""
    with wave.open(path) as w:
        n = w.getnframes()
        sr = w.getframerate()
        pcm = array.array("h")
        pcm.frombytes(w.readframes(n))
    hop = sr // ENV_HZ
    rms = []
    for i in range(0, len(pcm) - hop + 1, hop):
        seg = pcm[i:i + hop]
        rms.append(math.sqrt(sum(x * x for x in seg) / len(seg)))
    peak = max(rms) if rms else 1.0
    env = [round(min(r / (peak * 0.7), 1.0), 2) for r in rms] if peak > 0 else []
    return n / sr, env


# ------------------------------------------------------------ main

def spoken(sp):
    """Every line that is spoken: "say" beats, and old-style lines and reactions."""
    out = [b for b in sp.get("beats", []) if "say" in b]
    out += sp.get("lines", []) + sp.get("reactions", [])
    return out


def make_voices(sp, out, provider):
    vdir = os.path.join(out, "voices")
    os.makedirs(vdir, exist_ok=True)
    cast = sp.get("cast", {})
    results = {}
    for line in spoken(sp):
        lid = line["id"]
        who = cast.get(line.get("say", line.get("who", "")), {})
        v = who.get("voice", {})
        wav = os.path.join(vdir, lid + ".wav")
        tmp = os.path.join(vdir, lid + ".src")
        text = line.get("tts") or line.get("sub", "")
        if provider == "gemini":
            synth_gemini(line, v, wav)
        elif provider == "edge":
            rate, pitch = edge_prosody(v, line.get("emotion", ""))
            synth_edge(text, v.get("edge", "hi-IN-SwaraNeural"), rate, pitch, tmp + ".mp3")
            to_wav(tmp + ".mp3", wav)
        elif provider == "espeak":
            synth_espeak(text, v.get("espeak_pitch", 50), tmp + ".wav")
            to_wav(tmp + ".wav", wav)
        else:
            results[lid] = None
            continue
        dur, env = analyze(wav)
        if dur < 0.3:
            raise RuntimeError(f"voice clip for {lid} is empty")
        results[lid] = (dur, env)
        print(f"  {lid}: {dur:.2f}s")
    for f in os.listdir(vdir):
        if f.endswith(".src.mp3") or f.endswith(".src.wav"):
            os.remove(os.path.join(vdir, f))
    return results


def simulate(sp):
    """Rough length of the story: lines back to back, waits, the jump and the ending."""
    t = float(sp.get("start", 2.8))
    gap = float(sp.get("gap", 0.3))
    for b in sp.get("beats", []):
        if "say" in b:
            t += b["dur"] + gap + (2.5 if b.get("on") else 0.0)
        elif "wait" in b:
            t += float(b["wait"])
        elif "end" in b:
            t += 3.5
    for l in sp.get("lines", []):
        t += l["dur"] + gap
    slack = min(sum(r["dur"] for r in sp.get("reactions", [])), 6.0) + 3.0
    return t, t + slack


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("screenplay")
    ap.add_argument("out")
    ap.add_argument("--provider", default="auto", choices=["auto", "gemini", "edge", "espeak", "none"])
    a = ap.parse_args()
    with open(a.screenplay, encoding="utf-8") as f:
        sp = json.load(f)
    ids = [l["id"] for l in spoken(sp)]
    if len(ids) != len(set(ids)):
        sys.exit("duplicate line ids in the screenplay")
    os.makedirs(a.out, exist_ok=True)

    order = {"auto": ["gemini", "edge", "espeak", "none"], "gemini": ["gemini", "edge", "none"],
             "edge": ["edge", "none"], "espeak": ["espeak", "none"], "none": ["none"]}[a.provider]
    used, results = "none", {}
    for prov in order:
        if prov == "gemini":
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import gemini
            if not gemini.keys():
                print("no Gemini key (GEMINI_API_KEY)")
                continue
        if prov == "edge":
            try:
                import edge_tts  # noqa: F401
            except ImportError:
                print("edge-tts is not installed")
                continue
        if prov == "espeak" and not shutil.which("espeak-ng"):
            print("espeak-ng is not installed")
            continue
        print("voice provider:", prov)
        try:
            results = make_voices(sp, a.out, prov)
            used = prov
            break
        except Exception as e:
            print(f"::warning::voice provider {prov} failed: {e}")
    for l in spoken(sp):
        r = results.get(l["id"])
        if r:
            l["dur"] = round(r[0], 2)
            l["env"] = r[1]
            l["audio"] = f"voices/{l['id']}.wav"
        else:
            l["dur"] = round(est_dur(l), 2)
            l["audio"] = ""
    sp["provider"] = used
    plain, worst = simulate(sp)
    sp["est_end"] = round(plain, 1)
    sp["duration_hint"] = int(math.ceil(worst + 4.0))
    with open(os.path.join(a.out, "timed.json"), "w", encoding="utf-8") as f:
        json.dump(sp, f, ensure_ascii=False)
    print(f"provider={used} story length ~{plain:.1f}s, clip length hint {sp['duration_hint']}s")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"duration_hint={sp['duration_hint']}\nprovider={used}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
