#!/usr/bin/env python3
"""Writes ready-to-paste YouTube text (titles, description, tags, hashtags, pinned
comment) for one recorded run, using that run's real numbers.

Usage: tools/upload_text.py summary.json [out.txt]   (prints to stdout without out.txt)
"""
import json
import sys

# what each logged event looks like in a description, in the order they are listed
MOMENTS = [
    ("trap", "the barrel trap that blows up the police"),
    ("collapse", "buildings coming down"),
    ("gas", "a gas station explosion"),
    ("chain", "chain explosions"),
    ("big_air", "ramp jumps"),
    ("roadblock", "a police roadblock"),
    ("swat", "the SWAT truck"),
    ("heli", "the police helicopter"),
    ("broke_free", "a close call with the BUSTED meter"),
]

TAGS = ["police chase", "car chase", "bot gameplay", "destruction game", "indie game",
        "mobile game", "godot", "godot engine", "voxel destruction", "satisfying destruction",
        "wanted level", "game bot", "cube city chase"]


def titles(s):
    mode = s.get("mode", "chase")
    dur = int(round(float(s.get("duration", 55))))
    cops = max(int(s.get("max_cops", 0)), int(s.get("cops_wrecked", 0)))
    wrecked = int(s.get("cops_wrecked", 0))
    falls = int(s.get("collapses", 0))
    trapped = any(e.get("type") == "trap" for e in s.get("events", []))
    if mode == "destroy":
        out = ["Can a Bot Destroy the Whole City? 🏙️💥",
               f"Bot vs The City: {falls} Buildings Down 💥" if falls >= 2 else "Bot vs The City: Smashing Everything 💥",
               "This Bot Drives Straight Through Buildings 😳"]
    elif mode == "survive":
        out = [f"Can a Bot Survive 5 Stars for {dur} Seconds? 🚨",
               f"{cops} Cops vs 1 Car: Max Wanted Level 🚓",
               f"5 Star Police Chase: {wrecked} Cops Wrecked 💥" if wrecked >= 3 else "5 Star Police Chase, No Escape? 🚨"]
    else:
        out = [f"1 Car vs {cops} Cops 🚓 Can It Escape?",
               f"{wrecked} Cops Wrecked in {dur} Seconds 💥" if wrecked >= 3 else "Police Chase Through a City of Cubes 🚨",
               "The Bot Led the Police Into a Trap 😳" if trapped else "Can a Bot Outrun the Whole Police Force? 🚨"]
    return [t[:100] for t in out]


def description(s):
    mode = s.get("mode", "chase")
    events = {e.get("type") for e in s.get("events", [])}
    seen = [text for kind, text in MOMENTS if kind in events]
    hook = {
        "destroy": "A bot tries to smash the whole city. How much can it destroy before the police shut it down?",
        "survive": "Five stars from the first second. Can the bot stay ahead of the whole police force?",
    }.get(mode, "One car, a growing pack of police, and no way out. Can the bot escape?")
    lines = [hook, ""]
    lines.append(f"🚓 Police in the chase: {s.get('max_cops', 0)}")
    lines.append(f"💥 Police cars wrecked: {s.get('cops_wrecked', 0)}")
    if s.get("collapses"):
        lines.append(f"🏢 Buildings brought down: {s['collapses']}")
    if mode == "destroy":
        lines.append(f"🏙️ City destroyed: {float(s.get('destroyed_pct', 0)):.2f}%")
    if seen:
        if len(seen) > 1:
            lines.append("👀 Watch for " + ", ".join(seen[:-1]) + " and " + seen[-1] + ".")
        else:
            lines.append("👀 Watch for " + seen[0] + ".")
    lines += [
        "",
        "This run is played by a bot in Cube City Chase, a car chase and destruction game I'm making "
        "with the Godot engine. Everything in it (the city, cars, explosions and sounds) is generated in code.",
        "",
        "🎮 Play the game: [add your Play Store link here]",
        "🔔 Subscribe for more bot runs. Which mode next: chase, destroy or survive? Tell me in the comments!",
        "",
        " ".join(hashtags(s)),
    ]
    return "\n".join(lines)


def hashtags(s):
    first = "#Shorts" if s.get("orientation", "vertical") == "vertical" else "#Gaming"
    second = "#CityDestruction" if s.get("mode") == "destroy" else "#PoliceChase"
    return [first, second, "#IndieGame"]


def tags(s):
    out = list(TAGS)
    if s.get("mode") == "destroy":
        out.insert(0, "city destruction")
    if s.get("orientation", "vertical") == "vertical":
        out.append("shorts")
    return ", ".join(out)


def pinned_comment(s):
    if s.get("mode") == "destroy":
        return "How many runs until the bot destroys 100% of the city? Guess below 👇"
    return "Would you have escaped? What should the bot try next? 👇"


def build(s):
    parts = ["TITLE (pick one, max 100 characters)"]
    parts += [f"{i + 1}. {t}" for i, t in enumerate(titles(s))]
    parts += ["", "DESCRIPTION", description(s), "",
              "TAGS (paste into the Tags box under Show more)", tags(s), "",
              "PINNED COMMENT", pinned_comment(s), "",
              "BEFORE YOU UPLOAD",
              "- Replace [add your Play Store link here] with your real link, or delete that line.",
              "- Add music from the YouTube app's library, keep the game sound low under it.",
              "- Thumbnail: use the -thumbnail.jpg next to the video (for long videos; Shorts pick a frame)."]
    return "\n".join(parts) + "\n"


def main(args):
    with open(args[0]) as f:
        s = json.load(f)
    text = build(s)
    if len(args) > 1:
        with open(args[1], "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
