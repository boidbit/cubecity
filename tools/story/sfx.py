"""Story lab: comedy and drama sound effects, made from scratch (no samples, nothing to license).

Each effect is a short mono float array at music.SR. They are the kind of sounds Reels use for
timing jokes and moments: a cartoon boing, the sad trombone, a rimshot after a punchline, a record
scratch on a shock, crickets for an awkward pause, a whoosh on a cut, a riser into a reveal, a
heartbeat, a sparkle, a punch and a bonk.
"""
import numpy as np

from music import SR, add, env, reverb, sting

NAMES = ["boing", "wahwah", "rimshot", "scratch", "crickets", "whoosh", "riser", "heartbeat",
         "sparkle", "punch", "bonk", "slide_up", "slide_down", "ding", "sting"]


def _t(dur):
    return np.arange(int(dur * SR)) / SR


def _tone(freqs, amps=(1.0, 0.5, 0.25, 0.12)):
    """A tone that follows a frequency curve (array, Hz), with a few harmonics."""
    ph = 2 * np.pi * np.cumsum(freqs) / SR
    out = np.zeros(len(freqs))
    for k, a in enumerate(amps, start=1):
        out += a * np.sin(ph * k)
    return out


def _noise(n, rng, colour=0):
    """White noise; colour > 0 darkens it (simple running averages), < 0 brightens it."""
    x = rng.standard_normal(n)
    for _ in range(max(colour, 0)):
        x = np.convolve(x, np.ones(4) / 4, mode="same")
    for _ in range(max(-colour, 0)):
        x = np.diff(np.concatenate([[0.0], x]))
    return x / (np.max(np.abs(x)) or 1.0)


def boing():
    """Cartoon spring: a wobbling pitch that settles."""
    t = _t(0.7)
    f = 260 + 220 * np.exp(-t * 4) * np.sin(2 * np.pi * 9 * t) + 120 * t
    return 0.8 * _tone(f, (1.0, 0.3, 0.1)) * np.exp(-t * 4.0) * env(len(t), 0.004, 0.05)


def wahwah():
    """The sad trombone: four notes sliding down, the last one wobbling."""
    out = np.zeros(int(2.4 * SR))
    for i, (m, d) in enumerate([(58, 0.42), (57, 0.42), (56, 0.42), (55, 1.1)]):
        t = _t(d)
        f0 = 440.0 * 2 ** ((m - 12 - 69) / 12)
        f = f0 * (1 - 0.02 * t / d) * (1 + (0.025 * np.sin(2 * np.pi * 6 * t) if i == 3 else 0))
        # the "wah": brighter in the middle of each note
        bright = 0.3 + 0.7 * np.sin(np.pi * np.clip(t / d, 0, 1))
        note = _tone(f, (1.0, 0.6 * 1.0, 0.45, 0.3, 0.2)) * (0.6 + 0.4 * bright)
        add(out, 0.35 * note * env(len(t), 0.03, 0.08), i * 0.45)
    return out


def rimshot(rng=None):
    """Ba-dum-tss: two tom hits and a cymbal."""
    rng = rng or np.random.default_rng(3)
    out = np.zeros(int(1.6 * SR))
    for at, f in [(0.0, 190.0), (0.16, 140.0)]:
        t = _t(0.3)
        tom = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.5 * np.exp(-t * 30))) / SR) * np.exp(-t * 12)
        add(out, 0.7 * tom, at)
    t = _t(1.3)
    cym = _noise(len(t), rng, -2) * np.exp(-t * 3.0)
    add(out, 0.35 * cym, 0.34)
    add(out, 0.25 * _noise(int(0.05 * SR), rng) * np.exp(-_t(0.05) * 60), 0.34)
    return out


def scratch(rng=None):
    """Record scratch: noise pushed back and forth through a moving band."""
    rng = rng or np.random.default_rng(5)
    t = _t(0.55)
    sweep = np.sin(2 * np.pi * 3.2 * t) * np.exp(-t * 1.5)
    f = 900 + 700 * sweep
    tone = _tone(f, (1.0, 0.7, 0.5, 0.4, 0.3))
    grit = _noise(len(t), rng, -1)
    return 0.45 * (0.6 * tone + 0.5 * grit * np.abs(sweep)) * env(len(t), 0.003, 0.05)


def crickets(rng=None):
    """An awkward silence: a few cricket chirps."""
    out = np.zeros(int(2.2 * SR))
    for k in range(3):
        for c in range(4):
            t = _t(0.025)
            chirp = np.sin(2 * np.pi * 4300 * t) * np.sin(np.pi * t / 0.025)
            add(out, 0.25 * chirp, 0.15 + k * 0.7 + c * 0.045)
    return out


def whoosh(rng=None, dur=0.6):
    """Air rushing past: noise that swells and brightens, then fades."""
    rng = rng or np.random.default_rng(7)
    t = _t(dur)
    n = _noise(len(t), rng, 2)
    bright = _noise(len(t), rng, 0)
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    k = np.clip(t / dur, 0, 1)
    return 0.55 * ((1 - k) * n + k * 0.5 * bright) * shape


def riser(rng=None, dur=1.6):
    """Building up to a reveal: a rising tone and swelling noise, cut at the top."""
    rng = rng or np.random.default_rng(9)
    t = _t(dur)
    f = 180 * 2 ** (2.2 * t / dur)
    tone = _tone(f, (1.0, 0.4, 0.2)) * (t / dur) ** 2
    hiss = _noise(len(t), rng, -1) * (t / dur) ** 3
    return 0.45 * (0.7 * tone + 0.3 * hiss) * env(len(t), 0.05, 0.02)


def heartbeat(rng=None, beats=3):
    """Lub-dub, a few times."""
    out = np.zeros(int((beats * 0.85 + 0.4) * SR))
    for i in range(beats):
        for at, a in [(0.0, 1.0), (0.22, 0.7)]:
            t = _t(0.25)
            thump = np.sin(2 * np.pi * np.cumsum(55 + 40 * np.exp(-t * 25)) / SR) * np.exp(-t * 14)
            add(out, 0.9 * a * thump, i * 0.85 + at)
    return out


def sparkle(rng=None):
    """A twinkle: quick high bell notes going up."""
    out = np.zeros(int(1.6 * SR))
    for i, m in enumerate([84, 88, 91, 96, 100]):
        t = _t(1.0)
        f = 440.0 * 2 ** ((m - 69) / 12)
        note = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t)) * np.exp(-t * 6)
        add(out, 0.18 * note, i * 0.06)
    return reverb(out, seconds=1.0, wet=0.3, seed=2)


def punch(rng=None):
    """A cartoon hit: a fast whoosh into a low thump."""
    rng = rng or np.random.default_rng(11)
    out = np.zeros(int(0.45 * SR))
    add(out, 0.6 * whoosh(rng, 0.12), 0.0)
    t = _t(0.3)
    thump = np.sin(2 * np.pi * np.cumsum(70 + 120 * np.exp(-t * 35)) / SR) * np.exp(-t * 12)
    add(out, thump + 0.3 * _noise(len(t), rng, 1) * np.exp(-t * 40), 0.1)
    return 0.8 * out


def bonk(rng=None):
    """A hollow wooden knock (a knock-out, a head hitting something)."""
    t = _t(0.5)
    f = 520 * (1 - 0.15 * t)
    return 0.6 * (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(f * 2.3) / SR)) * np.exp(-t * 9)


def slide(up=True):
    """A slide whistle going up (something rising) or down (something falling)."""
    t = _t(0.7)
    k = t / 0.7
    f = 500 * 2 ** ((k if up else 1 - k) * 1.6)
    return 0.35 * _tone(f, (1.0, 0.15)) * env(len(t), 0.04, 0.08)


def ding(rng=None):
    """A bell: a good idea, the right answer."""
    t = _t(1.4)
    f = 1320.0
    return 0.35 * (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.0 * t) + 0.2 * np.sin(2 * np.pi * f * 3.01 * t)) * np.exp(-t * 3.5)


def make(name, rng=None):
    rng = rng or np.random.default_rng(1)
    gen = {
        "boing": boing, "wahwah": wahwah, "rimshot": lambda: rimshot(rng), "scratch": lambda: scratch(rng),
        "crickets": lambda: crickets(rng), "whoosh": lambda: whoosh(rng), "riser": lambda: riser(rng),
        "heartbeat": lambda: heartbeat(rng), "sparkle": lambda: sparkle(rng), "punch": lambda: punch(rng),
        "bonk": lambda: bonk(rng), "slide_up": lambda: slide(True), "slide_down": lambda: slide(False),
        "ding": lambda: ding(rng), "sting": lambda: sting().astype(float),
    }.get(name)
    if gen is None:
        return np.zeros(1)
    x = np.asarray(gen(), dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * 0.8
