#!/usr/bin/env python3
"""Story lab: ready-to-paste upload text (titles, description, tags, hashtags) for a story video.

Usage: tools/story/text.py timed.json [out.txt]   (prints to stdout without out.txt)
"""
import json
import sys


def build(sp):
    cast = sp.get("cast", {})
    names = [c.get("name", k).title() for k, c in cast.items()]
    couple = " & ".join(names) if names else sp.get("title", "Story")
    ep = sp.get("episode", "")
    lines = sp.get("lines", [])
    hook = lines[0].get("sub", "") if lines else ""
    last = lines[-1].get("sub", "") if lines else ""
    out = []
    out.append("TITLES (pick one)")
    out.append(f"1. {couple}: {ep.split(':')[-1].strip().title() or 'Episode 1'} 😂🚓")
    out.append(f"2. Date Night With the Police Behind Us 🍕🚓 | {couple}")
    out.append(f"3. {couple} Cringe Couple Car Chase 😭💕 #shorts")
    out.append("")
    out.append("DESCRIPTION")
    out.append(f"{couple} are on a date night. The police have other plans. 🚓💕")
    out.append("")
    if hook:
        out.append(f'"{hook}"')
        out.append("")
    out.append("A cute, cringe couple story told inside a real police chase: ramps, near misses and explosions.")
    out.append("Follow for the next part!")
    out.append("")
    out.append("Made with a game I am building in Godot. The voices are AI-generated.")
    out.append("")
    out.append("#shorts #couplegoals #cringe #funny #carchase #gaming #hindi #lovestory")
    out.append("")
    out.append("TAGS")
    out.append("cringe couple, couple goals, funny couple, hindi comedy, love story, car chase, police chase, "
               "cartoon couple, date night, babu shona, indie game, godot")
    out.append("")
    out.append("PINNED COMMENT")
    out.append("Which line was the most cringe? 😂 Comment it and I will use it in part 2!")
    out.append("")
    out.append("BEFORE YOU PUBLISH")
    out.append("- YouTube Studio > Details > 'Altered content': answer YES (the voices are synthetic)")
    out.append(f"- Last line of this episode, for the thumbnail text if you want one: {last}")
    return "\n".join(out) + "\n"


def main(argv):
    if not argv:
        sys.exit(__doc__)
    with open(argv[0], encoding="utf-8") as f:
        sp = json.load(f)
    text = build(sp)
    if len(argv) > 1:
        with open(argv[1], "w", encoding="utf-8") as f:
            f.write(text)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
