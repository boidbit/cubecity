#!/usr/bin/env python3
"""Story lab: the notes for a video's entry on the studio page (one GitHub release per video).

Usage: tools/story/release.py timed.json story_log.json upload.txt notes.md
Prints the release title. The notes read well on GitHub and end with a hidden JSON block
(<!-- studio-data ... -->) that the studio page (site/) reads: titles, description, hashtags,
the lines, and the settings the video was made with (from the workflow's environment).
"""
import json
import os
import sys

# workflow input -> environment variable the story workflow sets for it
SETTINGS = {"story_type": "STORY_TYPE", "idea": "IDEA", "template": "TEMPLATE", "script": "SCRIPT",
            "language": "LANGUAGE", "voice": "VOICE", "music": "MUSIC", "orientation": "ORIENTATION",
            "fps": "FPS_IN", "time": "TIME_IN", "seed": "SEED_USED"}
MARK = "studio-data"


def data(sp, log, upload_text, env):
    cast = sp.get("cast", {})
    up = sp.get("upload") if isinstance(sp.get("upload"), dict) else {}
    tags = [h if str(h).startswith("#") else "#" + str(h) for h in up.get("hashtags", [])][:10]
    if tags and "#shorts" not in tags:
        tags.insert(0, "#shorts")
    lines = []
    for b in sp.get("beats", []):
        if "say" in b:
            who = cast.get(b["say"], {}).get("name") or str(b["say"])
            lines.append({"who": str(who).title(), "emotion": b.get("emotion", "neutral"), "text": b.get("sub", "")})
    run_id = env.get("GITHUB_RUN_ID", "")
    server = env.get("GITHUB_SERVER_URL", "https://github.com")
    repo = env.get("GITHUB_REPOSITORY", "")
    return {
        "v": 1,
        "title": sp.get("title", ""),
        "episode": sp.get("episode", ""),
        "mood": sp.get("mood", ""),
        "writer": sp.get("writer", "saved episode"),
        "voices": sp.get("provider", ""),
        "ending": log.get("ending") or "",
        "seconds": round(float(log.get("end") or 0.0), 1),
        "titles": [str(t) for t in up.get("titles", []) if str(t).strip()][:3],
        "description": str(up.get("description", "")).strip(),
        "hashtags": tags,
        "upload": upload_text,
        "lines": lines,
        "settings": {k: env.get(v, "") for k, v in SETTINGS.items()},
        "run": {"id": run_id, "number": env.get("GITHUB_RUN_NUMBER", ""),
                "url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else ""},
    }


def notes(d):
    """Markdown for the release page, with the data block hidden at the end."""
    head = d["episode"] or d["title"] or "Story video"
    meta = [f"**{d['title']}**" if d["title"] else "", f"mood **{d['mood']}**" if d["mood"] else "",
            f"ending: {d['ending']}" if d["ending"] else "", f"{d['seconds']:.0f} s" if d["seconds"] else "",
            f"written by {d['writer']}", f"voices: {d['voices']}" if d["voices"] else ""]
    out = [f"## 🎬 {head}", " · ".join(m for m in meta if m), ""]
    if d["titles"]:
        out += ["### Titles (pick one)"] + [f"{i + 1}. {t}" for i, t in enumerate(d["titles"])] + [""]
    if d["description"] or d["hashtags"]:
        out += ["### Description", d["description"], "", " ".join(d["hashtags"]), ""]
    if d["lines"]:
        out += ["<details><summary>Lines</summary>", ""]
        out += [f"- **{ln['who']}** _({ln['emotion']})_: {ln['text']}" for ln in d["lines"]]
        out += ["", "</details>", ""]
    out += ["`story.mp4` has music; `story_nomusic.mp4` has none (put a trending sound under it in the app). "
            "`upload.txt` is the full text to paste.", ""]
    if d["run"]["url"]:
        out += [f"Made by [run #{d['run']['number']}]({d['run']['url']}).", ""]
    # "-->" would end the comment early; > is the same character inside a JSON string
    blob = json.dumps(d, ensure_ascii=False, indent=1).replace("-->", "--\\u003e")
    out += [f"<!-- {MARK}", blob, "-->", ""]
    return "\n".join(out)


def title(d):
    name = d["episode"] or d["title"] or "Story video"
    return f"🎬 {name}" + (f" · {d['mood']}" if d["mood"] else "")


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    with open(argv[0], encoding="utf-8") as f:
        sp = json.load(f)
    with open(argv[1], encoding="utf-8") as f:
        log = json.load(f)
    with open(argv[2], encoding="utf-8") as f:
        upload_text = f.read()
    d = data(sp, log, upload_text, os.environ)
    with open(argv[3], "w", encoding="utf-8") as f:
        f.write(notes(d))
    print(title(d))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
