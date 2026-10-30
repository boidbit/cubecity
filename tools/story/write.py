#!/usr/bin/env python3
"""Story lab: Gemini writes a new episode as a screenplay the game can play.

The model is told exactly what the game can do (lines, emotions, police, a jump, props,
endings) and must answer in JSON. The answer is checked and cleaned up (unknown actions
dropped, lengths limited, one ending, ids added). If it is still not usable, or there is
no key, the saved episode in --base is used instead, so the workflow always has a story.

Usage: tools/story/write.py --out story-out/screenplay.json [--type funny] [--idea "..."]
                            [--language hinglish] [--base story/screenplays/ep1_date_night.json]
"""
import argparse
import copy
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gemini  # noqa: E402

EMOTIONS = ["neutral", "smug", "love", "shock", "angry", "sad", "happy", "laugh"]
GESTURES = ["talk", "up", "point", "wave", "idle"]
ACTIONS = ["police", "calm", "heli", "heli_off", "jump", "roadblock", "crossers", "boom",
           "prop_show", "prop_fly", "prop_hide", "slowmo", "stop", "go",
           "park", "exit_car", "enter_car", "walk", "run", "sit", "stand", "kneel", "fall", "hug",
           "dance", "cheer", "hold", "give",
           "arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "look", "appear", "shot"]
FOOT = ["walk", "run", "sit", "stand", "kneel", "fall", "hug", "dance", "cheer"]
SPOTS = ["bench", "icecream", "chai"]       # sets put up where the car parks (park "at")
STALLS = ["icecream", "chai"]               # these come with a vendor who can speak
CAR_ONLY = ["police", "jump", "roadblock", "crossers", "boom", "prop_fly"]   # need the car to be driving
EVENTS = ["takeoff", "big_air", "prop_fly", "near_miss", "cop_wrecked", "roadblock",
          "parked", "exited", "arrived", "seated", "car_arrived", "grabbed", "fled", "cornered", "won"]
WAIT_FOR = ["parked", "exited", "arrived", "seated", "car_arrived", "grabbed", "fled", "cornered", "won"]
SHOTS = ["zoom", "pov", "wide"]
# side characters: looks the game can build, and Gemini voices by gender
STYLES = ["boy", "girl", "man", "woman", "oldman", "oldwoman", "kid"]
HAIR_STYLES = ["short", "long", "bald", "spiky", "bun", "ponytail"]
BUILDS = ["slim", "normal", "big"]
ACCESSORIES = ["cap", "hat", "glasses", "sunglasses", "mustache", "beard", "mask", "tie", "scarf", "bindi"]
MALE_VOICES = ["Algenib", "Charon", "Fenrir", "Orus", "Achird", "Iapetus", "Umbriel", "Rasalgethi", "Alnilam",
               "Schedar", "Sadachbia", "Sadaltager", "Zubenelgenubi", "Enceladus", "Algieba"]
FEMALE_VOICES = ["Kore", "Aoede", "Callirrhoe", "Autonoe", "Despina", "Erinome", "Laomedeia", "Achernar",
                 "Gacrux", "Pulcherrima", "Vindemiatrix", "Sulafat", "Zephyr"]
RESERVED = {"babu", "shona", "police", "vendor", "both", "all"}
TEMPLATES = {"kidnap_rescue": "kidnap & rescue (villains in the van, a chase, a fight)",
             "jealous_reveal": "jealous reveal (a misunderstanding on foot, a twist, they make up)",
             "date": "a date at a place (bench, ice cream or chai)",
             "proposal": "a proposal out of the car"}
MAX_SIDE = 3
CAR_COLORS = {"van": "#26262b"}
PLACES = ["ahead", "back", "car", "other", "spot"]
ENDINGS = ["happy", "caught", "crash", "cliffhanger"]
PROPS = ["pizza", "flowers", "gift", "ring", "teddy", "icecream", "chai"]
VENDOR = {"name": "BHAIYA", "color": "#f0a020",
          "voice": {"gemini": "Fenrir", "edge": "hi-IN-MadhurNeural", "rate": "+12%", "pitch": "-6Hz",
                    "espeak_pitch": 40, "style": "a cheerful, chatty Indian street vendor"},
          "look": {"style": "boy", "skin": "#c98b5e", "hair": "#1d1714", "shirt": "#f3efe4"}}
TIMES = ["day", "dusk", "night"]
MOOD_ENDING = {"happy": "happy", "romantic": "happy", "funny": "happy", "cringe": "happy",
               "sad": "crash", "action": "caught", "twist": "cliffhanger", "drama": "happy"}
MOOD_TIME = {"sad": "night", "romantic": "dusk", "happy": "day", "action": "dusk"}

SYSTEM = """You write episodes of a short animated comedy-drama series for YouTube Shorts and Instagram Reels.
The show is made in a blocky 3D city game (everything is cubes, like Minecraft or Roblox).

THE SET-UP (fixed, the game cannot do anything else):
- Two main characters start in a pink open-top car: "babu" (boy) drives, "shona" (girl) sits next to him.
- The car drives through the city while they talk. They can also pull over and get out for a scene on the
  pavement (a proposal, a fight, a sulk, a race on foot), then get back in and drive on, or end the episode there.
- Police cars, a police helicopter, roadblocks and traffic exist, but they are SIDE characters: bring them in only
  when your story needs them. A quiet story with no police at all is fine.
- "police" can also speak (over a megaphone), at most 2 short lines.
- When they stop at an ice-cream cart or a chai stall, its "vendor" (a street vendor, "Bhaiya") can speak too,
  at most 3 short lines: funny, chatty, he comments on the couple.

WHAT A SCREENPLAY CAN CONTAIN ("beats", played in order):
1. A line: {"say": "babu"|"shona"|"police"|"vendor", "emotion": E, "react": E, "gesture": G, "sub": "...", "tts": "..."}
   - emotion = how the speaker looks, react = how the other one looks while listening.
   - E is one of: neutral, smug, love, shock, angry, sad, happy, laugh.  G is one of: talk, up, point, wave, idle.
   - Optional "on": wait for a moment in the action before saying the line: takeoff (the car leaves a ramp,
     perfect for a scream), big_air (the car lands), prop_fly, near_miss, cop_wrecked, roadblock.
2. An action: {"do": A} where A is one of:
   police (add "stars": 1-3, police start chasing them), calm (the police give up and leave),
   heli / heli_off (police helicopter), jump (a ramp appears on the road and the car jumps it),
   roadblock (police block the road ahead), crossers (two cars cut across just in front: a near miss),
   boom (barrels explode behind the car and knock out the police), slowmo (2 seconds of slow motion),
   prop_show / prop_fly / prop_hide (add "prop": P; prop_fly throws it out of the car, best right after a jump),
   stop / go (the car stops / drives on).
   OUT OF THE CAR (W = "babu", "shona" or "both"):
   park (the car pulls over at the kerb; the street goes quiet and the police leave). Add "at": S to stop at a place:
     "bench" (a park bench: sit puts them on it), "icecream" (an ice-cream cart with its vendor),
     "chai" (a roadside chai stall with its vendor). Out of the car they walk straight to it.
   exit_car (add "who": W; they get out and stand on the pavement facing each other),
   walk / run (add "who": W, "to": "ahead" | "back" | "car" | "other" (to the other character) | "spot" (back to
   the bench or stall), "dist": 3-15 metres),
   sit (on the bench if there is one, else on the pavement), stand (get up again), kneel (one knee down,
   proposal style), fall (falls flat on the ground: comedy), hug (the two hug), dance, cheer (jumps for joy),
   each with "who": W,
   enter_car (add "who": W; back into their seats), then go to drive on.
   The order is: park, exit_car, the scene on foot, then either enter_car + go or the ending.
   Car actions (police, jump, roadblock, crossers, boom, prop_fly) only work while they are driving.
   SIDE CHARACTERS ("cast", optional, at most 3; ids are short lowercase words like "rahul", "goon1", "papa"):
     "cast": {"rahul": {"name": "RAHUL", "gender": "male", "role": "Shona's cousin, nerdy and loud",
                        "look": {"style": S, "skin": "#c98b5e", "hair": "#2b1d16", "shirt": "#f2f2f2", "pants": "#3a4a6a",
                                 "hair_style": H, "build": B, "acc": [A, ...]},
                        "start": {"at": "ahead" | "back" | "near:<id>", "dist": metres} or {"car": "van"}}}
     S: boy, girl, man, woman, oldman, oldwoman, kid. H: short, long, bald, spiky, bun, ponytail. B: slim, normal, big.
     A (up to 3): cap, hat, glasses, sunglasses, mustache, beard, mask, tie, scarf, bindi. Villains look good "big", in
     dark clothes with a mask or sunglasses. They speak with "say": "<id>" (at most 4 lines each) and take "who": "<id>".
   START OUT OF THE CAR: "start_on_foot": true (optional "start_spot": bench | icecream | chai) starts the episode on the
     pavement; give babu / shona a "start" in "cast" too: {"at": "ahead" | "back" | "spot" | "car", "dist": metres}
     (e.g. babu 20 m "back" walking up, shona "ahead" with somebody).
   ACTION (the villains' van is the only other car; people start inside it with "start": {"car": "van"}):
     arrive (the van drives up and stops by "to": who), exit_car / enter_car with "who": "id1,id2" and "car": "van",
     grab ("who": a side character carries "to": who off over his shoulder), drive_off (the van speeds away),
     chase (the leads' car chases the van; police, jump and boom work during the chase), corner (the van is cut off
     and stops; the chasing car stops behind it), fight ("who" takes on "to": "id1,id2" one after the other: DHISHUM!
     punches, they end up knocked out), punch ("who", "to", "ko": true), look ("who" stares at "to"),
     appear ("who" walks on: "at": ahead | back | near:<id>, "dist").
   DRAMA SHOTS: {"do": "shot", "type": "zoom", "who": id} (a push-in on a shocked face with a "dun dun DUNNN"),
     "pov" ("who" looking at "to", over the shoulder), "wide". Use them at the big moments, 1-3 per episode.
     Events for "on" / "wait_for": car_arrived, grabbed, fled, cornered, won.
   IN THE HAND (in the car or on foot): hold (add "who": "babu" | "shona", "prop": P: they hold it in their hand;
   food gets eaten), give (add "who": the giver, "to": "babu" | "shona" | "both", optional "prop": P: hands it
   over; the vendor gives what he sells, e.g. {"do": "give", "who": "vendor", "to": "both"}).
3. {"wait": seconds} (at most 3), or {"wait_for": "exited" | "arrived" | "seated"}: wait until they are out of the
   car / have reached where they walked or ran to / are back in their seats. A line can wait with "on": "parked".
4. Exactly one ending: {"end": "happy" | "caught" | "crash" | "cliffhanger"}
   happy = the police leave, the car stops, sunset and hearts; caught = police surround the stopped car;
   crash = the car spins out and stops with smoke (sad); cliffhanger = everything freezes in slow motion.
   If they are out of the car at the end, use happy (a slow closing shot of the two of them) or cliffhanger.

RECIPES (use one when the idea or the template fits; fill in the dialogue and the twist yourself):
- kidnap & rescue: start_on_foot at a stall -> the van arrives -> goons get out -> grab -> enter_car van -> drive_off ->
  zoom on the hero -> babu gets in, chase (a jump, a near miss) -> the victim screams from the van -> corner -> fight
  -> the victim gets out of the van -> hug -> a funny last line.
- jealous reveal: start_on_foot, the hero 20 m "back" holding flowers, the partner "ahead" walking with somebody new ->
  zoom on the hero -> pov -> the hero runs up angry -> the twist (cousin, brother, teacher ...) -> they make up.
- date / proposal / fight-and-patch-up: drive and talk, park at a place, the scene on foot, a sweet or funny ending.
   Put 1-3 lines AFTER the ending: they are the last words.
Props (P): pizza, flowers, gift, ring, teddy, icecream, chai. List the ones in the car at the start in "props".

WRITING RULES:
- 9 to 16 lines in total, each line at most 12 words. Talky episodes last about 40 seconds, action ones about 60.
- A real story: the first line is a hook (a problem, a promise or a question), then trouble that grows,
  a twist, a payoff that fits the mood, and a last line that is a punchline or an emotional moment.
- Show, do not explain the game: never talk about "the game", "bots", "ramps appearing" or "levels".
- Every action you use must matter to the story, and the lines around it must react to it.
- At most one scene out of the car, and only when the story is better for it (getting out takes a few seconds).
  A scene out of the car works best at a place (bench, icecream, chai).
- Keep it PG: cute, cringe, funny or emotional. No real people, brands or places, no hate, no real violence.
- The voice actor only gets the words, so put the feeling into them: exclamations, "arre", "uff", "haha",
  "hmm...", question marks and pauses ("...") where they belong.

LANGUAGE:
- hinglish: "sub" is natural Roman-script Hinglish like Instagram captions; "tts" is the SAME line written in
  Devanagari so a Hindi voice reads it well (English words written as they sound).
- hindi: "sub" is simple Hindi in Roman script; "tts" the same in Devanagari.
- english: "sub" and "tts" are both English.

ANSWER with one JSON object only:
{"title": "BABU & SHONA", "episode": "the episode's own title, 2-4 words, no number", "end_text": "teaser for next part, max 4 words",
 "names": {"babu": "BABU", "shona": "SHONA"}, "time": "day|dusk|night", "props": ["pizza"],
 "cast": { optional side characters }, "start_on_foot": false,
 "beats": [ ... ],
 "upload": {"titles": ["3 catchy titles, max 60 chars, 1-2 emojis"], "description": "2 short lines",
            "hashtags": ["#shorts", "..."]}}
Keep "names" as BABU and SHONA unless the idea asks for other names (then put the new names there, in capitals)."""


def clip(text, n):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text[:n].rstrip()


def side_cast(ai_cast, problems):
    """Side characters from the model's "cast": checked looks, a voice each. {id: cast entry}."""
    out = {}
    if not isinstance(ai_cast, dict):
        return out
    hexcol = re.compile(r"^#[0-9a-fA-F]{6}$")
    used = set()
    for raw_id, c in ai_cast.items():
        cid = re.sub(r"[^a-z0-9_]", "", str(raw_id).lower())[:12]
        if not cid or cid in RESERVED or not isinstance(c, dict):
            continue
        if len(out) >= MAX_SIDE:
            problems.append("too many side characters")
            break
        look_in = c.get("look") if isinstance(c.get("look"), dict) else {}
        style = look_in.get("style") if look_in.get("style") in STYLES else ("girl" if c.get("gender") == "female" else "boy")
        female = style in ("girl", "woman", "oldwoman")
        look = {"style": style}
        for k in ("skin", "hair", "shirt", "pants"):
            if isinstance(look_in.get(k), str) and hexcol.match(look_in[k]):
                look[k] = look_in[k]
        if look_in.get("hair_style") in HAIR_STYLES:
            look["hair_style"] = look_in["hair_style"]
        if look_in.get("build") in BUILDS:
            look["build"] = look_in["build"]
        acc = [a for a in (look_in.get("acc") or []) if a in ACCESSORIES][:3]
        if acc:
            look["acc"] = acc
        pool = FEMALE_VOICES if female else MALE_VOICES
        voice = c.get("voice") if isinstance(c.get("voice"), str) and c.get("voice") in pool else None
        voice = voice or next((v for v in pool if v not in used), pool[0])
        used.add(voice)
        n = len(out)
        entry = {"name": clip(c.get("name") or cid, 14).upper(), "color": ["#22aa66", "#aa6622", "#6622aa"][n % 3],
                 "look": look,
                 "voice": {"gemini": voice, "edge": "hi-IN-SwaraNeural" if female else "hi-IN-MadhurNeural",
                           "rate": ["+10%", "+0%", "+16%"][n % 3], "pitch": ["-8Hz", "+6Hz", "-3Hz"][n % 3],
                           "espeak_pitch": 70 if female else 35, "style": clip(c.get("role", ""), 60)}}
        st = c.get("start") if isinstance(c.get("start"), dict) else {}
        if st.get("car") in CAR_COLORS:
            entry["start"] = {"car": st["car"]}
        elif isinstance(st.get("at"), str) and (st["at"] in ("ahead", "back") or st["at"].startswith("near:")):
            entry["start"] = {"at": st["at"], "dist": max(3.0, min(30.0, float(st.get("dist", 8) or 8)))}
        out[cid] = entry
    return out


class Stage:
    """Keeps the actions in an order the game can play: the car parks before anyone gets out,
    everyone gets back in before it drives on, and car actions are dropped while it is parked.
    The waits for getting out and back in are added here, so the writer does not have to."""

    def __init__(self, beats, problems):
        self.beats, self.problems = beats, problems
        self.parked = False     # parked (the car stays put until "go")
        self.stop_at = -1       # a plain "stop" that becomes a park if they get out
        self.out = set()        # who is on foot
        self.walking = False    # a walk or run that a wait_for "arrived" can wait for
        self.spot = ""          # the place they parked at
        self.side = set()       # side characters' ids
        self.in_van = set()     # who is inside the van
        self.side_out = set()   # side characters standing in the scene
        self.carried = {}       # carrier -> victim
        self.cars = set()       # story cars used
        self.van_gone = False   # the van has driven off
        self.chasing = False

    def wait(self, ev, max_wait):
        if not (self.beats and self.beats[-1].get("wait_for") == ev):
            self.beats.append({"wait_for": ev, "max_wait": max_wait})

    def park(self, at=""):
        if self.parked:
            return
        d = {"do": "park"}
        if at in SPOTS:
            d["at"] = at
            self.spot = at
        if self.stop_at >= 0:
            self.beats[self.stop_at] = d
        else:
            self.beats.append(d)
        self.parked = True

    def get_out(self, names):
        need = names - self.out
        if need:
            self.park()
            self.beats.append({"do": "exit_car", "who": "both" if len(need) == 2 else min(need)})
            self.wait("exited", 25)
            self.out |= need

    def get_in(self, names):
        names = names & self.out
        if names:
            self.beats.append({"do": "enter_car", "who": "both" if len(names) == 2 else min(names)})
            self.wait("seated", 20)
            self.out -= names

    def names(self, who):
        if who == "both":
            return {"babu", "shona"}
        return {w.strip() for w in str(who).split(",") if w.strip() in self.side | {"babu", "shona", "vendor"}}

    def side_out_of_van(self, names):
        need = [k for k in names if k in self.in_van]
        if need:
            self.beats.append({"do": "exit_car", "who": ",".join(sorted(need))})
            self.wait("exited", 6)
            self.in_van -= set(need)
            self.side_out |= set(need) - {"babu", "shona"}
            self.out |= set(need) & {"babu", "shona"}      # a kidnapped lead is back on her feet

    def action(self, d):
        """The kidnap / chase / fight vocabulary. Returns True when handled."""
        act = d["do"]
        who, to = d.get("who", ""), d.get("to", "")
        if act == "arrive":
            if self.chasing:
                return True
            self.park()
            self.cars.add("van")
            self.beats.append({"do": "arrive", "car": "van", "to": to if to in self.names(to) else "shona"})
            self.wait("car_arrived", 14)
        elif act == "exit_car" and (self.names(who) & (self.in_van | {k for k in self.carried.values()})):
            names = self.names(who) & self.in_van
            self.side_out_of_van(names)
        elif act == "enter_car" and d.get("car") == "van":
            names = self.names(who) & (self.side_out | self.side)
            if names:
                self.beats.append({"do": "enter_car", "who": ",".join(sorted(names)), "car": "van"})
                self.wait("seated", 10)
                self.side_out -= names
                self.in_van |= names
                for k in names:
                    if k in self.carried:
                        victim = self.carried.pop(k)
                        self.in_van.add(victim)
                        self.out.discard(victim)
        elif act == "grab":
            victim = to if to in ("babu", "shona") or to in self.side else "shona"
            grabber = who if who in self.side else next(iter(sorted(self.side)), "")
            if not grabber:
                self.problems.append("grab without a side character")
                return True
            self.side_out_of_van({grabber})
            if victim in ("babu", "shona"):
                self.get_out({victim})
            self.beats.append({"do": "grab", "who": grabber, "to": victim})
            self.wait("grabbed", 10)
            self.carried[grabber] = victim
        elif act == "drive_off":
            if "van" in self.cars and not self.van_gone:
                self.beats.append({"do": "drive_off", "car": "van"})
                self.van_gone = True
        elif act == "chase":
            if not self.van_gone:
                self.problems.append("chase before the van drove off")
                return True
            # whoever is still on the pavement (and not kidnapped) jumps in
            self.get_in(set(self.out) - set(self.carried.values()) - self.in_van)
            self.beats.append({"do": "chase", "car": "van"})
            self.parked, self.stop_at, self.chasing = False, -1, True
        elif act == "corner":
            if self.chasing:
                self.beats.append({"do": "corner", "car": "van"})
                self.wait("cornered", 30)
                self.chasing, self.parked = False, True
        elif act in ("fight", "punch"):
            hero = who if who in ("babu", "shona") or who in self.side else "babu"
            targets = self.names(to) - {hero}
            if not targets:
                return True
            if hero in ("babu", "shona"):
                self.get_out({hero})
            else:
                self.side_out_of_van({hero})
            self.side_out_of_van(targets)
            for v in targets & {"babu", "shona"}:
                self.get_out({v})
            dd = {"do": act, "who": hero, "to": ",".join(sorted(targets))}
            if act == "punch" and d.get("ko"):
                dd["ko"] = True
            self.beats.append(dd)
            if act == "fight":
                self.wait("won", 25)
        elif act == "look":
            self.beats.append({"do": "look", "who": who, "to": to})
        elif act == "appear":
            if who in self.side:
                self.park()
                self.beats.append({"do": "appear", "who": who, "at": d.get("at", "ahead"), "dist": d.get("dist", 10)})
                self.side_out.add(who)
        elif act == "shot":
            self.beats.append({k: v for k, v in d.items() if k in ("do", "type", "who", "to", "dur")})
        else:
            return False
        return True

    def do(self, d):
        act = d["do"]
        if self.action(d):
            return
        names = {"babu", "shona"} if d.get("who", "both") == "both" or act == "hug" else self.names(d["who"])
        side_names = names & self.side
        names -= self.side
        if side_names and act in FOOT:
            self.side_out_of_van(side_names)
            self.beats.append(d)
            return
        if self.chasing and act in ("park", "stop", "go", "exit_car", "enter_car") + tuple(FOOT):
            self.problems.append(f"{act} during the chase")
            return
        if self.parked and act in CAR_ONLY:
            self.problems.append(f"{act} while the car is parked")
            return
        if d.get("who") == "vendor" and self.spot not in STALLS:
            self.problems.append(f"{act} by the vendor without a stall")
            return
        if act == "park":
            self.park(d.get("at", ""))
        elif act == "stop":
            if not self.parked and self.stop_at < 0:
                self.stop_at = len(self.beats)
                self.beats.append(d)
        elif act == "exit_car":
            self.get_out(names)
        elif act == "enter_car":
            self.get_in(names)
        elif act == "go":
            self.get_in(set(self.out) - self.in_van)
            self.parked, self.stop_at = False, -1
            self.beats.append(d)
        else:
            if act in FOOT:
                self.get_out(names)
                self.walking = self.walking or act in ("walk", "run")
            if act == "walk" or act == "run":
                if d.get("to") == "spot" and not self.spot:
                    d["to"] = "ahead"
            self.beats.append(d)

    def wait_for(self, ev):
        # the waits for getting out and in, the van and the fight are added where they belong;
        # "arrived" only after a walk or run
        if ev == "parked" and self.parked and not self.out:
            self.wait("parked", 22)
        elif ev == "arrived" and self.walking:
            self.wait("arrived", 12)
            self.walking = False


def ending_for(kind, stage):
    """A parked car does not spin out or get chased down: those endings become a quiet one or a freeze."""
    if stage.parked and kind in ("crash", "caught"):
        return "happy" if kind == "crash" else "cliffhanger"
    return kind


def clean(ai, base, mood):
    """A screenplay the game can play, built from the model's answer. Returns (screenplay, problems)."""
    sp = copy.deepcopy(base)
    problems = []
    names = ai.get("names") if isinstance(ai.get("names"), dict) else {}
    for k in ("babu", "shona"):
        if names.get(k):
            sp["cast"][k]["name"] = clip(names[k], 14).upper()
    sp["title"] = clip(ai.get("title") or f"{sp['cast']['babu']['name']} & {sp['cast']['shona']['name']}", 24).upper()
    sp["episode"] = clip(ai.get("episode") or "NEW EPISODE", 34).upper()
    sp["end_text"] = clip(ai.get("end_text") or "PART 2 JALDI...", 28).upper()
    sp["mood"] = mood
    sp["time"] = ai.get("time") if ai.get("time") in TIMES else MOOD_TIME.get(mood, "dusk")
    sp["props"] = [p for p in (ai.get("props") or []) if p in PROPS][:2]
    if isinstance(ai.get("upload"), dict):
        sp["upload"] = ai["upload"]
    else:
        sp.pop("upload", None)

    beats, says, police_says, vendor_says, endings, after_end = [], 0, 0, 0, 0, 0
    stage = Stage(beats, problems)
    # side characters, where everybody starts
    side = side_cast(ai.get("cast"), problems)
    sp["cast"].update(side)
    stage.side = set(side)
    for k, c in side.items():
        if c.get("start", {}).get("car") == "van":
            stage.in_van.add(k)
            stage.cars.add("van")
        elif "at" in c.get("start", {}):
            stage.side_out.add(k)
    if ai.get("start_on_foot"):
        sp["start_on_foot"] = True
        stage.parked = True
        stage.out = {"babu", "shona"}
        if ai.get("start_spot") in SPOTS:
            sp["start_spot"] = stage.spot = ai["start_spot"]
        ai_cast = ai.get("cast") if isinstance(ai.get("cast"), dict) else {}
        for k in ("babu", "shona"):
            st = ai_cast.get(k, {}).get("start") if isinstance(ai_cast.get(k), dict) else None
            if isinstance(st, dict) and (st.get("at") in ("ahead", "back", "spot", "car") or str(st.get("at", "")).startswith("near:")):
                sp["cast"][k]["start"] = {"at": st["at"], "dist": max(0.0, min(30.0, float(st.get("dist", 0) or 0)))}
    side_says = {}
    speakers = {"babu", "shona", "police", "vendor"} | set(side)
    for b in ai.get("beats") or []:
        if not isinstance(b, dict):
            continue
        if "say" in b:
            who = str(b.get("say", "")).lower()
            if who not in speakers:
                problems.append(f"unknown speaker {who!r}")
                continue
            if who in side:
                side_says[who] = side_says.get(who, 0) + 1
                if side_says[who] > 4:
                    continue
            if who == "vendor":
                vendor_says += 1
                if stage.spot not in STALLS or vendor_says > 3:
                    problems.append("the vendor speaks without a stall" if stage.spot not in STALLS else "too many vendor lines")
                    continue
                sp["cast"].setdefault("vendor", copy.deepcopy(VENDOR))
            if who == "police":
                police_says += 1
                if police_says > 3:
                    continue
            sub = clip(b.get("sub"), 110)
            if not sub:
                continue
            line = {"say": who, "sub": sub, "tts": clip(b.get("tts") or sub, 160),
                    "emotion": b.get("emotion") if b.get("emotion") in EMOTIONS else "neutral",
                    "react": b.get("react") if b.get("react") in EMOTIONS else "neutral"}
            if b.get("gesture") in GESTURES:
                line["gesture"] = b["gesture"]
            if b.get("on") in EVENTS:
                line["on"] = b["on"]
                line["max_wait"] = 20 if b["on"] in ("parked", "exited", "seated") else 9
            if len(sub.split()) > 16:
                problems.append(f"line too long: {sub!r}")
            says += 1
            if endings:
                after_end += 1
                if after_end > 3:
                    continue
            beats.append(line)
        elif "do" in b:
            act = str(b.get("do", "")).lower()
            if act not in ACTIONS:
                problems.append(f"unknown action {act!r}")
                continue
            d = {"do": act}
            if act == "police":
                d["stars"] = max(1, min(3, int(b.get("stars", 1) or 1)))
            if act.startswith("prop_"):
                if b.get("prop") not in PROPS:
                    continue
                d["prop"] = b["prop"]
            if act == "park" and b.get("at") in SPOTS:
                d["at"] = b["at"]
            if act in FOOT or act in ("exit_car", "enter_car"):
                who = str(b.get("who", "")).lower().replace(" ", "")
                ok = who == "both" or (who and all(w in ("babu", "shona") or w in side for w in who.split(",")))
                d["who"] = who if ok else ("babu" if act in ("kneel", "fall") else "both")
                if b.get("car") == "van":
                    d["car"] = "van"
            if act in ("arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "look", "appear", "shot"):
                for k in ("who", "to", "at"):
                    if isinstance(b.get(k), str):
                        d[k] = b[k].lower().replace(" ", "")
                if act == "shot":
                    d["type"] = b.get("type") if b.get("type") in SHOTS else "zoom"
                    try:
                        d["dur"] = max(1.0, min(4.0, float(b.get("dur", 2.0))))
                    except (TypeError, ValueError):
                        d["dur"] = 2.0
                if act == "appear":
                    try:
                        d["dist"] = max(3.0, min(30.0, float(b.get("dist", 10))))
                    except (TypeError, ValueError):
                        d["dist"] = 10.0
                if b.get("ko"):
                    d["ko"] = True
            if act == "hold":
                if b.get("prop") not in PROPS:
                    continue
                d["prop"] = b["prop"]
                who = str(b.get("who", "")).lower()
                d["who"] = who if who in ("babu", "shona") else "babu"
            if act == "give":
                who = str(b.get("who", "")).lower()
                d["who"] = who if who in ("babu", "shona", "vendor") else "babu"
                to = str(b.get("to", "")).lower()
                if to in ("babu", "shona", "both") and to != d["who"]:
                    d["to"] = to
                if b.get("prop") in PROPS:
                    d["prop"] = b["prop"]
            if act in ("walk", "run"):
                d["to"] = b.get("to") if b.get("to") in PLACES or b.get("to") in speakers else "ahead"
                if d["to"] in ("ahead", "back"):
                    try:
                        d["dist"] = max(3.0, min(15.0, float(b.get("dist", 8))))
                    except (TypeError, ValueError):
                        d["dist"] = 8.0
            if not endings:
                stage.do(d)
        elif "wait_for" in b:
            if b["wait_for"] in WAIT_FOR and not endings:
                stage.wait_for(b["wait_for"])
        elif "wait" in b:
            try:
                beats.append({"wait": max(0.5, min(3.0, float(b["wait"])))})
            except (TypeError, ValueError):
                pass
        elif "end" in b:
            if endings:
                continue
            endings += 1
            beats.append({"end": ending_for(b["end"] if b["end"] in ENDINGS else MOOD_ENDING.get(mood, "happy"), stage)})
    if endings == 0:
        problems.append("no ending")
        # put an ending before the last line so there is still a closing line
        at = len(beats) - 1 if beats else 0
        beats.insert(max(at, 0), {"end": ending_for(MOOD_ENDING.get(mood, "happy"), stage)})
    if stage.cars:
        sp["cars"] = {c: {"color": CAR_COLORS[c]} for c in stage.cars}
    lines = sum(1 for b in beats if "say" in b)
    if lines < 6:
        problems.append(f"only {lines} lines (need 9 to 14)")
    while sum(1 for b in beats if "say" in b) > 16:
        for i in range(len(beats) - 1, -1, -1):
            if "say" in beats[i] and not any("end" in x for x in beats[i:]):
                beats.pop(i)
                break
        else:
            break
    n = 0
    for b in beats:
        if "say" in b:
            n += 1
            b["id"] = "b%02d" % n
    sp["beats"] = beats
    sp.pop("lines", None)
    sp.pop("reactions", None)
    return sp, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--type", default="funny")
    ap.add_argument("--idea", default="")
    ap.add_argument("--language", default="hinglish", choices=["hinglish", "hindi", "english"])
    ap.add_argument("--episode", default="")
    ap.add_argument("--template", default="auto", help="auto, kidnap_rescue, jealous_reveal, date, proposal")
    ap.add_argument("--base", default=os.path.join(HERE, "..", "..", "story", "screenplays", "ep1_date_night.json"))
    a = ap.parse_args()
    with open(a.base, encoding="utf-8") as f:
        base = json.load(f)
    mood = a.type.lower()
    out_dir = os.path.dirname(os.path.abspath(a.out))
    os.makedirs(out_dir, exist_ok=True)

    sp, used = None, "saved episode"
    if not gemini.key():
        print("::warning::no Gemini key (GEMINI_API_KEY): using the saved episode")
    else:
        prompt = (f"Write a new episode.\nStory type / mood: {mood}.\n"
                  f"Idea from the creator: {a.idea.strip() or 'your choice, surprise me'}.\n"
                  f"Language: {a.language}.\n"
                  + (f"Episode number: {a.episode}.\n" if a.episode else "")
                  + f"Suggested ending for this mood: {MOOD_ENDING.get(mood, 'your choice')}."
                  + (f"\nUse this recipe: {TEMPLATES[a.template]}" if a.template in TEMPLATES else ""))
        feedback = ""
        for attempt in range(2):
            try:
                ai, model = gemini.write_json(prompt + feedback, SYSTEM, temperature=1.0)
            except Exception as e:
                print(f"::warning::Gemini could not write the episode: {e}")
                break
            with open(os.path.join(out_dir, f"ai_answer_{attempt + 1}.json"), "w", encoding="utf-8") as f:
                json.dump(ai, f, ensure_ascii=False, indent=1)
            cand, problems = clean(ai if isinstance(ai, dict) else {}, base, mood)
            lines = sum(1 for b in cand["beats"] if "say" in b)
            print(f"{model}: {lines} lines, problems: {problems or 'none'}")
            serious = [p for p in problems if p.startswith("only") or p == "no ending"]
            if not serious or (attempt == 1 and lines >= 6):
                sp, used = cand, model
                break
            feedback = ("\n\nYour last answer had these problems, fix them: " + "; ".join(problems)
                        + ". Answer with the full JSON again.")
    if sp is None:
        sp = base
    sp["writer"] = used
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(sp, f, ensure_ascii=False, indent=1)
    lines = [b for b in sp.get("beats", []) if "say" in b]
    print(f"screenplay by {used}: {sp.get('title')} / {sp.get('episode')}, {len(lines)} lines")
    for b in sp.get("beats", []):
        if "say" in b:
            print(f"  {b['say']:>6} ({b.get('emotion', 'neutral')}): {b['sub']}")
        else:
            print(f"  -- {json.dumps(b, ensure_ascii=False)}")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"time={sp.get('time', 'dusk')}\nwriter={used}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
