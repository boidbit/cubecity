#!/usr/bin/env python3
"""Notes for a chase / action video's entry on the studio page (one GitHub release per video).

Usage: tools/release_notes.py summary.json upload.txt notes.md
Prints the release title. The workflow's inputs come in as JSON in $SETTINGS and the release's
file names in $FILES (JSON: video, thumbnail, upload). The notes end with the same hidden data
block as the story videos (tools/story/release.py), which the studio page (site/) reads.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "story"))
import release as story_release  # noqa: E402
import upload_text  # noqa: E402

MODES = {"escape": "🏁 Escape", "chase": "🚓 Police chase", "heli": "🚁 Helicopter", "rush": "🚗 Rush hour", "stunt": "🤸 Stunts",
         "destroy": "💥 Destroy the city", "survive": "⭐ Survive 5 stars", "race": "🏁 Car vs train"}


def stats(s):
    out = [("🚓 police", s.get("max_cops", 0)), ("💥 wrecked", s.get("cops_wrecked", 0))]
    for key, label in (("collapses", "🏢 buildings down"), ("near_miss", "😳 near misses"), ("big_air", "🛫 jumps"),
                       ("heli_down", "🚁 helicopter down"), ("mega_jump", "🏙️ tower jumps"), ("train_hits", "🚂 train hits"),
                       ("emp_hits", "⚡ EMP"), ("spike_cops", "📌 spiked"), ("oil_spins", "🛢️ spun out"), ("cash", "💰 cash")):
        if s.get(key):
            out.append((label, s[key]))
    if s.get("mode") == "destroy" and s.get("cubes"):
        out.append(("🧱 cubes", f"{int(s['cubes']):,}"))
    if s.get("mode") == "race":
        winner = str(s.get("race_winner") or "undecided").upper()
        out.append(("🏁 winner", winner))
        if int(s.get("race_lead_changes", 0)):
            out.append(("🔁 lead changes", s["race_lead_changes"]))
        for key, label in (("race_car_time", "🚗 car finish"), ("race_train_time", "🚂 train finish")):
            value = float(s.get(key, -1.0))
            if value >= 0.0:
                out.append((label, f"{value:.2f}s"))
    else:
        out.append(("🏁", "safehouse" if s.get("safehouse") else ("escaped" if s.get("end") == "survived" else str(s.get("end", "")))))
    return [[k, str(v)] for k, v in out if str(v) not in ("", "0")]


def data(s, upload, env):
    desc = upload_text.description(s)
    tags = upload_text.hashtags(s)
    joined = " ".join(tags)
    if desc.endswith(joined):
        desc = desc[: -len(joined)].rstrip()
    try:
        settings = {k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in json.loads(env.get("SETTINGS") or "{}").items()}
    except ValueError:
        settings = {}
    try:
        files = json.loads(env.get("FILES") or "{}")
    except ValueError:
        files = {}
    run_id = env.get("VIDEO_RUN_ID") or env.get("GITHUB_RUN_ID", "")
    repo = env.get("GITHUB_REPOSITORY", "")
    server = env.get("GITHUB_SERVER_URL", "https://github.com")
    mode = str(s.get("mode", "chase"))
    titles = upload_text.titles(s)
    return {
        "v": 1,
        "kind": "chase",
        "title": str(s.get("title", "")),
        "episode": titles[0] if titles else str(s.get("title", "")),
        "mood": mode,
        "mode_label": MODES.get(mode, mode),
        "seconds": round(float(s.get("duration") or 0.0), 1),
        "titles": titles,
        "description": desc,
        "hashtags": tags,
        "yt_tags": upload_text.tags(s),
        "upload": upload,
        "stats": stats(s),
        "excitement": s.get("excitement", 0),
        "settings": settings,
        "files": files,
        "run": {"id": run_id, "number": env.get("VIDEO_RUN_NUMBER") or env.get("GITHUB_RUN_NUMBER", ""),
                "url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else ""},
    }


def notes(d):
    out = [f"## {d['mode_label']}: {d['episode']}",
           " · ".join([f"hook **{d['title']}**" if d["title"] else "", f"{d['seconds']:.0f} s"] +
                      [f"{k} {v}" for k, v in d["stats"]]).strip(" ·"), ""]
    out += ["### Titles (pick one)"] + [f"{i + 1}. {t}" for i, t in enumerate(d["titles"])] + [""]
    out += ["### Description", d["description"], "", " ".join(d["hashtags"]), ""]
    out += ["`upload.txt` is the full text to paste (titles, description, tags, pinned comment).", ""]
    if d["run"]["url"]:
        out += [f"Made by [run #{d['run']['number']}]({d['run']['url']}).", ""]
    out += [story_release.block(d), ""]
    return "\n".join(out)


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    with open(argv[0], encoding="utf-8") as f:
        s = json.load(f)
    with open(argv[1], encoding="utf-8") as f:
        upload = f.read()
    d = data(s, upload, os.environ)
    with open(argv[2], "w", encoding="utf-8") as f:
        f.write(notes(d))
    print(f"{d['mode_label'].split()[0]} {d['episode']}"[:120])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
