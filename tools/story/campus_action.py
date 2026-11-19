"""Compile AI-written story details onto the verified 28-second campus route."""
import copy
import json
from pathlib import Path

DEMO = Path(__file__).resolve().parents[2] / "story/screenplays/ep10_campus_action.json"
PRIZES = ("trophy", "medal")
WRONG_BAG = ("tiffin", "books")
FIELDS = {"episode": 32, "hook": 39, "mission": 45, "end_text": 34, "sub": 45, "tts": 64}

SYSTEM = """Write the plot text for a 28-second animated campus action Short.
The camera and stunts are locked: Shona drives a pink car away from college, a dark van gives chase,
a helicopter's spotlight follows them, the van hits barrels, the annex facade falls, Shona clears
a railway crossing before a train cuts off the van, and she opens the wrong bag. The final shot shows
the actual prize in the van. Provide the stakes in the mission text and a punchline at the reveal.
The prize mesh can be trophy or medal. The wrong bag can show tiffin or books. The text must match
the props. Follow the creator idea where supported and do not invent additional visible stunts,
cast, locations or props. If a requirement cannot fit these shots, return
{"unsupported_reason":"Explain which part of the creator idea cannot be shown"}.
Use short Roman-script overlay text and subtitles legible on phones. Only one spoken reveal line,
at most six spoken words. In Hindi or Hinglish, write its pronunciation in Devanagari in tts.
In English, tts and sub are the same. Use fictional characters and stylized PG action.
Return JSON with episode, hook, mission, end_text, prize, reveal_prop, sub, and tts.
Limits: episode 32, hook 39, mission 45, end_text 34, sub 45 and tts 64 characters.
Example: {"episode":"CAMPUS UNDER FIRE","hook":"8 SECONDS TO ESCAPE","mission":"SAVE THE COLLEGE TROPHY",
"end_text":"THE VAN HAS IT!","prize":"trophy","reveal_prop":"tiffin",
"sub":"Arre! Ye toh mera tiffin hai!","tts":"अरे! ये तो मेरा टिफ़िन है!"}."""


def compile_story(draft):
    if not isinstance(draft, dict):
        raise ValueError("The campus story must be a JSON object.")
    values = {}
    for key, limit in FIELDS.items():
        value = draft.get(key)
        if not isinstance(value, str) or not value.strip() or len(" ".join(value.split())) > limit:
            raise ValueError(f"{key} needs text of at most {limit} characters.")
        values[key] = " ".join(value.split())
    if len(values["tts"].split()) > 6 or len(values["sub"].split()) > 6:
        raise ValueError("The reveal must be six spoken words or fewer.")
    if draft.get("prize") not in PRIZES or draft.get("reveal_prop") not in WRONG_BAG:
        raise ValueError("Choose trophy or medal for the prize, and tiffin or books for the wrong bag.")

    scene = copy.deepcopy(json.loads(DEMO.read_text(encoding="utf-8")))
    scene.pop("id", None)
    scene.pop("upload", None)
    scene.update({key: values[key] for key in ("episode", "hook", "mission", "end_text")})
    scene.update(prize=draft["prize"], reveal_prop=draft["reveal_prop"])
    reveal = next(beat for beat in scene["beats"] if "say" in beat)
    reveal.update(sub=values["sub"], tts=values["tts"])
    scene["upload"] = {"titles": [values["episode"], values["hook"]],
                       "description": values["mission"], "hashtags": ["#shorts", "#animation", "#carchase"]}
    return scene
