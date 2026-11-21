"""Offline regressions: never replace a creator's requested story with the pizza episode."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import shutil
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "story"))
import write
import verify


def draft(chase=True, on_foot=True):
    beats = [{"say": "babu", "sub": f"Officer, this is line {n}.", "emotion": "scared"} for n in range(9)]
    if chase:
        beats.insert(1, {"do": "foot_chase", "who": "police", "to": "babu", "dur": 8, "outcome": "caught"})
    beats.insert(-1, {"end": "happy"})
    return {"episode": "Wrong Turn", "start_on_foot": on_foot, "beats": beats}


def comic_draft():
    say = lambda who, n: {"say": who, "sub": f"Line number {n} here.", "emotion": "shock"}
    beats = [say("babu", 1), say("shona", 2),
             {"do": "park", "at": "park"}, {"do": "exit_car", "who": "both"},
             {"do": "slap", "who": "shona", "to": "babu"}, {"do": "facepalm", "who": "shona", "to": "babu"},
             {"do": "phone", "who": "babu"}, {"do": "stand", "who": "babu"},
             {"do": "hold", "who": "shona", "prop": "balloon"},
             {"do": "push", "who": "dost", "to": "babu"}, {"do": "faint", "who": "dost"}]
    beats += [say("babu", n) for n in range(3, 10)] + [{"end": "happy"}]
    return {"episode": "Comic Kit", "start_on_foot": False, "beats": beats,
            "cast": {"dost": {"preset": "dost", "start": {"at": "ahead", "dist": 8}},
                     "papa": {}, "teacher": {}, "kid": {}, "mummy": {}}}


class ComicKitTests(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((ROOT / "story/screenplays/ep1_date_night.json").read_text(encoding="utf-8"))

    def test_presets_give_looks_and_voices_and_four_side_characters_fit(self):
        problems = []
        cast = write.side_cast({"papa": {}, "dost": {"preset": "dost", "name": "Raju"}, "teacher": {}, "kid": {}, "mummy": {}}, problems)
        self.assertEqual(sorted(cast), ["dost", "kid", "papa", "teacher"])       # MAX_SIDE = 4
        self.assertEqual(cast["dost"]["name"], "RAJU")                              # what the writer says wins
        self.assertEqual(cast["papa"]["look"]["style"], "oldman")
        self.assertIn("mustache", cast["papa"]["look"]["acc"])
        self.assertEqual(len({c["voice"]["gemini"] for c in cast.values()}), 4)
        self.assertTrue(any("too many" in p for p in problems))

    def test_every_preset_is_buildable(self):
        for pid, p in write.PRESETS.items():
            self.assertIn(p["look"]["style"], write.STYLES, pid)
            self.assertTrue(all(a in write.ACCESSORIES for a in p["look"].get("acc", [])), pid)
            self.assertIn(p["voice"], write.MALE_VOICES + write.FEMALE_VOICES, pid)

    def test_comic_actions_survive_clean_in_order(self):
        sp, problems = write.clean(comic_draft(), self.base, "funny")
        acts = [b["do"] for b in sp["beats"] if "do" in b]
        for a in ("slap", "facepalm", "phone", "push", "faint"):
            self.assertIn(a, acts)
        slap = next(b for b in sp["beats"] if b.get("do") == "slap")
        self.assertEqual((slap["who"], slap["to"]), ("shona", "babu"))
        face = next(b for b in sp["beats"] if b.get("do") == "facepalm")
        self.assertEqual(face.get("to"), "babu")
        # whoever slaps is out of the car first, and the car is parked before that
        self.assertLess(acts.index("park"), acts.index("exit_car"))
        self.assertLess(acts.index("exit_car"), acts.index("slap"))
        self.assertFalse([p for p in problems if "unknown action" in p], problems)

    def test_gestures_are_dropped_while_driving(self):
        d = {"episode": "Wrong", "start_on_foot": False, "beats": [
            {"say": "babu", "sub": "Line one is here.", "emotion": "shock"}, {"do": "shrug", "who": "babu"}] +
            [{"say": "shona", "sub": f"Line {n} is here.", "emotion": "shock"} for n in range(9)] + [{"end": "happy"}]}
        sp, _ = write.clean(d, self.base, "funny")
        acts = [b["do"] for b in sp["beats"] if "do" in b]
        self.assertEqual(acts.count("shrug"), 1)
        self.assertLess(acts.index("park"), acts.index("shrug"))               # the car parks first

    def test_new_props_are_known_to_the_writer_and_the_game(self):
        game = (ROOT / "story/props.gd").read_text(encoding="utf-8")
        for prop in write.PROPS:
            self.assertIn(f'"{prop}"', game, prop)

    def test_every_action_the_writer_may_use_is_handled_by_the_game(self):
        game = (ROOT / "story/story.gd").read_text(encoding="utf-8")
        for act in write.GESTURE_ACTS + ["slap", "push"]:
            self.assertIn(f'"{act}"', game, act)

    def test_variety_hint_mentions_real_things(self):
        import random
        hint = write.variety_hint(random.Random(3))
        self.assertTrue(any(a in hint for a in write.GESTURE_ACTS + ["slap", "push"]))
        self.assertTrue(any(f'"{p}"' in hint for p in write.PRESETS))


class GeminiFallbackTests(unittest.TestCase):
    def setUp(self):
        sys.path.insert(0, str(ROOT / "tools" / "story"))
        import gemini
        self.g = gemini

    def test_an_overloaded_model_hands_over_to_the_next_one(self):
        g = self.g
        ok = {"candidates": [{"content": {"parts": [{"text": "{\"a\": 1}"}]}}]}
        seen = []

        def fake_call(path, body, tries=5, **kw):
            seen.append((path, tries))
            if "model-a" in path:
                raise g.GeminiError("HTTP 503: high demand", status=503)
            return ok
        with patch.object(g, "ranked", return_value=["models/model-a", "models/model-b", "models/model-c"]), \
                patch.object(g, "call", side_effect=fake_call), contextlib.redirect_stdout(io.StringIO()):
            out, model = g.write_json("hi")
        self.assertEqual((out, model), ({"a": 1}, "models/model-b"))
        self.assertEqual([p.split("/")[2].split(":")[0] for p, _ in seen], ["model-a", "model-b"])

    def test_a_real_error_is_not_swallowed(self):
        g = self.g

        def fake_call(path, body, tries=5, **kw):
            raise g.GeminiError("HTTP 400: bad request", status=400)
        with patch.object(g, "ranked", return_value=["models/model-a", "models/model-b"]), \
                patch.object(g, "call", side_effect=fake_call), self.assertRaises(g.GeminiError):
            g.write_json("hi")

    def test_every_model_busy_still_fails(self):
        g = self.g

        def fake_call(path, body, tries=5, **kw):
            raise g.GeminiError("HTTP 503", status=503)
        with patch.object(g, "ranked", return_value=["models/a", "models/b"]), \
                patch.object(g, "call", side_effect=fake_call), contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaises(g.GeminiError):
            g.write_json("hi")


class HeliDownTests(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((ROOT / "story/screenplays/ep1_date_night.json").read_text(encoding="utf-8"))

    def draft(self, extra=None, driver="shona"):
        say = lambda w, n: {"say": w, "sub": f"Line number {n} here.", "emotion": "shock"}
        return {"episode": "Heli", "driver": driver, "beats": [say("babu", 1), say("shona", 2)] + (extra or [{"do": "heli_down"}])
                + [say("shona", n) for n in range(3, 11)] + [{"end": "happy"}]}

    def test_the_helicopter_is_called_first_and_the_story_waits_for_it_to_fall(self):
        sp, problems = write.clean(self.draft(), self.base, "twist")
        kinds = [b.get("do") or ("wait:" + b["wait_for"] if "wait_for" in b else "say") for b in sp["beats"]]
        self.assertEqual(kinds[2:5], ["heli", "heli_down", "wait:heli_down"])
        self.assertEqual(problems, [])

    def test_shona_can_drive(self):
        sp, _ = write.clean(self.draft(), self.base, "twist")
        self.assertEqual((sp["cast"]["shona"]["seat"], sp["cast"]["babu"]["seat"]), ("driver", "passenger"))
        sp, _ = write.clean(self.draft(driver="babu"), self.base, "twist")
        self.assertEqual((sp["cast"]["shona"]["seat"], sp["cast"]["babu"]["seat"]), ("passenger", "driver"))

    def test_no_takedown_while_parked_or_for_kids(self):
        park = [{"do": "park"}, {"do": "exit_car", "who": "both"}, {"do": "heli_down"}]
        sp, problems = write.clean(self.draft(park), self.base, "twist")
        self.assertTrue(any("while the car is parked" in p for p in problems))
        sp, _ = write.clean(self.draft(), self.base, "happy", kids=True)
        self.assertNotIn("heli_down", [b.get("do") for b in sp["beats"]])

    def test_the_game_knows_the_new_cue_and_event(self):
        d = (ROOT / "director.gd").read_text(encoding="utf-8")
        self.assertIn('"heli_down":', d)
        self.assertIn("heli_down", write.EVENTS)
        self.assertIn("heli_down", write.WAIT_FOR)


class KidsModeTests(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((ROOT / "story/screenplays/ep1_date_night.json").read_text(encoding="utf-8"))

    def draft(self):
        d = comic_draft()
        d["beats"].insert(3, {"do": "fight", "who": "dost", "to": "babu"})
        d["beats"].insert(3, {"do": "hug"})
        d["beats"][-1] = {"end": "crash"}
        d["cast"] = {"dost": {"preset": "dost"}, "goon": {"preset": "goon"}, "papa": {}}
        return d

    def test_kids_mode_drops_fights_slaps_goons_and_bad_endings(self):
        sp, _ = write.clean(self.draft(), self.base, "happy", kids=True)
        acts = {b["do"] for b in sp["beats"] if "do" in b}
        self.assertFalse(acts & set(write.KIDS_BANNED), acts & set(write.KIDS_BANNED))
        self.assertIn("facepalm", acts)                                   # the harmless gestures stay
        self.assertEqual([b["end"] for b in sp["beats"] if "end" in b], ["happy"])
        self.assertEqual(sp.get("audience"), "kids")

    def test_the_same_draft_is_unchanged_for_everyone_else(self):
        sp, _ = write.clean(self.draft(), self.base, "funny")
        acts = {b["do"] for b in sp["beats"] if "do" in b}
        self.assertTrue({"slap", "push"} <= acts)
        self.assertNotIn("audience", sp)

    def test_kids_variety_hint_has_no_slaps_or_goons(self):
        import random
        for n in range(40):
            hint = write.variety_hint(random.Random(n), kids=True)
            self.assertNotIn("slap", hint)
            self.assertNotIn("push", hint)
            self.assertNotIn('"goon"', hint)

    def test_the_prompt_for_kids_forbids_the_unsafe_things(self):
        for word in ("NEVER", "slap", "police", "romance", "hook", "catchphrase"):
            self.assertIn(word.lower(), write.KIDS_MODE.lower())

    def test_upload_text_tells_you_to_mark_it_made_for_kids(self):
        sys.path.insert(0, str(ROOT / "tools" / "story"))
        import text
        out = text.build({"audience": "kids", "upload": {"titles": ["A"], "description": "d", "hashtags": []}})
        self.assertIn("made for kids", out)


class WriterTests(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((ROOT / "story/screenplays/ep1_date_night.json").read_text(encoding="utf-8"))
        scratch = ROOT / "build" / "story-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        # Use inherited workspace permissions. Python 3.13's private Windows temp
        # ACL can exclude the restricted token that is running the tests.
        case_dir = scratch / ("case_" + uuid.uuid4().hex)
        case_dir.mkdir()
        self.assertTrue(case_dir.resolve().is_relative_to(scratch.resolve()))
        self.addCleanup(shutil.rmtree, case_dir)
        self.out = case_dir / "screenplay.json"
        self.summary = case_dir / "summary.md"

    def generate(self, answers=None, key="test-key", idea="Babu police se paidal bhag raha hai", template="auto"):
        args = ["write.py", "--out", str(self.out), "--idea", idea, "--template", template]
        with patch.object(sys, "argv", args), patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(self.summary), "GITHUB_OUTPUT": ""}), \
                patch.object(write.gemini, "key", return_value=key), \
                patch.object(write.gemini, "write_json", side_effect=answers) as api, \
                contextlib.redirect_stdout(io.StringIO()):
            result = write.main()
        return result, api.call_count

    def test_campus_idea_preserves_stunts_and_changes_visible_props(self):
        draft = {"episode": "MEDAL MISSION", "hook": "THE TRAIN IS HERE",
                 "mission": "SAVE THE COLLEGE MEDAL", "prize": "medal", "reveal_prop": "books",
                 "sub": "These are my books!", "tts": "These are my books!", "end_text": "THE VAN HAS THE MEDAL"}
        result, calls = self.generate([(draft, "mock-model")], idea="Save the college medal, reveal books",
                                      template="campus_action")
        self.assertEqual((result, calls), (0, 1))
        saved = json.loads(self.out.read_text(encoding="utf-8"))
        self.assertEqual((saved["scene"], saved["prize"], saved["reveal_prop"]),
                         ("campus_action", "medal", "books"))
        self.assertEqual(next(b["sub"] for b in saved["beats"] if "say" in b), draft["sub"])
        self.assertIn("train_horn", [b.get("sfx") for b in saved["beats"]])
        self.assertIn("blast_hit", [b.get("sfx") for b in saved["beats"]])

    def test_campus_rejects_unsupported_prop_without_replaying_demo(self):
        draft = {"episode": "MEDAL MISSION", "hook": "THE TRAIN IS HERE",
                 "mission": "SAVE THE COLLEGE MEDAL", "prize": "medal", "reveal_prop": "robot",
                 "sub": "That is a robot!", "tts": "That is a robot!", "end_text": "THE VAN HAS THE MEDAL"}
        result, calls = self.generate([(draft, "mock-model")] * 2, idea="Reveal a robot", template="campus_action")
        self.assertEqual(calls, 2)
        self.assertIn("wrong bag", self.assert_failed(result)["reason"])

    def assert_failed(self, result):
        self.assertEqual(result, 1)
        self.assertFalse(self.out.exists(), "a failed AI run must not produce any screenplay")
        error = json.loads((self.out.parent / "generation_error.json").read_text(encoding="utf-8"))
        self.assertFalse(error["fallback_used"])
        self.assertIn("No video was recorded", self.summary.read_text(encoding="utf-8"))
        return error

    def test_missing_key_never_uses_saved_episode(self):
        self.out.write_text("old screenplay", encoding="utf-8")
        result, calls = self.generate(key="")
        error = self.assert_failed(result)
        self.assertIn("No Gemini API key", error["reason"])
        self.assertEqual(calls, 0)

    def test_quota_failure_never_uses_saved_episode(self):
        result, _ = self.generate([RuntimeError("429 quota exhausted")])
        self.assertIn("quota", self.assert_failed(result)["reason"])

    def test_wrong_story_is_retried_then_rejected(self):
        result, calls = self.generate([(draft(False), "model")] * 2)
        self.assertEqual(calls, 2)
        self.assertIn("on-foot police chase is missing", self.assert_failed(result)["reason"])

    def test_corrected_retry_is_used(self):
        result, calls = self.generate([(draft(False), "model"), (draft(), "model")])
        self.assertEqual((result, calls), (0, 2))
        saved = json.loads(self.out.read_text(encoding="utf-8"))
        self.assertEqual(saved["writer"], "model")
        self.assertIn("paidal", saved["creator_idea"])
        self.assertEqual(saved["props"], [])

    def test_unsupported_request_is_explained(self):
        result, _ = self.generate([({"unsupported_reason": "Rooftop jumping is unavailable"}, "model")])
        self.assertIn("Rooftop jumping", self.assert_failed(result)["reason"])

    def test_malformed_answers_fail_cleanly(self):
        result, calls = self.generate([({"props": 5}, "model")] * 2)
        self.assertEqual(calls, 2)
        self.assertIn("malformed", self.assert_failed(result)["reason"])

    def test_unknown_action_cannot_silently_disappear(self):
        ai = draft()
        ai["beats"].insert(0, {"do": "fly_over_building"})
        result, _ = self.generate([(ai, "model")] * 2)
        self.assertIn("unknown action", self.assert_failed(result)["reason"])

    def test_police_becomes_visible_without_using_side_cast_slot(self):
        sp, issues = write.clean(draft(), self.base, "action")
        self.assertEqual(issues, [])
        self.assertIn("badge", sp["cast"]["police"]["look"]["acc"])
        self.assertNotIn("radio", sp["cast"]["police"])
        self.assertNotIn("look", self.base["cast"]["police"], "must not mutate the original car episode")

    def test_car_start_parks_and_exits_before_foot_chase(self):
        sp, issues = write.clean(draft(on_foot=False), self.base, "action")
        self.assertEqual(issues, [])
        actions = [b["do"] for b in sp["beats"] if "do" in b]
        self.assertEqual(actions, ["park", "exit_car", "foot_chase"])

    def test_ending_waits_for_chase_and_dialogue_can_overlap(self):
        sp, _ = write.clean(draft(), self.base, "action")
        beats = sp["beats"]
        chase = next(i for i, b in enumerate(beats) if b.get("do") == "foot_chase")
        end = next(i for i, b in enumerate(beats) if "end" in b)
        self.assertIn("say", beats[chase + 1])
        self.assertEqual(beats[end - 1]["wait_for"], "foot_chase_done")

    def test_car_actions_on_foot_are_validation_errors(self):
        ai = draft()
        ai["beats"].insert(0, {"do": "police"})
        result, _ = self.generate([(ai, "model")] * 2)
        self.assertIn("while the car is parked", self.assert_failed(result)["reason"])

    def test_explicit_wait_is_not_duplicated(self):
        ai = draft()
        ai["beats"].insert(-2, {"wait_for": "foot_chase_done"})
        sp, _ = write.clean(ai, self.base, "action")
        self.assertEqual(sum(b.get("wait_for") == "foot_chase_done" for b in sp["beats"]), 1)

    def test_foot_chase_cannot_be_a_token_addition_to_a_car_story(self):
        ai = draft()
        ai["beats"].insert(-2, {"do": "go"})
        result, _ = self.generate([(ai, "model")] * 2)
        self.assertIn("vehicle chase", self.assert_failed(result)["reason"])

    def test_requested_runner_must_be_preserved(self):
        result, _ = self.generate([(draft(), "model")] * 2, idea="Shona police se paidal bhag rahi hai")
        self.assertIn("runner is shona", self.assert_failed(result)["reason"])

    def test_intent_languages_and_template(self):
        for idea in ["Babu police se paidal bhag raha hai", "Shona runs from cops", "पुलिस से पैदल भागता बाबू"]:
            self.assertTrue(write.needs_foot_chase(idea), idea)
        self.assertFalse(write.needs_foot_chase("Police chase the pink car"))
        self.assertFalse(write.needs_foot_chase("Babu police se gaadi bhaga raha hai"))
        self.assertFalse(write.needs_foot_chase("Babu and Shona walk to the chai stall"))
        self.assertTrue(write.needs_foot_chase("", "police_foot_chase"))


class SceneTests(unittest.TestCase):
    def setUp(self):
        self.base = json.loads((ROOT / "story/screenplays/ep1_date_night.json").read_text(encoding="utf-8"))

    def test_short_sketch_locations_and_reaction(self):
        for location in ("college_gate", "bus_stop", "park"):
            ai = {"format": "short", "start_on_foot": True, "start_spot": location,
                  "cast": {"babu": {"name": "A", "look": {"style": "boy", "shirt": "#2266ee"}},
                           "shona": {"name": "B", "look": {"style": "girl", "shirt": "#ffdc22"}}},
                  "beats": [{"say": "babu", "sub": "Why did you block me?"},
                            {"say": "shona", "sub": "Too many good morning messages!"},
                            {"do": "reaction", "who": "babu", "effect": "shock_freeze", "dur": 1.2},
                            {"end": "happy"}]}
            sp, issues = write.clean(ai, self.base, "funny")
            self.assertEqual(issues, [])
            self.assertEqual(sp["start_spot"], location)
            self.assertEqual(sp["cast"]["babu"]["name"], "A")
            self.assertEqual(sp["cast"]["shona"]["look"]["shirt"], "#ffdc22")
            reaction = next(i for i, b in enumerate(sp["beats"]) if b.get("do") == "reaction")
            self.assertEqual(sp["beats"][reaction + 1], {"wait": 1.2})

    def test_unknown_reaction_is_rejected(self):
        ai = draft()
        ai["beats"].insert(0, {"do": "reaction", "who": "babu", "effect": "teleport"})
        _, issues = write.clean(ai, self.base, "funny")
        self.assertIn("unsupported reaction actor or effect", issues)


class RecordingTests(unittest.TestCase):
    def test_catch_must_really_happen(self):
        log = {"end": 40, "events": [{"type": k} for k in ["foot_chase_started", "foot_caught", "foot_chase_done"]]}
        self.assertEqual(verify.problems(draft(), log), [])
        log["events"][1]["type"] = "foot_escaped"
        self.assertTrue(verify.problems(draft(), log))

    def test_missing_chase_and_incomplete_video_fail(self):
        self.assertTrue(verify.problems(draft(), {"end": -1, "events": []}))

    def test_script_errors_fail_even_with_complete_log(self):
        self.assertTrue(verify.problems(draft(False), {"end": 40}, "SCRIPT ERROR: invalid call"))


if __name__ == "__main__":
    unittest.main()
