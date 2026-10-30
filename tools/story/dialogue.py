"""Story lab: cuts a two-speaker conversation (spoken in one Gemini request) into its lines.

Gemini can speak a whole conversation in one request, which on the free plan means one
request per episode instead of one per line. The game needs one clip per line, so the cut
points are worked out from three clues:
  - pauses: lines are separated by silences (a line can also have pauses of its own);
  - pitch: the two characters have different voices, so who is talking shows in the pitch;
  - length: a line takes roughly as long as its text.
A small dynamic programme picks the pauses that fit all three best. split() also reports
whether the result looks trustworthy, so the caller can fall back to one request per line.
"""
import math
import wave

import numpy as np

HOP = 0.01          # analysis step (s)
MIN_GAP = 0.14      # shortest pause that can separate two lines (s)
# how much each clue counts: a line much longer or shorter than its text, a second of the
# wrong voice inside a line, and (a small bonus) cutting at a longer pause. Pauses inside a
# line can be as long as the ones between lines, so the voice counts most.
W_LEN = 2.0
W_PITCH = 10.0
W_GAP = 1.0


def load(path):
    with wave.open(path) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    return x, sr


def features(x, sr):
    """Per 10 ms frame: loudness (dB), pitch (Hz) and whether the frame is voiced."""
    hop = int(sr * HOP)
    win = int(sr * 0.04)
    if len(x) < win:
        x = np.pad(x, (0, win - len(x)))
    frames = np.lib.stride_tricks.sliding_window_view(x, win)[::hop]
    db = 20.0 * np.log10(np.sqrt(np.mean(frames ** 2, axis=1)) + 1e-9)
    w = frames * np.hanning(win)
    ac = np.fft.irfft(np.abs(np.fft.rfft(w, 2 * win)) ** 2)[:, :win]
    ac = ac / (ac[:, :1] + 1e-9)
    lo, hi = int(sr / 400), int(sr / 70)
    lag = np.argmax(ac[:, lo:hi], axis=1) + lo
    peak = ac[np.arange(len(lag)), lag]
    loud = np.percentile(db, 90)
    voiced = (peak > 0.35) & (db > loud - 22.0)
    return db, sr / lag, voiced, loud


def gaps_of(db, loud):
    """Pauses as (start, end) in seconds, not counting silence before the first or after the last word."""
    silent = db < loud - 30.0
    speech = np.nonzero(~silent)[0]
    if len(speech) == 0:
        return [], 0.0, 0.0
    first, last = speech[0], speech[-1]
    out, i = [], first
    while i <= last:
        if silent[i]:
            j = i
            while j <= last and silent[j]:
                j += 1
            if (j - i) * HOP >= MIN_GAP:
                out.append((i * HOP, j * HOP))
            i = j
        else:
            i += 1
    return out, first * HOP, (last + 1) * HOP


def split(path, lines):
    """lines: [(speaker, text)] in order. Returns (spans [(start, end)] in seconds, ok, report)."""
    x, sr = load(path)
    db, f0, voiced, loud = features(x, sr)
    gaps, t0, t1 = gaps_of(db, loud)
    n = len(lines)
    if n == 0:
        return [], True, "no lines"
    if n == 1:
        return [(t0, t1)], True, "one line"

    # who is talking, from the pitch: split the voiced frames into a low and a high voice
    lf = np.log(f0[voiced])
    hi_frame = np.zeros(len(db), dtype=bool)
    pitch_useful = False
    if len(lf) > 50:
        c = np.percentile(lf, [20, 80]).astype(float)
        for _ in range(12):
            lab = np.abs(lf - c[1]) < np.abs(lf - c[0])
            if lab.all() or (~lab).all():
                break
            c = np.array([lf[~lab].mean(), lf[lab].mean()])
        pitch_useful = c[1] - c[0] > math.log(1.18)
        hi_frame[np.nonzero(voiced)[0]] = np.abs(lf - c[1]) < np.abs(lf - c[0])
    if pitch_useful:
        # a change of voice with hardly any pause is a cut point too (quick back and forth)
        vi = np.nonzero(voiced)[0]
        lab = hi_frame[vi].astype(float)
        k = 15
        smooth = np.convolve(lab, np.ones(2 * k + 1) / (2 * k + 1), mode="same") > 0.5
        for m in np.nonzero(smooth[1:] != smooth[:-1])[0]:
            t = (vi[m] + vi[m + 1]) * 0.5 * HOP
            if t0 + 0.3 < t < t1 - 0.3 and all(t < a - 0.6 or t > b + 0.6 for a, b in gaps):
                gaps.append((t, t))
        gaps.sort()
    if len(gaps) < n - 1:
        return [], False, f"only {len(gaps)} pauses for {n} lines"
    cum_hi = np.concatenate([[0], np.cumsum(hi_frame & voiced)])
    cum_v = np.concatenate([[0], np.cumsum(voiced)])

    def frames_in(a, b):
        i, j = int(a / HOP), int(b / HOP)
        return cum_hi[j] - cum_hi[i], cum_v[j] - cum_v[i]

    chars = np.array([max(len(t.strip()), 1) for _, t in lines], dtype=float)
    speaking = (t1 - t0) - 0.35 * (n - 1)
    expect = chars / chars.sum() * max(speaking, 0.5)
    speakers = sorted({s for s, _ in lines})

    # Cut positions: 0 = where the speech starts, 1..G = the pauses, G + 1 = where it ends.
    # A line runs from the end of one cut position to the start of the next one.
    G = len(gaps)

    def line_end(q):
        return gaps[q - 1][0] if 1 <= q <= G else t1

    def next_start(q):
        return gaps[q - 1][1] if 1 <= q <= G else t0

    def solve(high_speaker):
        inf = float("inf")
        best = [[inf] * (G + 2) for _ in range(n + 1)]
        back = [[-1] * (G + 2) for _ in range(n + 1)]
        best[0][0] = 0.0
        for i in range(1, n + 1):
            want_hi = lines[i - 1][0] == high_speaker
            qs = range(i, G + 1) if i < n else [G + 1]
            for q in qs:
                e = line_end(q)
                reward = -W_GAP * min(gaps[q - 1][1] - gaps[q - 1][0], 0.6) if q <= G else 0.0
                for p in range(i - 1, q):
                    if best[i - 1][p] == inf:
                        continue
                    s0 = next_start(p)
                    dur = e - s0
                    if dur < 0.3:
                        continue
                    c = W_LEN * math.log(dur / expect[i - 1]) ** 2 + reward
                    if pitch_useful and high_speaker is not None:
                        h, v = frames_in(s0, e)
                        c += W_PITCH * ((v - h) if want_hi else h) * HOP
                    if best[i - 1][p] + c < best[i][q]:
                        best[i][q] = best[i - 1][p] + c
                        back[i][q] = p
        if best[n][G + 1] == inf:
            return inf, []
        spans, q = [], G + 1
        for i in range(n, 0, -1):
            p = back[i][q]
            spans.append((next_start(p), line_end(q)))
            q = p
        return best[n][G + 1], spans[::-1]

    results = [solve(sp) for sp in speakers] if len(speakers) == 2 else [solve(None)]
    cost, spans = min(results, key=lambda r: r[0])
    if not spans:
        return [], False, "no way to place the cuts"
    # how believable is it
    ratios = [(e - s) / expect[i] for i, (s, e) in enumerate(spans)]
    bad_len = [i + 1 for i, r in enumerate(ratios) if r < 0.35 or r > 2.8]
    report = "lengths " + " ".join(f"{r:.2f}" for r in ratios) + f" | pitch {'used' if pitch_useful else 'not used'}"
    ok = not bad_len
    if bad_len:
        report += f" | odd lengths for lines {bad_len}"
    return spans, ok, report


def cut(path, spans, out_paths, pad_in=0.04, pad_out=0.1):
    """Writes each span to its own wav (same format as the input)."""
    with wave.open(path) as w:
        sr, sw, ch = w.getframerate(), w.getsampwidth(), w.getnchannels()
        data = w.readframes(w.getnframes())
    step = sw * ch
    total = len(data) // step
    for (s, e), out in zip(spans, out_paths):
        a = max(int((s - pad_in) * sr), 0)
        b = min(int((e + pad_out) * sr), total)
        with wave.open(out, "wb") as o:
            o.setnchannels(ch)
            o.setsampwidth(sw)
            o.setframerate(sr)
            o.writeframes(data[a * step:b * step])
