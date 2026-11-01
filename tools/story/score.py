"""Story lab: scores an episode after it has been recorded: music that changes with the story,
and comedy / drama sound effects on the moments that need them.

The game's log has the real time of every line, action and event, the screenplay has who said
what and how they felt. From those:
  - music cues: the episode's base mood, then romance for love, tension when things go wrong,
    action for a chase or a fight, sad for tears, a quick dropout before a shock, silence under
    the punchline and a finale for the end card; {"music": cue} beats in the screenplay win.
  - sound effects: a boing when somebody falls, a punch on every hit, a record scratch on a
    comic shock, the sad trombone after a comic sad line, crickets after an awkward one, a
    sparkle or a heartbeat for love, a whoosh on big moves, a riser into a reveal, a rimshot
    after the punchline; {"sfx": name} beats in the screenplay add more.
build() returns the music track, the effects track and a list of what was placed (for the run page).
"""
import numpy as np

import music
import sfx as sfx_mod

SR = music.SR
CUES = ["calm", "romantic", "happy", "comic", "sad", "tension", "action", "silence"]
COMIC_MOODS = ("funny", "cringe", "dark")
CUE_MUSIC = {"calm": "calm", "romantic": "romantic", "happy": "happy", "comic": "funny", "sad": "sad",
             "tension": "tension", "action": "action"}
BASE = {"funny": "comic", "cringe": "comic", "dark": "comic", "happy": "happy", "romantic": "romantic",
        "sad": "sad", "action": "calm", "drama": "calm", "twist": "calm"}
MUSIC_RMS = 0.11
MIN_CUE = 3.5          # a cue plays at least this long before the next change (except hits)


def _timeline(sp, log):
    """Lines with their real times and feelings, actions and events."""
    beats = sp.get("beats", [])
    by_id = {b["id"]: b for b in beats if "say" in b}
    lines = []
    for p in log.get("lines", []):
        b = by_id.get(p.get("id"))
        if not b:
            continue
        dur = float(b.get("dur", 2.0))
        if p.get("cut") is not None:
            dur = float(p["cut"])
        lines.append({"t": float(p["t"]), "end": float(p["t"]) + dur, "who": b.get("say", ""),
                      "emotion": b.get("emotion", "neutral"), "react": b.get("react", "neutral"), "id": b["id"]})
    # where the ending starts: just before the first line that comes after the "end" beat
    end_at = None
    seen_end = False
    for b in beats:
        if "end" in b:
            seen_end = True
        elif seen_end and "say" in b:
            for ln in lines:
                if ln["id"] == b["id"]:
                    end_at = ln["t"] - 0.4
                    break
            break
    if end_at is None and float(log.get("end", -1)) > 0:
        end_at = float(log["end"]) - 1.0
    return lines, log.get("actions", []), log.get("events", []), end_at


def plan(sp, log, mood, seconds):
    """Decides the cues [(t, cue, hard)] and the effects [(t, name, gain)]."""
    lines, actions, events, end_at = _timeline(sp, log)
    comic = mood in COMIC_MOODS
    base = BASE.get(mood, "calm")
    cues = [(0.0, base, True)]
    fx = []

    def cue(t, c, hard=False):
        cues.append((max(t, 0.0), c, hard))

    def effect(t, name, gain=1.0):
        fx.append((max(t, 0.0), name, gain))

    # while a chase or a fight is on, the action music stays whatever is said
    locks = []
    t_on = None
    for item in sorted([(float(a.get("t", 0)), a.get("do", "")) for a in actions] +
                       [(float(e.get("t", 0)), e.get("type", "")) for e in events]):
        if item[1] in ("chase", "drive_off", "fight") and t_on is None:
            t_on = item[0]
        elif item[1] in ("cornered", "won") and t_on is not None:
            locks.append((t_on, item[0]))
            t_on = None
    if t_on is not None:
        locks.append((t_on, seconds))

    def locked(t):
        return any(a - 0.2 <= t <= b for a, b in locks) or (end_at is not None and t >= end_at - 0.2)

    # feelings in the lines; what a feeling does to the music depends on the kind of episode
    serious = mood in ("action", "drama", "twist", "sad")
    loved = False
    wahs = []
    relax = []          # light lines: the music can let go of tension here
    for i, ln in enumerate(lines):
        e = ln["emotion"]
        light = ("happy", "laugh", "smug", "love")
        if e in light and i > 0 and lines[i - 1]["emotion"] in light:
            relax.append(ln["t"])         # two light lines in a row: the talk has turned easy
        if locked(ln["t"]):
            continue
        if e == "love":
            if mood != "sad":
                cue(ln["t"], "romantic")
            if not loved:
                effect(ln["t"] + 0.1, "sparkle" if comic else "heartbeat", 0.7)
                loved = True
        elif e in ("sad", "cry"):
            if comic:
                # the sad trombone, not too often
                if len(wahs) < 2 and (not wahs or ln["end"] - wahs[-1] > 20.0):
                    effect(ln["end"] + 0.15, "wahwah", 0.8)
                    wahs.append(ln["end"])
            elif serious or e == "cry":
                cue(ln["t"], "sad")
        elif e == "shock":
            if comic:
                effect(ln["t"] - 0.05, "scratch", 0.9)
                cue(ln["t"] - 0.1, "silence", True)
                cue(ln["end"] + 0.2, base, True)
            elif serious:
                cue(ln["t"], "tension")
        elif e in ("angry", "scared") and serious:
            cue(ln["t"], "tension")
        elif e == "think" and comic:
            nxt = lines[i + 1]["t"] if i + 1 < len(lines) else ln["end"] + 3
            if nxt - ln["end"] > 1.0:
                effect(ln["end"] + 0.1, "crickets", 0.6)

    # what happens
    for a in actions:
        t = float(a.get("t", 0))
        kind = a.get("do", "")
        if kind == "music" and a.get("type") in CUES:
            cue(t, a["type"], True)
        elif kind == "sfx" and a.get("type") in sfx_mod.NAMES:
            effect(t, a["type"])
        elif kind == "fall":
            effect(t + 0.25, "boing" if comic or mood != "sad" else "bonk", 0.9)
        elif kind == "arrive":
            cue(t, "silence", True)
            effect(t, "riser", 0.6)
        elif kind in ("drive_off", "chase", "police", "fight"):
            cue(t, "action", True)
        elif kind == "calm":
            cue(t, base)
        elif kind in ("hug",):
            cue(t, "romantic")
        elif kind in ("dance", "cheer"):
            cue(t, "happy")
        elif kind == "shot" and a.get("type") == "zoom":
            cue(t - 0.05, "silence", True)
            effect(t, "sting", 0.9)
            cue(t + 2.8, "tension", True)
        elif kind == "kneel":
            effect(t + 0.2, "heartbeat", 0.6)
        elif kind in ("exit_car", "park"):
            pass
    for e in events:
        t = float(e.get("t", 0))
        kind = e.get("type", "")
        if kind in ("car_arrived", "grabbed"):
            cue(t, "tension", True)
        elif kind == "cornered":
            cue(t, "tension", True)
            effect(t, "whoosh", 0.7)
        elif kind == "won":
            cue(t, "happy", True)
        elif kind == "hit":
            effect(t, "punch", 0.9)
        elif kind == "ko":
            effect(t, "punch", 1.0)
            effect(t + 0.25, "bonk", 0.8)
        elif kind == "takeoff" and t > 3.0 and any(x.get("type") == "big_air" and 0 < float(x.get("t", 0)) - t < 3.0 for x in events):
            effect(t, "whoosh", 0.7)       # a real jump (it lands as big air)
        elif kind == "near_miss" and t > 3.0:
            effect(t, "whoosh", 0.6)

    # the ending: a finale under the end, silence under the punchline, then the button
    if end_at is not None:
        ending = log.get("ending", "")
        fin = {"crash": "sad", "cliffhanger": "tension", "caught": "tension"}.get(ending, "happy" if comic else "romantic")
        if mood == "sad":
            fin = "sad"
        cue(end_at, fin, True)
        if lines:
            last = lines[-1]
            if last["t"] >= end_at - 0.5:
                cue(last["t"] - 0.15, "silence", True)
                cue(last["end"] + 0.5, fin, True)
                effect(last["end"] + 0.15, "rimshot" if comic else "sparkle", 0.9 if comic else 0.6)
    for a in actions:
        if a.get("do") == "shot" and a.get("type") == "zoom":
            z = float(a.get("t", 0))
            during = [c for c in cues if z - 0.04 < c[0] < z + 2.8 and c[1] != "silence"]
            before = [c for c in cues if c[0] <= z - 0.06 and c[1] != "silence"]
            cues = [c for c in cues if c not in during]
            # after the sting: what was asked for during it, else tension (comedy goes back to its tune)
            nxt = max(during, key=lambda c: c[0])[1] if during else (base if comic else "tension")
            cue(z + 2.8, nxt, True)
    # a light line (or one during a sting) lets go of tension or sadness
    zooms = [float(a.get("t", 0)) for a in actions if a.get("do") == "shot" and a.get("type") == "zoom"]
    if mood != "sad":
        for t in relax:
            for z in zooms:
                if z - 0.1 <= t < z + 2.8:
                    t = z + 2.8
            if locked(t):
                continue
            now = [c for c in sorted(cues, key=lambda c: c[0]) if c[0] <= t + 0.05 and c[1] != "silence"]
            if now and now[-1][1] in ("tension", "sad"):
                cue(t, base, True)
    return _tidy(cues, seconds), _tidy_fx(fx)


def _tidy(cues, seconds):
    """In time order; a soft change too soon after the last one is dropped; repeats merged."""
    cues = sorted(cues, key=lambda c: c[0])
    out = []
    for t, c, hard in cues:
        if t >= seconds:
            continue
        if out and out[-1][1] == c:
            continue
        if out and not hard and t - out[-1][0] < MIN_CUE and out[-1][1] != "silence":
            continue
        if out and (abs(t - out[-1][0]) < 0.05 or (hard and out[-1][1] != "silence" and t - out[-1][0] < 1.5 and len(out) > 1)):
            out[-1] = (out[-1][0] if abs(t - out[-1][0]) >= 0.05 else t, c, hard)
        else:
            out.append((t, c, hard))
    return out


def _tidy_fx(fx):
    """Not too many: hits in a fight come close together, everything else keeps 1.5 s apart."""
    fx = sorted(fx, key=lambda f: f[0])
    out = []
    for t, name, g in fx:
        if out and name not in ("punch", "bonk") and t - out[-1][0] < 1.5:
            continue
        out.append((t, name, g))
    return out


def build(sp, log, mood, seconds, seed=0):
    """Returns (music track, effects track, report lines)."""
    cues, fx = plan(sp, log, mood, seconds)
    n = int(seconds * SR)
    track = np.zeros(n)
    used = sorted({c for _, c, _ in cues if c != "silence"})
    voices = {c: music.make(CUE_MUSIC[c], seconds, seed + i, rms=MUSIC_RMS).astype(float) for i, c in enumerate(used)}
    # each cue plays from its start to the next cue, crossfaded; silence fades out quickly
    for i, (t, c, hard) in enumerate(cues):
        t_end = cues[i + 1][0] if i + 1 < len(cues) else seconds
        if c == "silence":
            continue
        fade_in = 0.12 if hard else 0.6
        nxt_silence = i + 1 < len(cues) and cues[i + 1][1] == "silence"
        fade_out = 0.15 if nxt_silence else 0.6
        a = int(max(t - (0.0 if hard else 0.3), 0) * SR)
        b = min(int((t_end + (0.0 if nxt_silence else 0.3)) * SR), n)
        if b <= a:
            continue
        g = np.ones(b - a)
        fi = min(int(fade_in * SR), len(g))
        fo = min(int(fade_out * SR), len(g))
        if fi > 0:
            g[:fi] *= np.linspace(0, 1, fi)
        if fo > 0:
            g[-fo:] *= np.linspace(1, 0, fo)
        track[a:b] += voices[c][a:b] * g
    effects = np.zeros(n)
    rng = np.random.default_rng(seed)
    for t, name, g in fx:
        music.add(effects, 0.75 * g * sfx_mod.make(name, rng), t)
    report = [f"{t:5.1f}s music: {c}" for t, c, _ in cues] + [f"{t:5.1f}s sfx: {name}" for t, name, _ in fx]
    report.sort()
    return track.astype(np.float32), effects.astype(np.float32), report
