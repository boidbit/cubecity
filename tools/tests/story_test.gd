extends SceneTree
# Real scene regression: both leads, capture and escape, moving rigs and a tracking camera.
# tools/run_test.sh GODOT story smoke-out --bot=chase --duration=180 --story=res://story/screenplays/ep7_foot_chase.json

const Story := preload("res://story/story.gd")
var failures := {}
var passed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures[label] = true
		print("FAIL ", label)


func _run() -> void:
	for cfg: Dictionary in [{"runner": "babu", "outcome": "caught"}, {"runner": "shona", "outcome": "escape"}]:
		await _case(cfg)
	print("RESULT: %d cases completed, %d failures" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _case(cfg: Dictionary) -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	var story = null
	for child in main.get_children():
		if child.get_script() == Story:
			story = child
	if story == null:
		check(false, "story fixture was loaded (pass --bot and --story)")
		main.queue_free()
		await process_frame
		return
	story.start_t = 0.2
	story.gap = 0.05
	story.line_gap = 0.05
	for beat: Dictionary in story.beats:
		if beat.has("say"):
			beat["dur"] = 0.25
			beat["emotion"] = "neutral"
			beat["react"] = "neutral"
		elif beat.get("do") == "foot_chase":
			beat["to"] = cfg["runner"]
			beat["outcome"] = cfg["outcome"]
			beat["dur"] = 4.0
	var runner = story._rig_of(cfg["runner"])
	var officer = story._rig_of("police")
	var runner_start: Vector3 = runner.global_position
	var officer_start := Vector3.INF
	var car_start: Vector3 = main.player.global_position
	var samples := 0
	var seen := false
	var officer_travel := 0.0
	for frame in 1800:
		await process_frame
		if not story.act.foot_chase.is_empty():
			if not seen:
				seen = true
				officer_start = officer.global_position
			officer_travel = maxf(officer_travel, officer_start.distance_to(officer.global_position))
			check(runner.visible and officer.visible and not runner.seated and not officer.seated, "both chase actors are visible and on foot")
			check(main.alive_police() == 0, "no police cars substitute for the foot chase")
			for r in [runner, officer]:
				var along: float = story.street.along(r.global_position)
				check(along >= story.street.lo - 0.2 and along <= story.street.hi + 0.2, "actors remain on this block's pavement")
			if main.clock - float(story.act.foot_chase["t0"]) > 0.6:
				samples += 1
				check(main.cam.is_position_in_frustum(runner.head.global_position), "runner stays in camera frame")
				check(main.cam.is_position_in_frustum(officer.head.global_position), "pursuing officer stays in camera frame")
		if story.done:
			break
	check(story.done, "story finishes before timeout")
	check(seen and samples > 30, "chase runs across multiple rendered frames")
	check(runner_start.distance_to(runner.global_position) > 5.0, "runner actually moves")
	check(officer_travel > 4.0, "officer actually follows the runner")
	check(car_start.distance_to(main.player.global_position) < 2.0, "the player's car stays parked")
	var expected := "foot_caught" if cfg["outcome"] == "caught" else "foot_escaped"
	var results: Array = story.ev_log.filter(func(e: Dictionary) -> bool: return e["type"] in ["foot_caught", "foot_escaped"])
	check(results.size() == 1 and results[0]["type"] == expected, "requested outcome: " + expected)
	if cfg["outcome"] == "caught":
		check(runner.global_position.distance_to(officer.global_position) <= 1.4, "capture requires the officer to reach the runner")
	else:
		check(officer.pose == "kneel", "escaping runner leaves the officer out of breath")
	check(story.act.foot_chase.is_empty() and runner.arrived() and officer.arrived(), "chase motion is cleaned up")
	passed += 1
	print("PASS completed ", cfg["runner"], " / ", cfg["outcome"])
	main.queue_free()
	await process_frame
	Engine.time_scale = 1.0
