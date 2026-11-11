#!/usr/bin/env bash
# Headless physics test for street lamps and trees (tools/tests/props_test.gd): hitting one must
# slow the car a bit, never stop it, and a lamp a metre away must not be hit at all.
# Needs no graphics card and takes about 15 s.
# Usage: tools/test_props.sh <godot binary> [out dir]
exec "$(dirname "$0")/run_test.sh" "$1" props "${2:-test-out}"
