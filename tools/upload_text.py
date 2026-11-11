#!/usr/bin/env python3
"""Writes ready-to-paste YouTube text (titles, description, tags, hashtags, pinned
comment) for one recorded run, using that run's real numbers.

Usage: tools/upload_text.py summary.json [out.txt]   (prints to stdout without out.txt)
"""
import json
import sys

# what each logged event looks like in a description, in the order they are listed
MOMENTS = [
    ("train_hit", "a train taking out a police car"),
    ("safehouse", "a last-second escape into the safehouse"),
    ("emp", "an EMP that kills every police car around"),
    ("spike_cop", "police driving over their own spike strip"),
    ("oil_spin", "an oil slick"),
    ("spray", "a respray that shakes the police off"),
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
    "escape": ["police escape", "train crossing", "getaway"],
    "destroy": ["city destruction"],
    "heli": ["helicopter", "police helicopter"],
    "rush": ["traffic", "near miss", "rush hour"],
    "stunt": ["car stunts", "ramp jump", "jump"],
    "race": ["car vs train", "train race", "car racing"],
    "swarm": ["police chase", "40 cops", "chase", "near miss"],
}

HOOKS = {
    "escape": "Spike strips, a train, an EMP and one safehouse. Can he make it before they catch him?",
    "chase": "One car, a growing pack of police, and no way out. Can it escape?",
    "destroy": "One car tries to smash the whole city. How much can it destroy before the police shut it down?",
    "survive": "Five stars from the first second. Can one car stay ahead of the whole police force?",
    "heli": "A police helicopter is chasing one car through the city. Can the car get away, or take it down?",
    "rush": "Rush hour. Cars from every direction, police closing in, and one car threading through. How close can it get?",
    "stunt": "Ramps, jumps, explosions and falling towers: the stunt show.",
    "race": "A car races a train across the city. One ramp, one finish line—who gets there first?",
    "swarm": "Thirty, forty police cars. From behind, from the side streets, head-on. One car threads through, and sometimes it does not get away clean.",
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
    if mode == "race":
        winner = str(s.get("race_winner") or "")
        margin = float(s.get("race_margin", -1.0))
        changes = int(s.get("race_lead_changes", 0))
        who = "Car" if winner == "car" else "Train"
        loser = "Train" if winner == "car" else "Car"
        if winner and 0.0 <= margin < 0.6:
            out = [f"Photo Finish! The {who} Won by {margin:.2f} Seconds 🏁",
                   "Car vs Train: Decided by a Hair 🚗🚂",
                   "One Ramp. One Finish Line. Too Close to Call."]
        elif winner and margin >= 0.0:
            out = [f"The {who} Beat the {loser} by {margin:.2f} Seconds 🏁",
                   f"It Changed Hands {changes} Time{'s' if changes != 1 else ''}: Car vs Train 🚗🚂" if changes else "Can a Car Beat a Train to the Finish? 🚗🚂",
                   "One Ramp. One Finish Line. Car vs Train."]
        else:
            out = ["Car vs Train: Who Reaches the Finish First? 🏁",
                   "A Train Race Through Cube City 🚂🚗",
                   "One Ramp. One Finish Line. Car vs Train."]
    elif mode == "escape":
        trains = int(s.get("train_hits", 0))
        out = ["Can He Escape? The Train Didn't Stop 🚂🚓" if trains else "Can He Escape the Whole Police Force? 🚓💨",
               "He Made It to the Safehouse... Barely 😳" if s.get("safehouse") else f"{cops} Cops, 1 Car, No Way Out 🚨",
               f"Spike Strips, EMP and {wrecked} Cops Wrecked 💥" if wrecked >= 2 else "The Police Hit Their Own Spikes 😂"]
    elif mode == "destroy":
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
    elif mode == "swarm":
        hits = int(s.get("player_hits", 0))
        out = [f"{cops} Cops vs 1 Car: Every Direction 🚔😳",
               f"{misses} Near Misses With {cops} Police Cars on His Tail 🚨" if misses >= 3 else "40 Police Cars. One Car. No Way Out? 🚨",
               f"He Took {hits} Hits and Kept Driving 💥" if hits >= 2 else "Police From Every Side. Somehow He Made It 😳"]
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
    if mode == "race":
        winner = str(s.get("race_winner") or "undecided").upper()
        lines.append(f"🏁 Winner: {winner}")
        car_time = float(s.get("race_car_time", -1.0))
        train_time = float(s.get("race_train_time", -1.0))
        if car_time >= 0.0:
            lines.append(f"🚗 Car finish: {car_time:.2f} seconds")
        if train_time >= 0.0:
            lines.append(f"🚂 Train finish: {train_time:.2f} seconds")
        if int(s.get("race_lead_changes", 0)):
            lines.append(f"🔁 Lead changes: {int(s['race_lead_changes'])}")
    else:
        lines.append(f"🚓 Police in the chase: {s.get('max_cops', 0)}")
        lines.append(f"💥 Police cars wrecked: {s.get('cops_wrecked', 0)}")
    if mode != "race" and s.get("collapses"):
        lines.append(f"🏢 Buildings brought down: {s['collapses']}")
    if mode != "race" and s.get("near_miss"):
        lines.append(f"😳 Near misses: {s['near_miss']}")
    if mode == "destroy" and s.get("cubes"):
        lines.append(f"🏙️ Cubes smashed: {int(s['cubes']):,}")
    if seen:
        if len(seen) > 1:
            lines.append("👀 Watch for " + ", ".join(seen[:-1]) + " and " + seen[-1] + ".")
        else:
            lines.append("👀 Watch for " + seen[0] + ".")
    lines += [
        "",
        "AI-driven gameplay from Cube City Chase, a car chase, racing and destruction game I'm making "
        "with the Godot engine. Everything in it (the city, cars, explosions and sounds) is generated in code.",
        "",
        "🎮 Play the game: [add your Play Store link here]",
        "🔔 Subscribe for more runs. Which mode next: chase, escape, race, destroy, survive, helicopter, rush hour or stunts? Tell me in the comments!",
        "",
        " ".join(hashtags(s)),
    ]
    return "\n".join(lines)


def hashtags(s):
    first = "#Shorts" if s.get("orientation", "vertical") == "vertical" else "#Gaming"
    second = {"destroy": "#CityDestruction", "heli": "#Helicopter", "rush": "#CarChase", "stunt": "#Stunts", "escape": "#Escape", "race": "#CarVsTrain", "swarm": "#PoliceChase"}.get(
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
        "escape": "Train, EMP or the spray shop: what saved him? 👇",
        "destroy": "How many runs until it destroys 100% of the city? Guess below 👇",
        "heli": "Would you try that jump? 👇",
        "rush": "How many near misses did you count? 👇",
        "stunt": "Which stunt was the craziest? 👇",
        "race": "Could the car beat the train? What should race next? 👇",
        "swarm": "How many close calls did you count? 👇",
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
