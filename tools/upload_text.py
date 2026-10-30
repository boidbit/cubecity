#!/usr/bin/env python3
"""Writes ready-to-paste YouTube text (titles, description, tags, hashtags, pinned
comment) for one recorded run, using that run's real numbers.

Usage: tools/upload_text.py summary.json [out.txt]   (prints to stdout without out.txt)
"""
import json
import sys

# what each logged event looks like in a description, in the order they are listed
MOMENTS = [
    ("heli_down", "a helicopter takedown"),
    ("mega_jump", "a tower-top to tower-top jump"),
    ("trap", "the barrel trap that blows up the police"),
    ("collapse", "buildings coming down"),
    ("gas", "a gas station explosion"),
    ("chain", "chain explosions"),
    ("near_miss", "near misses"),
    ("big_air", "ramp jumps"),
    ("roadblock", "a police roadblock"),
    ("swat", "the SWAT truck"),
    ("heli", "the police helicopter"),
    ("broke_free", "a close call with the BUSTED meter"),
]

TAGS = ["police chase", "car chase", "ai gameplay", "destruction game", "indie game",
        "mobile game", "godot", "godot engine", "voxel destruction", "satisfying destruction",
        "wanted level", "cube city chase"]
MODE_TAGS = {
    "destroy": ["city destruction"],
    "heli": ["helicopter", "police helicopter"],
    "rush": ["traffic", "near miss", "rush hour"],
    "stunt": ["car stunts", "ramp jump", "jump"],
}

HOOKS = {
    "chase": "One car, a growing pack of police, and no way out. Can it escape?",
    "destroy": "One car tries to smash the whole city. How much can it destroy before the police shut it down?",
    "survive": "Five stars from the first second. Can one car stay ahead of the whole police force?",
    "heli": "A police helicopter is chasing one car through the city. Can the car get away, or take it down?",
    "rush": "Rush hour. Cars from every direction, police closing in, and one car threading through. How close can it get?",
    "stunt": "Ramps, jumps, explosions and falling towers: the stunt show.",
}


def titles(s):
    mode = s.get("mode", "chase")
    dur = int(round(float(s.get("duration", 55))))
    cops = max(int(s.get("max_cops", 0)), int(s.get("cops_wrecked", 0)))
    wrecked = int(s.get("cops_wrecked", 0))
    falls = int(s.get("collapses", 0))
    misses = int(s.get("near_miss", 0))
    jumps = int(s.get("big_air", 0))
    events = {e.get("type") for e in s.get("events", [])}
    if mode == "destroy":
        out = ["Can One Car Destroy the Whole City? 🏙️💥",
               f"One Car vs The City: {falls} Buildings Down 💥" if falls >= 2 else "One Car vs The City: Smashing Everything 💥",
               "This Car Drives Straight Through Buildings 😳"]
    elif mode == "survive":
        out = [f"Can One Car Survive 5 Stars for {dur} Seconds? 🚨",
               f"{cops} Cops vs 1 Car: Max Wanted Level 🚓",
               f"5 Star Police Chase: {wrecked} Cops Wrecked 💥" if wrecked >= 3 else "5 Star Police Chase, No Escape? 🚨"]
    elif mode == "heli":
        down = "heli_down" in events
        out = ["Can a Car Take Down a Police Helicopter? 🚁💥" if down else "Police Helicopter vs One Car 🚁",
               "The Car Jumped Right Into the Helicopter 😳" if down else "Police Helicopter Chase Through the City 🚨",
               f"1 Car vs {cops} Cops and a Helicopter 🚓🚁"]
    elif mode == "rush":
        out = [f"{misses} Near Misses in {dur} Seconds 😳🚗" if misses >= 3 else "Rush Hour Chaos: Cars From Every Direction 🚗💥",
               "Can One Car Escape Rush Hour and the Cops? 🚨",
               "Cars From Every Direction. One Narrow Escape 😳"]
    elif mode == "stunt":
        out = ["Craziest Car Stunts in a City of Cubes 🚗💥",
               "Jumping From Tower to Tower 😳" if "mega_jump" in events else "Ramps, Jumps and Explosions 💥",
               f"{jumps} Insane Jumps in {dur} Seconds 🚗" if jumps >= 3 else "One Car. One Stunt Show. 🚗"]
    else:
        out = [f"1 Car vs {cops} Cops 🚓 Can It Escape?",
               f"{wrecked} Cops Wrecked in {dur} Seconds 💥" if wrecked >= 3 else "Police Chase Through a City of Cubes 🚨",
               "This Car Led the Cops Into a Trap 😳" if "trap" in events else "Can One Car Outrun the Whole Police Force? 🚨"]
    return [t[:100] for t in out]


def description(s):
    mode = s.get("mode", "chase")
    events = {e.get("type") for e in s.get("events", [])}
    seen = [text for kind, text in MOMENTS if kind in events]
    lines = [HOOKS.get(mode, HOOKS["chase"]), ""]
    lines.append(f"🚓 Police in the chase: {s.get('max_cops', 0)}")
    lines.append(f"💥 Police cars wrecked: {s.get('cops_wrecked', 0)}")
    if s.get("collapses"):
        lines.append(f"🏢 Buildings brought down: {s['collapses']}")
    if s.get("near_miss"):
        lines.append(f"😳 Near misses: {s['near_miss']}")
    if mode == "destroy":
        lines.append(f"🏙️ City destroyed: {float(s.get('destroyed_pct', 0)):.2f}%")
    if seen:
        if len(seen) > 1:
            lines.append("👀 Watch for " + ", ".join(seen[:-1]) + " and " + seen[-1] + ".")
        else:
            lines.append("👀 Watch for " + seen[0] + ".")
    lines += [
        "",
        "AI-driven gameplay from Cube City Chase, a car chase and destruction game I'm making "
        "with the Godot engine. Everything in it (the city, cars, explosions and sounds) is generated in code.",
        "",
        "🎮 Play the game: [add your Play Store link here]",
        "🔔 Subscribe for more runs. Which mode next: chase, destroy, survive, helicopter, rush hour or stunts? Tell me in the comments!",
        "",
        " ".join(hashtags(s)),
    ]
    return "\n".join(lines)


def hashtags(s):
    first = "#Shorts" if s.get("orientation", "vertical") == "vertical" else "#Gaming"
    second = {"destroy": "#CityDestruction", "heli": "#Helicopter", "rush": "#CarChase", "stunt": "#Stunts"}.get(
        s.get("mode"), "#PoliceChase")
    return [first, second, "#IndieGame"]


def tags(s):
    out = list(TAGS)
    out[0:0] = MODE_TAGS.get(s.get("mode"), [])
    if s.get("orientation", "vertical") == "vertical":
        out.append("shorts")
    return ", ".join(out)


def pinned_comment(s):
    return {
        "destroy": "How many runs until it destroys 100% of the city? Guess below 👇",
        "heli": "Would you try that jump? 👇",
        "rush": "How many near misses did you count? 👇",
        "stunt": "Which stunt was the craziest? 👇",
    }.get(s.get("mode"), "Would you have escaped? What should happen next? 👇")


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
