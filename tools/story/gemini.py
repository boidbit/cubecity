"""Story lab: a small Gemini API client (Python standard library only).

Keys come from the environment: GEMINI_API_KEY and GEMINI_API_KEY_1 ... _9 (or GOOGLE_API_KEY).
When a key is out of quota, refused or invalid, the next one is used. Models are picked from
the ones the key can use, so a renamed or retired model does not break the workflow;
GEMINI_TEXT_MODEL / GEMINI_TTS_MODEL force a specific one.
"""
import base64
import json
import os
import re
import time
import urllib.error
import urllib.request

API = "https://generativelanguage.googleapis.com/v1beta"


class GeminiError(Exception):
    def __init__(self, msg, status=0, retry_after=0.0):
        super().__init__(msg)
        self.status = status
        self.retry_after = retry_after


KEY_NAMES = ["GEMINI_API_KEY"] + [f"GEMINI_API_KEY_{i}" for i in range(1, 10)] + ["GOOGLE_API_KEY"]
_keys = None
_ki = 0


def keys():
    global _keys
    if _keys is None:
        _keys = []
        for name in KEY_NAMES:
            v = os.environ.get(name, "").strip()
            if v and v not in _keys:
                _keys.append(v)
    return _keys


def key():
    k = keys()
    return k[_ki] if _ki < len(k) else ""


def next_key(reason):
    """Moves on to the next key. False if this was the last one."""
    global _ki
    if _ki + 1 >= len(keys()):
        return False
    _ki += 1
    print(f"  switching to Gemini key {_ki + 1} of {len(keys())} ({reason})")
    return True


def key_problem(err):
    """Why this key cannot be used (out of quota, refused, invalid), or "" if it is something else."""
    text = str(err)
    if err.status in (401, 403):
        return "refused"
    if err.status == 400 and re.search(r"API_KEY_INVALID|API key not valid|API key expired", text):
        return "invalid"
    if daily_quota_gone(err):
        return "daily quota used up"
    if err.status == 429 and re.search(r"limit: 0\b|RESOURCE_EXHAUSTED.*free_tier.*limit: 0", text, re.S):
        return "no quota for this model"
    return ""


def _request(method, path, body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Content-Type": "application/json", "x-goog-api-key": key()})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        m = re.search(r'"retryDelay":\s*"(\d+(?:\.\d+)?)s"', text)
        raise GeminiError(f"HTTP {e.code}: {text[:600]}", e.code, float(m.group(1)) if m else 0.0)
    except (urllib.error.URLError, TimeoutError) as e:
        raise GeminiError(f"network: {e}")


def daily_quota_gone(err):
    return err.status == 429 and re.search(r"per ?day|PerDay|daily", str(err), re.I) is not None


def call(path, body, tries=5, max_wait=75, method="POST"):
    """A request with retries: busy or rate-limited answers wait (honouring the server's
    retryDelay); a key that is out of quota or refused is swapped for the next key."""
    i = 0
    while True:
        try:
            return _request(method, path, body)
        except GeminiError as e:
            why = key_problem(e)
            if why:
                if next_key(why):
                    continue
                raise
            busy = e.status in (429, 500, 502, 503, 504) or e.status == 0
            if e.status == 429 and next_key("rate limit"):
                continue
            i += 1
            if not busy or i >= tries:
                raise
            wait = min(max(e.retry_after, 5.0 * i), max_wait)
            print(f"  gemini busy ({e.status or 'network'}), trying again in {wait:.0f}s")
            time.sleep(wait)


_models = None


def models():
    global _models
    if _models is None:
        out, token = [], ""
        while True:
            r = call("/models?pageSize=1000" + (f"&pageToken={token}" if token else ""), None, method="GET")
            out += r.get("models", [])
            token = r.get("nextPageToken", "")
            if not token:
                break
        _models = out
    return _models


def _version(name):
    m = re.search(r"gemini-(\d+)(?:\.(\d+))?", name)
    return (int(m.group(1)), int(m.group(2) or 0)) if m else (0, 0)


def pick(kind, override=""):
    """Best available model for "text" (writing) or "tts" (speech)."""
    if override:
        return override if override.startswith("models/") else "models/" + override
    skip = ("tts", "image", "embedding", "live", "audio", "learnlm", "robotics", "computer", "gemma", "veo", "imagen")
    cands = []
    for m in models():
        name = m.get("name", "")
        low = name.lower()
        if "generateContent" not in m.get("supportedGenerationMethods", []) or not low.startswith("models/gemini"):
            continue
        if kind == "tts":
            if "tts" not in low:
                continue
        elif any(x in low for x in skip):
            continue
        # flash: good, fast and the most generous free quota
        tier = 2 if ("flash" in low and "lite" not in low) else (1 if "pro" in low else 0)
        stable = 0 if ("preview" in low or "exp" in low) else 1
        cands.append(((tier, _version(name), stable), name))
    if not cands:
        raise GeminiError(f"no Gemini {kind} model is available for this key")
    cands.sort(reverse=True)
    return cands[0][1]


def _text_of(r):
    parts = []
    for c in r.get("candidates", [])[:1]:
        for p in c.get("content", {}).get("parts", []):
            if not p.get("thought") and "text" in p:
                parts.append(p["text"])
    return "".join(parts).strip()


def write_json(prompt, system="", temperature=1.0, model=""):
    """Asks for a JSON answer. Returns (parsed JSON, model name)."""
    m = pick("text", model or os.environ.get("GEMINI_TEXT_MODEL", ""))
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": temperature}}
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}
    r = call(f"/{m}:generateContent", body)
    text = _text_of(r)
    if not text:
        raise GeminiError("empty answer: " + json.dumps(r)[:400])
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\s*|\s*```$", "", text)
    return json.loads(text), m


def _audio_of(r):
    for c in r.get("candidates", []):
        for p in c.get("content", {}).get("parts", []):
            d = p.get("inlineData") or p.get("inline_data")
            if d and d.get("data"):
                mime = d.get("mimeType") or d.get("mime_type") or ""
                rate = re.search(r"rate=(\d+)", mime)
                return base64.b64decode(d["data"]), int(rate.group(1)) if rate else 24000
    raise GeminiError("no audio in the answer: " + json.dumps(r)[:400])


def _speech(parts, speech_config, model):
    m = pick("tts", model or os.environ.get("GEMINI_TTS_MODEL", ""))
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": speech_config}}
    pcm, rate = _audio_of(call(f"/{m}:generateContent", body, tries=6))
    return pcm, rate, m


def _metadata_refused(err):
    """An older model that does not know the per-part speech metadata."""
    return err.status == 400 and re.search(r"speech_metadata|speechMetadata|Unknown name", str(err)) is not None


def speak(text, voice, model="", style=""):
    """Text to speech. style: how to say it (not read out). Returns (16-bit mono PCM bytes,
    sample rate, model name)."""
    cfg = {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}
    if style:
        try:
            return _speech([{"text": text, "speech_metadata": {"style": style}}], cfg, model)
        except GeminiError as e:
            if not _metadata_refused(e):
                raise
    return _speech([{"text": text}], cfg, model)


def speak_dialogue(lines, voices, model="", styles=None):
    """A whole conversation between two speakers in one request (one request instead of one
    per line). lines: [(speaker, text)], voices: {speaker: voice name}, styles: how to say
    each line (not read out). Each turn is its own part with speech_metadata.speaker (the
    current API); older models get the "Speaker: text" transcript instead.
    Returns (PCM bytes, sample rate, model name)."""
    if len(voices) != 2:
        raise GeminiError("a dialogue needs exactly two speakers")
    cfg = {"multiSpeakerVoiceConfig": {"speakerVoiceConfigs": [
        {"speaker": who, "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": v}}} for who, v in voices.items()]}}
    styles = styles or [""] * len(lines)
    parts = []
    for (who, t), st in zip(lines, styles):
        meta = {"speaker": who}
        if st:
            meta["style"] = st
        parts.append({"text": t, "speech_metadata": meta})
    try:
        return _speech(parts, cfg, model)
    except GeminiError as e:
        if not _metadata_refused(e):
            raise
    return _speech([{"text": "\n".join(f"{who}: {t}" for who, t in lines)}], cfg, model)
