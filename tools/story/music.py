#!/usr/bin/env python3
"""Story lab: background music made from scratch for each mood (no samples, no licences).

Small additive synths (a plucked string, a soft piano, a warm pad, a bass, a marimba and a few
drums) play a four-chord loop with a sparse little tune on top. Every mood has its own key,
tempo, chords and instruments; the tune is picked by a seed, so two episodes of the same mood
do not sound the same. The music is meant to sit under the voices: no busy lead line.

Usage: tools/story/music.py --mood romantic --seconds 50 [--seed 3] [--intro 2.6] out.wav
"""
import argparse
import hashlib
import wave

import numpy as np

SR = 44100

# key (MIDI note of the root), tempo, chords (scale degrees of a major or minor scale),
# instruments and how busy the drums are
MOODS = {
    "romantic": {"root": 62, "minor": False, "bpm": 76, "prog": [0, 5, 3, 4], "keys": "pluck", "pad": 0.5,
                 "bass": 0.5, "drums": 0, "tune": "bell", "swing": 0.0},
    "happy":    {"root": 60, "minor": False, "bpm": 112, "prog": [0, 4, 5, 3], "keys": "strum", "pad": 0.25,
                 "bass": 0.7, "drums": 2, "tune": "marimba", "swing": 0.0},
    "funny":    {"root": 65, "minor": False, "bpm": 124, "prog": [0, 3, 4, 0], "keys": "staccato", "pad": 0.0,
                 "bass": 0.8, "drums": 1, "tune": "marimba", "swing": 0.18},
    "cringe":   {"root": 63, "minor": False, "bpm": 96, "prog": [0, 5, 1, 4], "keys": "pluck", "pad": 0.35,
                 "bass": 0.6, "drums": 1, "tune": "bell", "swing": 0.12},
    "sad":      {"root": 57, "minor": True, "bpm": 64, "prog": [0, 5, 2, 6], "keys": "piano", "pad": 0.6,
                 "bass": 0.4, "drums": 0, "tune": "piano", "swing": 0.0},
    "action":   {"root": 52, "minor": True, "bpm": 138, "prog": [0, 0, 5, 6], "keys": "ostinato", "pad": 0.4,
                 "bass": 1.0, "drums": 3, "tune": "", "swing": 0.0},
    "twist":    {"root": 55, "minor": True, "bpm": 92, "prog": [0, 5, 3, 4], "keys": "pluck", "pad": 0.55,
                 "bass": 0.6, "drums": 1, "tune": "bell", "swing": 0.0},
}
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def env(n, attack, release=0.0):
    e = np.ones(n)
    a = min(int(attack * SR), n)
    if a > 0:
        e[:a] = np.linspace(0.0, 1.0, a)
    r = min(int(release * SR), n)
    if r > 0:
        e[n - r:] *= np.linspace(1.0, 0.0, r)
    return e


def partials(f, dur, amps, decays, attack=0.004, detune=0.0):
    """A note as a sum of harmonics, each fading at its own rate (higher ones faster)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, (a, d) in enumerate(zip(amps, decays), start=1):
        fk = f * k * (1.0 + detune * k * k)
        if fk > SR * 0.45:
            break
        out += a * np.sin(2 * np.pi * fk * t) * np.exp(-d * t)
    return out * env(n, attack, 0.02)


def pluck(f, dur):
    return partials(f, dur, [1, 0.6, 0.35, 0.22, 0.12, 0.08, 0.05], [2.2, 3.5, 5, 7, 9, 12, 15], detune=0.0004)


def piano(f, dur):
    return partials(f, dur, [1, 0.45, 0.25, 0.12, 0.08, 0.04], [1.2, 2.0, 3.0, 4.5, 6, 8], attack=0.006)


def bell(f, dur):
    return 0.7 * partials(f, dur, [1, 0.0, 0.3, 0.0, 0.1], [2.5, 3, 4, 5, 7], attack=0.003)


def marimba(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * f * t) * np.exp(-9 * t) + 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-30 * t)
    return out * env(n, 0.002, 0.01)


def bass(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t) + 0.1 * np.sin(2 * np.pi * 3 * f * t)
    return out * np.exp(-2.5 * t) * env(n, 0.008, 0.04)


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            ff = f * (1 + det)
            # a slow 0.2 % vibrato (the phase is the integral of the wobbling frequency)
            ph = 2 * np.pi * ff * t - ff * 0.002 / 5.0 * np.cos(2 * np.pi * 5.0 * t)
            # a soft triangle-ish tone: odd harmonics falling fast
            out += np.sin(ph) + np.sin(3 * ph) / 9.0 + np.sin(5 * ph) / 25.0
    out /= max(len(freqs) * 3, 1)
    return out * env(n, min(0.6, dur * 0.4), min(0.5, dur * 0.3))


def kick(rng):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 80 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def snare(rng):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = np.diff(rng.standard_normal(n + 1))
    return (0.6 * noise * np.exp(-t * 18) + 0.4 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)) * 0.5


def hat(rng):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    return np.diff(np.diff(rng.standard_normal(n + 2))) * np.exp(-t * 70) * 0.12


def clap(rng):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    e = np.exp(-t * 25) + 0.6 * np.exp(-np.maximum(t - 0.012, 0) * 30) * (t > 0.012)
    return np.diff(rng.standard_normal(n + 1)) * e * 0.35


def add(buf, x, at):
    i = int(at * SR)
    if i >= len(buf) or i < 0:
        return
    j = min(len(buf), i + len(x))
    buf[i:j] += x[:j - i]


def reverb(x, seconds=1.4, wet=0.22, seed=1):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / seconds)
    ir[0] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return x + wet * y


def chord_notes(m, degree, octave=0):
    scale = MINOR if m["minor"] else MAJOR
    root = m["root"] + 12 * octave
    return [root + scale[(degree + i) % 7] + 12 * ((degree + i) // 7) for i in (0, 2, 4)]


def make(mood, seconds, seed=0, intro=2.6):
    m = MOODS.get(mood, MOODS["romantic"])
    rng = np.random.default_rng(seed)
    beat = 60.0 / m["bpm"]
    bar = beat * 4
    n = int((seconds + 2.0) * SR)
    keys = np.zeros(n)
    low = np.zeros(n)
    drums = np.zeros(n)
    tune = np.zeros(n)
    scale = MINOR if m["minor"] else MAJOR
    t0 = intro           # the groove starts after the title card; the pad plays under it
    bars = int((seconds - t0) / bar) + 2

    # the pad holds each chord from the very start
    total_bars = int(seconds / bar) + 2
    for b in range(total_bars):
        deg = m["prog"][b % 4]
        if m["pad"] > 0:
            add(keys, m["pad"] * 0.5 * pad([hz(x) for x in chord_notes(m, deg, 0)], bar + 0.4), b * bar)

    # a tune: a few notes every other bar, stepping around the chord, then resting
    motif = []
    if m["tune"]:
        pos = int(rng.integers(0, 3))
        for i in range(6):
            pos = max(0, min(6, pos + int(rng.choice([-2, -1, 1, 1, 2]))))
            motif.append(pos)
        rhythm = [0.0, 1.0, 1.5, 2.0, 3.0] if m["bpm"] > 100 else [0.0, 1.5, 2.0, 3.0]
    for b in range(bars):
        start = t0 + b * bar
        deg = m["prog"][b % 4]
        notes = chord_notes(m, deg, 0)
        # rhythm part
        if m["keys"] == "pluck":
            for i in range(8):
                f = hz(notes[[0, 1, 2, 1][i % 4]] + (12 if i >= 4 else 0))
                add(keys, 0.32 * pluck(f, beat * 2.5), start + i * beat * 0.5 + (m["swing"] * beat * 0.5 if i % 2 else 0))
        elif m["keys"] == "strum":
            for i, w in enumerate([0, 1.5, 2, 3]):
                for j, x in enumerate(notes + [notes[0] + 12]):
                    add(keys, 0.16 * pluck(hz(x), beat * 1.6), start + w * beat + j * 0.012)
        elif m["keys"] == "staccato":
            for i in range(4):
                f = hz(notes[i % 3] + 12)
                add(keys, 0.3 * marimba(f, 0.3), start + (i + 0.5) * beat + (m["swing"] * beat * 0.5))
        elif m["keys"] == "piano":
            for i, x in enumerate([notes[0], notes[2], notes[1] + 12, notes[2]]):
                add(keys, 0.3 * piano(hz(x), beat * 3), start + i * beat)
        elif m["keys"] == "ostinato":
            for i in range(8):
                x = notes[0] + (12 if i % 4 == 3 else 0)
                add(keys, 0.22 * pluck(hz(x), beat * 0.6), start + i * beat * 0.5)
        # bass
        r = hz(notes[0] - 12)
        if m["bpm"] >= 110:
            for i in range(4):
                add(low, m["bass"] * 0.55 * bass(r if i % 2 == 0 else r * 1.5, beat * 0.9),
                    start + i * beat + (m["swing"] * beat * 0.5 if i % 2 else 0))
        else:
            add(low, m["bass"] * 0.55 * bass(r, bar * 0.95), start)
            add(low, m["bass"] * 0.4 * bass(r * 1.5, beat * 1.5), start + beat * 2.5)
        # drums
        lvl = m["drums"]
        if lvl >= 1:
            for i in range(4):
                if i % 2 == 0:
                    add(drums, 0.55 * kick(rng), start + i * beat)
                else:
                    add(drums, 0.5 * (clap(rng) if lvl < 3 else snare(rng)), start + i * beat)
        if lvl >= 2:
            for i in range(8):
                add(drums, hat(rng), start + i * beat * 0.5 + (m["swing"] * beat * 0.5 if i % 2 else 0))
        if lvl >= 3:
            for i in range(16):
                add(drums, 0.7 * hat(rng), start + i * beat * 0.25)
            add(drums, 0.4 * kick(rng), start + 2.5 * beat)
        # tune on odd bars
        if motif and b % 2 == 1:
            inst = {"bell": bell, "marimba": marimba, "piano": piano}[m["tune"]]
            for i, w in enumerate(rhythm):
                deg_note = scale[(deg + motif[i % len(motif)]) % 7] + 12 * ((deg + motif[i % len(motif)]) // 7)
                f = hz(m["root"] + 12 + deg_note)
                add(tune, 0.2 * inst(f, beat * 1.5), start + w * beat)

    mix = 0.9 * keys + 0.8 * low + 0.6 * drums + tune
    mix = reverb(mix, wet=0.28 if m["bpm"] < 100 else 0.16, seed=seed + 1)
    mix = mix[:int(seconds * SR)]
    # fade in under the title, fade out at the very end
    mix *= env(len(mix), 1.5, 2.0)
    peak = np.max(np.abs(mix)) or 1.0
    return (mix / peak * 0.7).astype(np.float32)


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    stereo = np.repeat(pcm[:, None], 2, axis=1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(stereo.tobytes())


def seed_of(text):
    return int(hashlib.sha1(text.encode("utf-8")).hexdigest()[:8], 16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--mood", default="romantic")
    ap.add_argument("--seconds", type=float, default=45.0)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--intro", type=float, default=2.6)
    a = ap.parse_args()
    write_wav(a.out, make(a.mood, a.seconds, a.seed, a.intro))
    print(f"music: {a.mood}, {a.seconds:.1f}s -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
