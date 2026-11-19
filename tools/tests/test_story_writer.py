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

    def generate(self, answers=None, key="test-key", idea="Babu police se paidal bhag raha hai"):
        args = ["write.py", "--out", str(self.out), "--idea", idea]
        with patch.object(sys, "argv", args), patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(self.summary), "GITHUB_OUTPUT": ""}), \
                patch.object(write.gemini, "key", return_value=key), \
                patch.object(write.gemini, "write_json", side_effect=answers) as api, \
                contextlib.redirect_stdout(io.StringIO()):
            result = write.main()
        return result, api.call_count

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
