#!/usr/bin/env python3
"""Story lab: Gemini writes a new episode as a screenplay the game can play.

The model is told exactly what the game can do (lines, emotions, police, a jump, props,
endings) and must answer in JSON. The answer is checked and cleaned up (unknown actions
dropped, lengths limited, one ending, ids added). If it is still not usable, or there is
no key, generation fails with diagnostics. A saved episode is only played when selected.

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

EMOTIONS = ["neutral", "smug", "love", "shock", "angry", "sad", "happy", "laugh", "cry", "shy", "scared", "think",
            "excited", "jealous", "worried", "proud"]
GESTURES = ["talk", "up", "point", "wave", "idle"]
ACTIONS = ["police", "calm", "heli", "heli_off", "jump", "roadblock", "crossers", "boom", "train",
           "prop_show", "prop_fly", "prop_hide", "slowmo", "stop", "go",
           "park", "exit_car", "enter_car", "walk", "run", "sit", "stand", "kneel", "fall", "hug",
           "dance", "cheer", "hold", "give",
           "arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "look", "appear", "shot",
           "foot_chase", "reaction",
           "slap", "push", "shrug", "facepalm", "clap", "wave", "spin", "hop", "bow", "phone", "hide", "faint",
           "stumble", "point_at", "heli_down"]
# comic gestures: one person (optionally turned towards "to"), on foot
GESTURE_ACTS = ["shrug", "facepalm", "clap", "wave", "spin", "hop", "bow", "phone", "hide", "faint", "stumble", "point_at"]
FOOT = ["walk", "run", "sit", "stand", "kneel", "fall", "hug", "dance", "cheer"] + GESTURE_ACTS
SPOTS = ["bench", "icecream", "chai", "college_gate", "bus_stop", "park"]       # sets put up where the car parks (park "at")
STALLS = ["icecream", "chai"]               # these come with a vendor who can speak
CAR_ONLY = ["police", "jump", "roadblock", "crossers", "boom", "train", "prop_fly", "heli_down"]   # need the car to be driving
EVENTS = ["takeoff", "big_air", "prop_fly", "near_miss", "cop_wrecked", "roadblock",
          "parked", "exited", "arrived", "seated", "car_arrived", "grabbed", "fled", "cornered", "won",
          "train_crossed", "train_passed", "heli_down", "foot_chase_started", "foot_chase_done", "foot_caught", "foot_escaped"]
WAIT_FOR = ["parked", "exited", "arrived", "seated", "car_arrived", "grabbed", "fled", "cornered", "won", "foot_chase_done", "heli_down"]
SHOTS = ["zoom", "pov", "wide"]
MUSIC_CUES = ["calm", "romantic", "happy", "comic", "sad", "tension", "action", "silence"]
SFX_NAMES = ["boing", "wahwah", "rimshot", "scratch", "crickets", "whoosh", "riser", "heartbeat", "sparkle",
             "ding", "slide_up", "slide_down"]
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
TEMPLATES = {"campus_action": "a staged campus car chase with helicopter, blast and railway crossing",
             "kidnap_rescue": "kidnap & rescue (villains in the van, a chase, a fight)",
             "jealous_reveal": "jealous reveal (a misunderstanding on foot, a twist, they make up)",
             "date": "a date at a place (bench, ice cream or chai)",
             "proposal": "a proposal out of the car",
             "police_foot_chase": "an on-foot police chase: start_on_foot, foot_chase with who=police, no car chase"}
MAX_SIDE = 4
# KIDS MODE: nothing that could be copied into a fight, no villains, no police, no romance. The writer is told so in
# KIDS_MODE; whatever still comes back is dropped here
KIDS_BANNED = ["heli_down", "slap", "push", "fight", "punch", "grab", "police", "calm", "heli", "heli_off", "roadblock", "foot_chase",
               "drive_off", "chase", "corner", "arrive", "boom", "crossers", "kneel", "hug"]
KIDS_PRESETS_OUT = ["goon", "doctor"]
CAR_COLORS = {"van": "#26262b"}
PLACES = ["ahead", "back", "car", "other", "spot"]
ENDINGS = ["happy", "caught", "crash", "cliffhanger"]
PROPS = ["pizza", "flowers", "gift", "ring", "teddy", "icecream", "chai",
         "phone", "balloon", "cake", "umbrella", "bag", "camera", "megaphone"]
VENDOR = {"name": "BHAIYA", "color": "#f0a020",
          "voice": {"gemini": "Fenrir", "edge": "hi-IN-MadhurNeural", "rate": "+12%", "pitch": "-6Hz",
                    "espeak_pitch": 40, "style": "a cheerful, chatty Indian street vendor"},
          "look": {"style": "boy", "skin": "#c98b5e", "hair": "#1d1714", "shirt": "#f3efe4"}}
# a library of side characters: the writer can say {"papa": {"preset": "papa"}} (or just use the id) and gets the
# look, the role and the voice style; anything it writes itself wins over the preset
PRESETS = {
    "papa": {"gender": "male", "role": "Shona's strict, funny papa; overprotective", "voice": "Charon",
             "look": {"style": "oldman", "skin": "#c98b5e", "hair": "#cfcfcf", "shirt": "#e8d8b0", "pants": "#4a4a52",
                      "hair_style": "bald", "outfit": "kurta", "acc": ["mustache", "glasses"]}},
    "mummy": {"gender": "female", "role": "a loud, loving mummy who notices everything", "voice": "Kore",
              "look": {"style": "woman", "skin": "#d99d78", "hair": "#2b1d16", "shirt": "#c0392b", "pants": "#7a2a2a",
                       "hair_style": "bun", "acc": ["bindi"]}},
    "dadi": {"gender": "female", "role": "a sharp-tongued dadi with a heart of gold", "voice": "Achernar",
             "look": {"style": "oldwoman", "skin": "#c98b5e", "hair": "#e6e6e6", "shirt": "#f3efe4", "pants": "#8a6a8a",
                      "hair_style": "bun", "acc": ["glasses", "bindi"]}},
    "bhai": {"gender": "male", "role": "Shona's big brother: tall, suspicious and protective", "voice": "Orus",
             "look": {"style": "boy", "skin": "#b9784f", "hair": "#1d1714", "shirt": "#1b1b22", "pants": "#2c2c34",
                      "build": "big", "acc": ["sunglasses"]}},
    "dost": {"gender": "male", "role": "Babu's best friend, a goofy gossip who ruins plans", "voice": "Alnilam",
             "look": {"style": "boy", "skin": "#e3a373", "hair": "#3b2a1a", "shirt": "#f1c40f", "pants": "#34495e",
                      "hair_style": "spiky", "acc": ["cap"]}},
    "saheli": {"gender": "female", "role": "Shona's best friend, dramatic and nosy", "voice": "Aoede",
               "look": {"style": "girl", "skin": "#f0b48f", "hair": "#2b1d16", "shirt": "#9b59b6", "pants": "#2c3e50",
                        "hair_style": "ponytail"}},
    "teacher": {"gender": "female", "role": "a strict college teacher who catches everyone", "voice": "Despina",
                "look": {"style": "woman", "skin": "#c98b5e", "hair": "#241b16", "shirt": "#3d6a5a", "pants": "#2c3e50",
                         "hair_style": "bun", "acc": ["glasses"]}},
    "uncle": {"gender": "male", "role": "a nosy neighbourhood uncle who has an opinion on everything", "voice": "Rasalgethi",
              "look": {"style": "man", "skin": "#c98b5e", "hair": "#2b2b2b", "shirt": "#d6c9a0", "pants": "#555555",
                       "build": "big", "acc": ["mustache", "tie"]}},
    "aunty": {"gender": "female", "role": "a gossiping neighbourhood aunty", "voice": "Laomedeia",
              "look": {"style": "woman", "skin": "#d99d78", "hair": "#3a2a20", "shirt": "#e84393", "pants": "#6c3483",
                       "hair_style": "bun", "acc": ["bindi"]}},
    "kid": {"gender": "male", "role": "a cheeky kid who knows too much", "voice": "Sadachbia",
            "look": {"style": "kid", "skin": "#e3a373", "hair": "#1d1714", "shirt": "#e67e22", "pants": "#2980b9"}},
    "goon": {"gender": "male", "role": "a clumsy, loud goon", "voice": "Fenrir",
             "look": {"style": "man", "skin": "#b9784f", "hair": "#111111", "shirt": "#1c1c20", "pants": "#1c1c20",
                      "build": "big", "acc": ["mask", "sunglasses"]}},
    "doctor": {"gender": "male", "role": "a calm doctor who delivers news badly", "voice": "Algenib",
               "look": {"style": "man", "skin": "#c98b5e", "hair": "#241b16", "shirt": "#f5f5f5", "pants": "#bcd2e8",
                        "acc": ["glasses", "tie"]}},
    "delivery": {"gender": "male", "role": "a food-delivery boy who is always late", "voice": "Achird",
                 "look": {"style": "boy", "skin": "#c98b5e", "hair": "#1d1714", "shirt": "#e74c3c", "pants": "#222222",
                          "acc": ["cap"]}},
}
TIMES = ["day", "dusk", "night"]
POLICE_LOOK = {"style": "man", "skin": "#c98b5e", "hair": "#241b16", "shirt": "#b49a65",
               "pants": "#776440", "hair_style": "short", "acc": ["cap", "mustache", "badge"]}
MOOD_ENDING = {"happy": "happy", "romantic": "happy", "funny": "happy", "cringe": "happy", "dark": "cliffhanger",
               "sad": "crash", "action": "caught", "twist": "cliffhanger", "drama": "happy"}
MOOD_TIME = {"sad": "night", "romantic": "dusk", "happy": "day", "action": "dusk", "dark": "night"}

SYSTEM = """You write episodes of a short animated comedy-drama series for YouTube Shorts and Instagram Reels.
The show is made in a blocky 3D city game (everything is cubes, like Minecraft or Roblox).

THE SET-UP (fixed, the game cannot do anything else):
- Two main characters are "babu" (boy) and "shona" (girl). By default babu drives a pink car.
  When the idea is on foot, set start_on_foot=true: they begin on the pavement, not in the car.
- The car drives through the city while they talk. They can also pull over and get out for a scene on the
  pavement (a proposal, a fight, a sulk, a race on foot), then get back in and drive on, or end the episode there.
- Police cars, a police helicopter, roadblocks and traffic exist, but they are SIDE characters: bring them in only
  when your story needs them. A quiet story with no police at all is fine.
- "police" can also speak (over a megaphone in car chases, in person during foot_chase), at most 3 short lines.
- When they stop at an ice-cream cart or a chai stall, its "vendor" (a street vendor, "Bhaiya") can speak too,
  at most 3 short lines: funny, chatty, he comments on the couple.

WHAT A SCREENPLAY CAN CONTAIN ("beats", played in order):
1. A line: {"say": "babu"|"shona"|"police"|"vendor", "emotion": E, "react": E, "gesture": G, "sub": "...", "tts": "..."}
   - emotion = how the speaker looks, react = how the other one looks while listening.
   - E is one of: neutral, smug, love, shock, angry, sad, happy, laugh, cry, shy, scared, think, excited, jealous,
     worried, proud.
     G is one of: talk, up, point, wave, idle. The faces and bodies act these out, so use the strong ones
     (cry, shock, angry, love, shy, scared) where the story turns, and give the listener a "react" that fits.
   - Optional "on": wait for a moment in the action before saying the line: takeoff (the car leaves a ramp,
     perfect for a scream), big_air (the car lands), prop_fly, near_miss, cop_wrecked, roadblock,
     train_crossed (the car has just crossed the railway ahead of a train), train_passed (the train has gone by).
2. An action: {"do": A} where A is one of:
   police (add "stars": 1-3, police start chasing them), calm (the police give up and leave),
   heli / heli_off (police helicopter), heli_down (the car jumps a ramp into the helicopter and brings it down in a
     ball of fire: needs the car driving and the police chasing; it takes 10-40 seconds, so put "on": "heli_down" on
     the line that celebrates it, and give the lines before it something to say about the helicopter), jump (a ramp appears on the road and the car jumps it),
   roadblock (police block the road ahead), crossers (two cars cut across just in front: a near miss),
   train (the car heads for a level crossing and goes over just ahead of a passing train: flashing gates, a loud horn),
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
   Car actions (police, jump, roadblock, crossers, boom, train, prop_fly) only work while they are driving.
   ON-FOOT POLICE CHASE:
   {"do": "foot_chase", "who": "police", "to": "babu" | "shona", "dur": 4-12,
    "outcome": "caught" | "escape"}
   A visible uniformed police officer runs after the runner along the pavement. The runner flees,
   the officer follows their changing position, and the camera tracks both. No police car is used.
   The officer is built automatically; do not add police as a custom side character.
   They can speak DURING the chase, then {"wait_for": "foot_chase_done"} waits for its result.
   caught = the officer reaches the runner and stops them; escape = the officer gives up.
   Use a happy or cliffhanger ending afterward (the separate end=caught is a CAR arrest).
   Use this action for an idea about running from police on foot; ordinary run + police is NOT equivalent.
   The chase stays on one block's pavement; no jumping walls, rooftops or entering buildings.
   COMIC ACTIONS ON FOOT (who = "babu" | "shona" | a side character id; they must be out of the car):
     slap ("who" walks up to "to" and slaps them: THAPPAD! and a stagger), push ("who" shoves "to": DHAKKA!),
     shrug (a "who knows" shrug), facepalm (hand to the forehead), clap, wave (a big wave), spin (twirls for joy),
     hop (a jump for joy), bow (a dramatic bow), phone (takes a call: a phone in the hand, until "stand"),
     hide (ducks down, hands over the head, until "stand"), faint (swoons onto the back, until "stand"),
     stumble (trips and catches themselves), point_at (points at "to"). The gestures take an optional "to": the
     person they turn towards. Use them for the jokes: a slap after a bad line, a facepalm after a silly one, a
     faint at the reveal, hide when papa turns up, a bow after a victory. Do not use the same one twice in a row.
   SIDE CHARACTERS ("cast", optional, at most 4; ids are short lowercase words like "rahul", "goon1", "papa"):
     "cast": {"rahul": {"name": "RAHUL", "gender": "male", "role": "Shona's cousin, nerdy and loud",
                        "look": {"style": S, "skin": "#c98b5e", "hair": "#2b1d16", "shirt": "#f2f2f2", "pants": "#3a4a6a",
                                 "hair_style": H, "build": B, "acc": [A, ...]},
                        "start": {"at": "ahead" | "back" | "near:<id>", "dist": metres} or {"car": "van"}}}
     READY-MADE SIDE CHARACTERS: instead of a look, write {"papa": {"preset": "papa"}} (or just use the id) for one of:
     papa, mummy, dadi, bhai (big brother), dost (babu's friend), saheli (shona's friend), teacher, uncle, aunty, kid,
     goon, doctor, delivery. They come with a look and a voice; add "name", "role" or "start" as you like.
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
3. MUSIC AND SOUND (optional: the editor already changes the music with the story and adds effects on
   falls, hits, shocks, sad lines and the punchline): {"music": "calm" | "romantic" | "happy" | "comic" | "sad" |
   "tension" | "action" | "silence"} switches the music right there; {"sfx": "boing" | "wahwah" | "rimshot" |
   "scratch" | "crickets" | "whoosh" | "riser" | "heartbeat" | "sparkle" | "ding" | "slide_up" | "slide_down"}
   plays a sound effect. Use them only for a moment that needs it (a "silence" before a big reveal, crickets
   after an awkward line, a "ding" when somebody gets an idea).
4. {"wait": seconds} (at most 3), or {"wait_for": "exited" | "arrived" | "seated"}: wait until they are out of the
   car / have reached where they walked or ran to / are back in their seats. A line can wait with "on": "parked".
5. Exactly one ending: {"end": "happy" | "caught" | "crash" | "cliffhanger"}
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
Props (P): pizza, flowers, gift, ring, teddy, icecream, chai, phone, balloon, cake, umbrella, bag, camera, megaphone. List the ones in the car at the start in "props".

WRITING RULES:
- A college_gate chase is a short film. Open on the hook, use short spoken lines (one thought each),
  and save the reaction for the reveal. Skip generic exposition and long ellipses. Place the runner
  at "spot". Use look.outfit="kurta" for a kurta and choose a height and build for each lead.
- For a 10-15 second sketch set "format":"short"; 2-4 short lines are allowed.
- Custom lead names and looks go in cast.babu and cast.shona (internal actor ids); use names for display labels.
  A/B in the creator script map to babu/shona. Preserve their given dialogues and clothing colours.
- Extra start_spot / park at locations: college_gate, bus_stop, park (outdoor pavement sets).
- Reaction bundle: {"do":"reaction","who":"babu","effect":"shock_freeze","dur":1.2} combines shock,
  sweat, freeze, zoom and record scratch. Other effects: sweat, sparkle. Do not add a duplicate wait.
- The creator's explicit actions, travel mode, characters and premise are requirements. Preserve them.
  Never replace a requested on-foot chase with driving, or invent pizza/theft as a substitute premise.
  If a required action cannot be staged using the vocabulary above, answer
  {"unsupported_reason": "explain which requested action is unsupported"} instead of changing the story.
- 9 to 16 lines in total, each line at most 12 words. Talky episodes last about 40 seconds, action ones about 60.
- A real story: the first line is a hook (a problem, a promise or a question), then trouble that grows,
  a twist, a payoff that fits the mood, and a last line that is a punchline or an emotional moment.
- Show, do not explain the game: never talk about "the game", "bots", "ramps appearing" or "levels".
- Every action you use must matter to the story, and the lines around it must react to it.
- At most two scenes out of the car, at DIFFERENT places, and only when the story is better for it (getting out takes
  a few seconds; between the scenes they get back in, "enter_car" then "go", and park again with another "at").
  A scene out of the car works best at a place (bench, icecream, chai, bus_stop, park, college_gate).
- VARIETY: this is one episode of a long series, so do not repeat the stock moves (a ramp jump, a chase, a hug).
  Use at least two of the COMIC ACTIONS and one prop in a way that pays off, bring in a ready-made side character
  when the story has a third voice, and give the episode its own setting.
- Keep it PG: cute, cringe, funny or emotional. No real people, brands or places, no hate, no real violence.
- The voice actor only gets the words, so put the feeling into them: exclamations, "arre", "uff", "haha",
  "hmm...", question marks and pauses ("...") where they belong.
- Rhythm makes it emotional: a few quick back-and-forth lines, then a big line and a beat of silence
  ({"wait": 1}) while the other one reacts. Do not let every line rush into the next one.

LANGUAGE:
- hinglish: "sub" is natural Roman-script Hinglish like Instagram captions; "tts" is the SAME line written in
  Devanagari so a Hindi voice reads it well (English words written as they sound).
- hindi: "sub" is simple Hindi in Roman script; "tts" the same in Devanagari.
- english: "sub" and "tts" are both English.

ANSWER with one JSON object only:
{"title": "BABU & SHONA", "episode": "the episode's own title, 2-4 words, no number", "end_text": "teaser for next part, max 4 words",
 "names": {"babu": "BABU", "shona": "SHONA"}, "time": "day|dusk|night", "props": [], "driver": "babu" (or "shona": she drives the car),
 "cast": { optional side characters }, "start_on_foot": false,
 "beats": [ ... ],
 "upload": {"titles": ["3 catchy titles, max 60 chars, 1-2 emojis"], "description": "2 short lines",
            "hashtags": ["#shorts", "..."]}}
Keep "names" as BABU and SHONA unless the idea asks for other names (then put the new names there, in capitals)."""


NEVER = """Never (hard rules, even if the idea asks for it):
- no suicide or self-harm, not even as a joke or a threat
- no sexual content or jokes about sexual violence; nothing involving children in danger
- no real tragedies, disasters, wars, terror attacks, accidents or real people (alive or dead)
- no jokes about religion, caste, region, skin colour, gender, body shape, illness or disability
- no slurs, gaali or abuse; no drugs, alcohol or smoking shown as cool
- no realistic violence, blood or weapons; fights stay cartoon (DHISHUM!, knocked out, stars)
- no mocking the poor or the helpless: punch up (the villain, the boss, the system, themselves),
  never down
If the idea needs something on this list, keep the dark tone but swap in a safe target."""

KIDS_MODE = """

KIDS MODE (this episode is for children of about 4 to 9; they must stay hooked and the parents must be happy)
Make it a bright, silly mini-adventure with two friends, Babu and Shona. Rules:
- HOOK in the first line: a funny problem, a surprise or a question a child wants answered ("Arre! Mera cake kahan gaya?").
- Very simple words, at most 8 words a line, 7 to 11 lines. Lots of "haha", "arre", "wow", "uff".
- A CATCHPHRASE: one short funny phrase (say "Dhamaka!" or "Chalo chalo!") said three times, so children can shout it.
- A tiny mystery or riddle the children can guess, and the answer is a surprise at the end ("Kaun hai chor? Billu!").
- Slapstick without hurting anyone: use stumble, faint, hop, spin, clap, wave, bow, hide, phone, fall, shrug,
  facepalm. Props like balloon, cake, umbrella, bag. Colourful, loud, happy.
- A kind lesson, never preachy: sharing, honesty, helping, being brave. The problem is solved by cleverness or
  kindness, never by hitting.
- NEVER: slap, push, fight, punch, grabbing, police, helicopters, chases, villains, goons, kidnap, scary or sad
  endings, romance, kissing, dating, weapons, danger a child could copy. Babu and Shona are best friends.
- End: happy, a last funny line, and then a question to the children ("Aapko kaun sa gubbara pasand hai?"),
  and "end_text" teases the next part ("KAL: BILLU KA BIRTHDAY!").
- Use the emotions excited, happy, laugh, shock, shy, think; the music will be bright.
"""
DARK_MODE = """

DARK HUMOR MODE (this episode's mood is "dark")
Tone: dark, deadpan comedy. Terrible things happen and the characters react with calm, petty or
absurd logic instead of panic. The laugh comes from the gap between how bad it is and how casually
they take it. Still a cartoon: blocky characters, nobody really gets hurt, and the couple still love
each other underneath.
Techniques to use:
- Deadpan: the worse the situation, the calmer the line ("Car gayi, phone gaya... chalo, EMI toh bachi").
- Misplaced priorities: in a disaster they worry about something tiny (the pizza, the parking ticket,
  the Wi-Fi password, "last seen").
- Escalation: each attempt to fix things makes it worse; the last beat is the worst, said calmly.
- Brutal honesty: a character says out loud what everybody thinks ("Main tumhe bachane nahi, apni
  gaadi ki EMI bachane aaya hoon").
- Karma and irony: the plan backfires on whoever made it; the villain's own trick catches him.
- Morbid exaggeration about everyday things: meeting her papa is like going to war ("Will likh ke aaya
  hoon"), a Monday is a funeral.
- Savage but loving roasts between Babu and Shona; the last line can be a sting, not a hug.
Good endings for dark mode: "crash" or "cliffhanger" with a deadpan last line, or a happy ending that is
ruined in the very last line.
""" + NEVER

REVIEW = """You are the standards editor of a dark comedy series for YouTube Shorts and Instagram Reels.
Below is an episode as JSON. Check every line ("sub" and "tts") and every action against these rules:
""" + NEVER + """
If something breaks a rule, rewrite only that part so the joke keeps its dark, deadpan tone but uses a
safe target. Keep everything else exactly as it is: the same keys, beats, order and wording.
Answer with the full episode JSON only."""

# words that never go out, in any mood (Roman Hinglish, English and Devanagari)
UNSAFE = re.compile(
    r"suicide|khudkushi|khud ?kushi|atmahatya|aatmhatya|self[- ]?harm|kill (my|him|her)self|"
    r"\brape|balatkar|molest|\bbombs?\b|terroris|aatankwad|"
    r"drugs?\b|ganja|charas|cocaine|heroin|"
    r"chutiy|madarchod|ma+dar ?chod|behen ?chod|bhen ?chod|bhosd|gaa?ndu|randi|"
    r"आत्महत्या|खुदकुशी|बलात्कार|आतंक|गांजा|चरस|चूतिय|मादरचोद|बहनचोद|भोसड|गांडू|रंडी",
    re.IGNORECASE)


def unsafe_words(ai):
    """The banned words that appear anywhere in the model's answer."""
    return sorted({m.group(0).lower() for m in UNSAFE.finditer(json.dumps(ai, ensure_ascii=False))})


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
        pid = c.get("preset") if c.get("preset") in PRESETS else (cid if cid in PRESETS else None)
        if pid:
            base_p = PRESETS[pid]
            mine = c.get("look") if isinstance(c.get("look"), dict) else {}
            c = {**base_p, **{k: v for k, v in c.items() if k != "look"}, "look": {**base_p["look"], **mine}}
            c.setdefault("name", pid)
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
        if isinstance(look_in.get("height"), (float, int)) and not isinstance(look_in["height"], bool):
            look["height"] = max(0.75, min(1.2, look_in["height"]))
        if look_in.get("outfit") in ("kurta", "uniform"):
            look["outfit"] = look_in["outfit"]
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
        self.heli_seen = False  # the police helicopter has been called
        self.foot_duration = 0.0

    def finish_foot_chase(self):
        if self.foot_duration:
            self.wait("foot_chase_done", self.foot_duration + 4)
            self.foot_duration = 0.0

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
        if act == "reaction":
            self.beats.append(d)
            self.beats.append({"wait": d["dur"]})
        elif act == "foot_chase":
            if self.chasing or who != "police" or to not in ("babu", "shona") or to in self.in_van:
                self.problems.append("invalid foot_chase: use police pursuing babu or shona on the pavement")
                return True
            self.get_out({to})
            self.beats.append(d)
            self.foot_duration = d["dur"]
        elif act == "arrive":
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
        elif act in ("fight", "punch", "slap", "push"):
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
        if self.foot_duration and act not in ("shot", "look", "hold", "give", "slowmo"):
            self.finish_foot_chase()
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
            if act == "heli":
                self.heli_seen = True
            if act == "heli_down":
                # the helicopter must be there first; the lines after it wait until it is down
                if not self.heli_seen:
                    self.beats.append({"do": "heli"})
                    self.heli_seen = True
                self.beats.append(d)
                self.wait("heli_down", 45)
                return
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
        if ev == "foot_chase_done":
            self.finish_foot_chase()
        elif ev == "parked" and self.parked and not self.out:
            self.wait("parked", 22)
        elif ev == "arrived" and self.walking:
            self.wait("arrived", 12)
            self.walking = False


def ending_for(kind, stage):
    """A parked car does not spin out or get chased down: those endings become a quiet one or a freeze."""
    if stage.parked and kind in ("crash", "caught"):
        return "happy" if kind == "crash" else "cliffhanger"
    return kind


def clean(ai, base, mood, kids=False):
    """A screenplay the game can play, built from the model's answer. Returns (screenplay, problems)."""
    sp = copy.deepcopy(base)
    problems = []
    for lead in ("babu", "shona"):
        requested = ai.get("cast", {}).get(lead, {}) if isinstance(ai.get("cast"), dict) else {}
        if isinstance(requested, dict) and requested.get("look"):
            checked = side_cast({"actor": requested}, problems)["actor"]
            sp["cast"][lead]["look"] = checked["look"]
            if requested.get("name"):
                sp["cast"][lead]["name"] = checked["name"]
    names = ai.get("names") if isinstance(ai.get("names"), dict) else {}
    for k in ("babu", "shona"):
        if names.get(k):
            sp["cast"][k]["name"] = clip(names[k], 14).upper()
    sp["title"] = clip(ai.get("title") or f"{sp['cast']['babu']['name']} & {sp['cast']['shona']['name']}", 24).upper()
    sp["episode"] = clip(ai.get("episode") or "NEW EPISODE", 34).upper()
    sp["end_text"] = clip(ai.get("end_text") or "PART 2 JALDI...", 28).upper()
    sp["mood"] = mood
    if ai.get("driver") == "shona":
        # shona at the wheel, babu beside her
        sp["cast"]["shona"]["seat"], sp["cast"]["babu"]["seat"] = "driver", "passenger"
    if kids:
        sp["audience"] = "kids"
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
    if kids:
        side = {k: v for k, v in side.items() if k not in KIDS_PRESETS_OUT and "mask" not in v["look"].get("acc", [])}
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
            if kids and act in KIDS_BANNED:
                continue
            d = {"do": act}
            if act == "reaction":
                d["who"] = b.get("who", "babu")
                d["effect"] = b.get("effect", "shock_freeze")
                if d["who"] not in speakers or d["effect"] not in ("shock_freeze", "sweat", "sparkle"):
                    problems.append("unsupported reaction actor or effect")
                    continue
                d["dur"] = max(0.5, min(3.0, float(b.get("dur", 1.2))))
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
                d["who"] = who if ok else ("babu" if act in ("kneel", "fall") + tuple(GESTURE_ACTS) else "both")
                if act in GESTURE_ACTS and isinstance(b.get("to"), str) and b["to"].lower() in speakers:
                    d["to"] = b["to"].lower()
                if b.get("car") == "van":
                    d["car"] = "van"
            if act in ("arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "slap", "push", "look", "appear", "shot", "foot_chase"):
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
                if act == "foot_chase":
                    d.setdefault("who", "police")
                    d.setdefault("to", "babu")
                    try:
                        d["dur"] = max(4.0, min(12.0, float(b.get("dur", 8))))
                    except (TypeError, ValueError):
                        d["dur"] = 8.0
                    d["outcome"] = b.get("outcome") if b.get("outcome") in ("caught", "escape") else "escape"
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
        elif "music" in b or "sfx" in b:
            if b.get("music") in MUSIC_CUES:
                beats.append({"music": b["music"]})
            elif b.get("sfx") in SFX_NAMES:
                beats.append({"sfx": b["sfx"]})
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
            stage.finish_foot_chase()
            endings += 1
            beats.append({"end": ending_for("happy" if kids else (b["end"] if b["end"] in ENDINGS else MOOD_ENDING.get(mood, "happy")), stage)})
    if endings == 0:
        stage.finish_foot_chase()
        problems.append("no ending")
        # put an ending before the last line so there is still a closing line
        at = len(beats) - 1 if beats else 0
        beats.insert(max(at, 0), {"end": ending_for(MOOD_ENDING.get(mood, "happy"), stage)})
    if stage.cars:
        sp["cars"] = {c: {"color": CAR_COLORS[c]} for c in stage.cars}
    if any(b.get("do") == "foot_chase" for b in beats):
        sp["cast"]["police"]["look"] = copy.deepcopy(POLICE_LOOK)
        sp["cast"]["police"].pop("radio", None)
        if sp.get("start_spot") == "college_gate":
            sp["cinematic"] = True
            sp["cast"]["police"]["look"].update(build="big", height=1.12, outfit="uniform")
    lines = sum(1 for b in beats if "say" in b)
    minimum = 2 if ai.get("format") == "short" else 6
    if lines < minimum:
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


def variety_hint(rng=None, kids=False):
    """A nudge so that episodes written one after another do not all use the same moves."""
    import random
    r = rng or random.Random()
    acts = r.sample(GESTURE_ACTS if kids else GESTURE_ACTS + ["slap", "push"], 3)
    who = r.choice([p for p in sorted(PRESETS) if not (kids and p in KIDS_PRESETS_OUT)])
    place = r.choice([x for x in SPOTS])
    prop = r.choice(PROPS)
    return (f"For variety, if it fits the idea, build in: the actions {', '.join(acts)}; the ready-made side character "
            f"\"{who}\"; the place \"{place}\"; the prop \"{prop}\". Drop any of these that do not fit.\n")


def needs_foot_chase(idea, template="auto"):
    """Catch explicit English/Hinglish/Hindi requests; the template is an unambiguous override."""
    if template == "police_foot_chase":
        return True
    police = re.search(r"\b(police|pulis|cop|cops|officer)\b|पुलिस", idea, re.I)
    if not police:
        return False
    if re.search(r"\b(on[ -]foot|foot chase|paidal|pedal)\b|पैदल", idea, re.I):
        return True
    if re.search(r"\b(car|gaadi|gadi|van|bike|truck)\b|गाड़ी|गाडी|कार", idea, re.I):
        return False
    return bool(re.search(r"\b(walking|running|runs?|bhag\w*|bhaag\w*|daud\w*)\b|भाग|दौड़", idea, re.I))


def intent_problems(sp, idea, template="auto"):
    if not needs_foot_chase(idea, template):
        return []
    chases = [b for b in sp.get("beats", []) if b.get("do") == "foot_chase" and b.get("who") == "police"]
    if not chases:
        return ["The requested on-foot police chase is missing. Use foot_chase with who=police; do not substitute a car chase."]
    issues = []
    named = [who for who, pattern in (("babu", r"\bbabu\b|बाबू"), ("shona", r"\bshona\b|शोना"))
             if re.search(pattern, idea, re.I)]
    if len(named) == 1 and not any(b.get("to") == named[0] for b in chases):
        issues.append(f"The requested runner is {named[0]}; keep that character in the foot_chase.")
    mixed_transport = re.search(r"\b(car|gaadi|gadi|van|bike|truck)\b|गाड़ी|गाडी|कार", idea, re.I)
    if template == "police_foot_chase" or not mixed_transport:
        if not sp.get("start_on_foot"):
            issues.append("The requested on-foot story must start_on_foot, not open with driving.")
        if any(b.get("do") in CAR_ONLY + ["chase", "drive_off", "go"] for b in sp.get("beats", [])):
            issues.append("Do not add a vehicle chase to the requested on-foot story.")
    return issues


def generation_failed(out, reason, idea):
    """Leave an actionable failure in Actions and artifacts, never a replacement screenplay."""
    reason = clip(reason, 1800)
    # Avoid an older output being mistaken for this failed generation on a local rerun.
    if os.path.isfile(out):
        os.remove(out)
    with open(os.path.join(os.path.dirname(os.path.abspath(out)), "generation_error.json"), "w", encoding="utf-8") as f:
        json.dump({"status": "failed", "reason": reason, "idea": idea, "fallback_used": False}, f, ensure_ascii=False, indent=2)
    print("::error::Story generation failed: " + reason.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A"))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Story generation failed\n\n" + reason + "\n\nNo video was recorded and no saved episode was substituted. "
                    "Fix the issue and retry, or explicitly select a saved script.\n")
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--type", default="funny")
    ap.add_argument("--idea", default="")
    ap.add_argument("--language", default="hinglish", choices=["hinglish", "hindi", "english"])
    ap.add_argument("--episode", default="")
    ap.add_argument("--template", default="auto", choices=["auto", *TEMPLATES])
    ap.add_argument("--base", default=os.path.join(HERE, "..", "..", "story", "screenplays", "ep1_date_night.json"))
    a = ap.parse_args()
    with open(a.base, encoding="utf-8") as f:
        base = json.load(f)
    mood = a.type.lower()
    kids = mood == "kids"
    out_dir = os.path.dirname(os.path.abspath(a.out))
    os.makedirs(out_dir, exist_ok=True)

    sp, used = None, ""
    failure = "The AI did not return a valid screenplay."
    if not gemini.key():
        return generation_failed(a.out, "No Gemini API key was found. Add GEMINI_API_KEY (or GEMINI_API_KEY_1 ... _5) to repository secrets for script=ai.", a.idea)
    else:
        prompt = (f"Write a new episode.\nStory type / mood: {mood}.\n"
                  f"Idea from the creator: {a.idea.strip() or 'your choice, surprise me'}.\n"
                  f"Language: {a.language}.\n"
                  + (f"Episode number: {a.episode}.\n" if a.episode else "")
                  + f"Suggested ending for this mood: {MOOD_ENDING.get(mood, 'your choice')}."
                  + (f"\nUse this recipe: {TEMPLATES[a.template]}" if a.template in TEMPLATES else "")
                  + "\n" + variety_hint(kids=kids)
                  + (DARK_MODE if mood == "dark" else "") + (KIDS_MODE if kids else ""))
        if needs_foot_chase(a.idea, a.template):
            prompt += "\nRequired: show an on-foot police chase using foot_chase with who=police. Keep the requested runner on foot."
        campus = a.template == "campus_action"
        system = SYSTEM
        if campus:
            import campus_action
            system = campus_action.SYSTEM
            prompt = f"Creator idea: {a.idea.strip() or 'Surprise me within the fixed campus route'}.\nLanguage: {a.language}."
        feedback = ""
        for attempt in range(2):
            try:
                ai, model = gemini.write_json(prompt + feedback, system, temperature=1.0)
            except Exception as e:
                print(f"::warning::Gemini could not write the episode: {e}")
                failure = f"Gemini request failed: {e}. Check the key, quota and provider availability, then retry."
                break
            with open(os.path.join(out_dir, f"ai_answer_{attempt + 1}.json"), "w", encoding="utf-8") as f:
                json.dump(ai, f, ensure_ascii=False, indent=1)
            if not campus and mood == "dark" and isinstance(ai, dict):
                # dark humour is where the platforms' rules bite: a second read against the rules
                try:
                    fixed, _ = gemini.write_json(REVIEW + "\n\n" + json.dumps(ai, ensure_ascii=False), temperature=0.3)
                    if isinstance(fixed, dict) and fixed.get("beats"):
                        changed = json.dumps(fixed, sort_keys=True) != json.dumps(ai, sort_keys=True)
                        print(f"standards review: {'rewrote some lines' if changed else 'no changes'}")
                        ai = fixed
                except Exception as e:
                    print(f"::warning::standards review failed ({e}): keeping the draft")
            if isinstance(ai, dict) and ai.get("unsupported_reason"):
                failure = "Unsupported story request: " + str(ai["unsupported_reason"])
                break
            try:
                if campus:
                    cand, problems = campus_action.compile_story(ai), []
                else:
                    cand, problems = clean(ai if isinstance(ai, dict) else {}, base, "happy" if kids else mood, kids=kids)
                    problems.extend(intent_problems(cand, a.idea, a.template))
            except (TypeError, ValueError, KeyError, AttributeError) as e:
                failure = f"The AI returned malformed screenplay data: {e}"
                feedback = f"\nYour last response could not be used: {e}. Return valid JSON."
                continue
            bad = unsafe_words(ai)
            if bad:
                problems.append("unsafe words: " + ", ".join(bad))
            lines = sum(1 for b in cand["beats"] if "say" in b)
            print(f"{model}: {lines} lines, problems: {problems or 'none'}")
            serious = [p for p in problems if not p.startswith("line too long:")]
            failure = "The generated screenplay failed validation: " + "; ".join(serious)
            if bad:
                feedback = ("\n\nYour last answer used words that can never go out (" + ", ".join(bad)
                            + "). Write the episode again without them, keeping the tone. Answer with the full JSON.")
                continue
            if not serious:
                sp, used = cand, model
                break
            feedback = ("\n\nYour last answer had these problems, fix them: " + "; ".join(problems)
                        + ". Answer with the full JSON again.")
    if sp is None:
        return generation_failed(a.out, failure, a.idea)
    sp["writer"] = used
    sp["creator_idea"] = a.idea
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
