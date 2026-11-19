"""Verify a normal-speed turn and physical ramp crossing from wheel telemetry."""

import argparse
import json
import math
import statistics
from pathlib import Path

START = 1.0
END = 11.0


def speed(sample):
    vx, _, vz = sample["velocity"]
    return math.hypot(vx, vz) * 3.6


def verify(data):
    frames = [s for s in data["samples"] if START <= s["t"] <= END]
    if len(frames) < 150 or frames[-1]["t"] < END - 0.12:
        raise ValueError("Incomplete physics or camera telemetry.")
    if any(abs(s["time_scale"] - 1) > 1e-5 for s in frames):
        raise ValueError("The engine entered slow motion.")
    x0, _, zs = data["ramp_start"]
    lip, _, _ = data["ramp_lip"]
    ramp = [s for s in frames if lip + 1 < s["position"][0] < x0 - 2
            and abs(s["position"][2] - zs) < 2.5
            and s["contacts"] >= 1 and s["position"][1] > 1.15]
    if len(ramp) < 2:
        raise ValueError("The wheels never climbed the ramp while in contact.")
    takeoff = next((s for s in frames if s["t"] > ramp[0]["t"] and s["contacts"] == 0
                    and abs(s["position"][0] - lip) < 8 and s["velocity"][1] > 0.8
                    and s["position"][1] > 2.3 and s["airtime"] > 0.08), None)
    if takeoff is None:
        raise ValueError("No launch from the ramp lip with upward velocity.")
    landing = next((s for s in frames if s["t"] > takeoff["t"] + 0.30 and s["contacts"] >= 2
                    and s["position"][0] < lip - 7 and s["position"][1] < 1.15), None)
    if landing is None:
        raise ValueError("No landing beyond the ramp with the wheels back on the ground.")
    if not any(s["velocity"][2] < -7 for s in frames if s["t"] < takeoff["t"]) or not any(
            s["velocity"][0] < -15 for s in frames if s["t"] < takeoff["t"]):
        raise ValueError("The clip did not capture the turn into the ramp lane.")
    post_turn = [s for s in frames if s["position"][0] < -18 and s["t"] <= landing["t"]]
    median = statistics.median(speed(s) for s in post_turn)
    peak = max(map(speed, frames))
    if median < 65 or speed(takeoff) < 70:
        raise ValueError(f"Approach is too slow: {median:.0f} km/h median, {speed(takeoff):.0f} at takeoff.")
    if not all(s["in_frame"] for s in frames if ramp[0]["t"] <= s["t"] <= landing["t"]):
        raise ValueError("The car went out of shot during the jump.")
    if not any(s["police_in_frame"] for s in frames):
        raise ValueError("The police car never appeared in the chase shot.")
    return {"preview_start_s": START, "duration_s": END - START, "peak_kmh": round(peak, 1),
            "post_turn_median_kmh": round(median, 1), "takeoff_kmh": round(speed(takeoff), 1),
            "ramp_climb_s": round(ramp[0]["t"] - START, 2), "takeoff_s": round(takeoff["t"] - START, 2),
            "landing_s": round(landing["t"] - START, 2)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("telemetry", type=Path)
    parser.add_argument("summary", type=Path)
    args = parser.parse_args()
    try:
        result = verify(json.loads(args.telemetry.read_text()))
    except ValueError as exc:
        parser.exit(1, f"{exc}\n")
    result_text = json.dumps(result, indent=2) + "\n"
    args.summary.write_text(result_text)
    print(result_text, end="")


if __name__ == "__main__":
    main()
