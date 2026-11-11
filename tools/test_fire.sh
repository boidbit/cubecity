#!/usr/bin/env bash
# Headless test for burning cars (tools/tests/fire_test.gd): the stages by health, a car on fire
# that loses health and does not mend itself, a repair that puts it out, wrecks that burn on, and
# the budget that keeps a pile of burning wrecks cheap.
# Takes about 30 s.
# Usage: tools/test_fire.sh <godot binary> [out dir]
exec "$(dirname "$0")/run_test.sh" "$1" fire "${2:-test-out}"
