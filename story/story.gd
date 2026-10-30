extends Node
# Story lab (experiment). Started with "-- --bot=chase --story=<screenplay.json>": two
# blocky characters sit in the player's car and talk while the usual bot chase goes on
# around them. Everything lives under res://story and reads the game; the only thing
# the game itself does is create this node (one line in main.gd) when --story is given.
#
# Screenplay (JSON, see story/screenplays):
#   lines      play in order, one after another
#   reactions  one-off lines that fire when the chase produces an event (big_air, near_miss,
#              cop_wrecked ...); "interrupt": true cuts the line in progress
#   dur / env  per line, filled in by tools/story/voices.py (voice length, loudness curve)
# The real start time of every line is written to --story_log, so tools/story/mix.py can
# lay the voices over the video at the right moments.

const Rig := preload("res://story/rig.gd")
const Roadster := preload("res://story/roadster.gd")
const DEFAULT_SCREENPLAY := "res://story/screenplays/ep1_date_night.json"
const INTRO := 2.6          # the opening drone shot; the title card sits on it
const END_HOLD := 3.4       # seconds the end card stays after the last line
const REACT_COOLDOWN := 3.5
const REACT_MAX_WAIT := 2.4

var main
var data := {}
var rigs := {}                   # who -> rig
var wheel: Node3D
var lines: Array = []
var reactions: Array = []
var queue: Array = []            # reactions waiting for their turn
var idx := 0
var cur := {}
var cur_start := 0.0
var cur_end := 0.0
var cur_is_reaction := false
var last_end := -9.0
var last_react := -9.0
var start_t := 2.8
var gap := 0.3
var ev_seen := 0
var played: Array = []
var log_path := ""
var done := false
var done_t := 0.0
var shot := "two"
var forced_shot := ""       # --story_shot=two|close|side|behind: for testing one camera angle
var shot_who := ""
var shot_i := 0
var shot_fov := 52.0
var cam_on := false
var cam_new := true
var cam_pos := Vector3.ZERO
var cam_fov := 50.0

var ui_name: Label
var ui_sub: Label
var ui_title: Label
var ui_ep: Label
var ui_end: Label
var ui_scale := 1.0


func setup(main_node, cfg: Dictionary) -> void:
	main = main_node
	log_path = str(cfg.get("story_log", ""))
	forced_shot = str(cfg.get("story_shot", ""))
	var path := str(cfg.get("story", ""))
	if path == "" or path == "1":
		path = DEFAULT_SCREENPLAY
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("STORY no screenplay at ", path)
		queue_free()
		return
	data = parsed
	lines = data.get("lines", [])
	reactions = data.get("reactions", [])
	start_t = float(data.get("start", start_t))
	gap = float(data.get("gap", gap))
	_dress_car()
	_make_cast()
	_make_ui()
	main.hud.visible = false
	print("STORY ", data.get("title", ""), " lines=", lines.size(), " reactions=", reactions.size())


# ------------------------------------------------------------ set dressing

func _dress_car() -> void:
	var pl: Car = main.player
	var bmi: MeshInstance3D = pl.vis.get_child(0)
	bmi.mesh = Roadster.mesh()
	var car: Dictionary = data.get("car", {})
	var col := Color.from_string(str(car.get("color", "#ff5c9a")), Color(1.0, 0.36, 0.6))
	pl.mat_body.set_shader_parameter("color", col)
	pl.body_color = col
	# a soft light over the seats so the faces read at dusk and at night
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 0.5)
	lamp.omni_range = 4.5
	lamp.light_energy = 0.3
	lamp.shadow_enabled = false
	pl.vis.add_child(lamp)


func _make_cast() -> void:
	var pl: Car = main.player
	var cast: Dictionary = data.get("cast", {})
	for who: String in cast:
		var c: Dictionary = cast[who]
		var is_driver := str(c.get("seat", "passenger")) == "driver"
		var x: float = Roadster.SEAT_X if is_driver else -Roadster.SEAT_X
		var r := Rig.new()
		pl.vis.add_child(r)
		r.position = Vector3(x, Roadster.SEAT_Y, Roadster.SEAT_Z)
		r.build(who, c.get("look", {}), is_driver, x)
		rigs[who] = r
		if is_driver:
			wheel = Roadster.make_wheel(pl.vis, x)


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	ui_scale = vs.x / 1080.0 if main.vertical else vs.x / 1920.0 * 1.5
	ui_name = _label(layer, 40, 10, Vector2(0.5, 0.0))
	ui_sub = _label(layer, 56, 14, Vector2(0.5, 0.0))
	ui_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_sub.custom_minimum_size = Vector2(vs.x * 0.88, 0)
	ui_sub.size = Vector2(vs.x * 0.88, 10)
	ui_sub.position = Vector2(vs.x * 0.06, vs.y * 0.7)
	ui_name.position = Vector2(vs.x * 0.06, vs.y * 0.7 - 70.0 * ui_scale)
	ui_title = _label(layer, 110, 20, Vector2.ZERO)
	ui_title.text = str(data.get("title", ""))
	ui_title.size = Vector2(vs.x, 140.0 * ui_scale)
	ui_title.position = Vector2(0, vs.y * 0.2)
	ui_ep = _label(layer, 48, 12, Vector2.ZERO)
	ui_ep.text = str(data.get("episode", ""))
	ui_ep.size = Vector2(vs.x, 70.0 * ui_scale)
	ui_ep.position = Vector2(0, vs.y * 0.2 + 150.0 * ui_scale)
	ui_end = _label(layer, 70, 16, Vector2.ZERO)
	ui_end.text = str(data.get("end_text", ""))
	ui_end.size = Vector2(vs.x, 100.0 * ui_scale)
	ui_end.position = Vector2(0, vs.y * 0.4)
	ui_end.modulate.a = 0.0
	ui_name.visible = false
	ui_sub.visible = false


func _label(parent: Node, size: int, outline: int, _unused: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", int(size * ui_scale))
	l.add_theme_constant_override("outline_size", int(outline * ui_scale))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ------------------------------------------------------------ frame loop

func _process(dt: float) -> void:
	var t: float = main.clock
	_collect_events(t)
	_schedule(t)
	_animate(dt, t)
	_camera(dt, t)
	_ui(t)


func _est_dur(line: Dictionary) -> float:
	return clampf(0.075 * str(line.get("sub", "")).length(), 1.2, 6.0)


# Chase events can trigger a reaction line (each one only once).
func _collect_events(t: float) -> void:
	while ev_seen < main.events.size():
		var kind: String = main.events[ev_seen]["type"]
		ev_seen += 1
		# no reactions until the story has got going (the first two lines are the hook)
		if done or idx < 2 or t - last_react < REACT_COOLDOWN:
			continue
		for r: Dictionary in reactions:
			if str(r.get("on", "")) != kind or r.get("used", false):
				continue
			r["used"] = true
			r["queued_at"] = t
			last_react = t
			# a scream may cut a line short, but only one that is mostly said already
			if r.get("interrupt", false) and not cur.is_empty() and not cur_is_reaction \
					and t - cur_start > 0.5 * (cur_end - cur_start):
				_end_line(t, true)
			queue.append(r)
			break


func _schedule(t: float) -> void:
	if not cur.is_empty():
		if t >= cur_end:
			_end_line(t, false)
		return
	# reactions wait for the line in progress, but go stale if it takes too long
	while not queue.is_empty() and t - float(queue[0]["queued_at"]) > REACT_MAX_WAIT:
		queue.pop_front()
	if not queue.is_empty():
		if t - last_end >= 0.12:
			_start_line(queue.pop_front(), t, true)
		return
	if idx < lines.size():
		if t >= start_t and t - last_end >= gap:
			idx += 1
			_start_line(lines[idx - 1], t, false)
	elif not done and t - last_end > 0.2:
		done = true
		done_t = t
		var dir = main.director
		if dir != null:
			dir.duration = minf(dir.duration, t + END_HOLD)
		_write_log()


func _start_line(line: Dictionary, t: float, is_reaction: bool) -> void:
	cur = line
	cur_is_reaction = is_reaction
	cur_start = t
	cur_end = t + float(line.get("dur", _est_dur(line)))
	var who := str(line.get("who", ""))
	var cast: Dictionary = data.get("cast", {})
	var c: Dictionary = cast.get(who, {})
	for k: String in rigs:
		var r: Rig = rigs[k]
		if k == who:
			r.set_state(str(line.get("emotion", "neutral")), str(line.get("gesture", "talk")), true)
		else:
			r.set_state(str(line.get("react", "neutral")), "idle", false)
	played.append({"id": str(line.get("id", "")), "t": snappedf(t, 0.01)})
	_write_log()
	shot_who = who
	shot = ["two", "close", "side", "close", "behind", "close"][shot_i % 6]
	if is_reaction:
		shot = "close"
	if forced_shot != "":
		shot = forced_shot
	shot_i += 1
	cam_new = true
	ui_name.text = str(c.get("name", who.to_upper()))
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color.from_string(str(c.get("color", "#ffffff")), Color.WHITE)
	chip.set_corner_radius_all(int(18 * ui_scale))
	chip.content_margin_left = 26.0 * ui_scale
	chip.content_margin_right = 26.0 * ui_scale
	chip.content_margin_top = 4.0 * ui_scale
	chip.content_margin_bottom = 4.0 * ui_scale
	ui_name.add_theme_stylebox_override("normal", chip)
	ui_sub.text = str(line.get("sub", ""))
	ui_name.visible = true
	ui_sub.visible = true
	print("STORYLINE ", line.get("id", ""), " t=", snappedf(t, 0.01), " ", who)



func _end_line(t: float, cut: bool) -> void:
	if cut and not played.is_empty():
		played[played.size() - 1]["cut"] = snappedf(t - cur_start, 0.01)
		_write_log()
	cur = {}
	last_end = t
	ui_name.visible = false
	ui_sub.visible = false
	for k: String in rigs:
		var r: Rig = rigs[k]
		r.speaking = false


func _write_log() -> void:
	if log_path == "":
		return
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa == null:
		return
	fa.store_string(JSON.stringify({"lines": played, "end": snappedf(done_t, 0.01) if done else -1.0}))
	fa.close()


# ------------------------------------------------------------ characters

func _animate(dt: float, t: float) -> void:
	var talking := not cur.is_empty()
	var env: Array = cur.get("env", [])
	for k: String in rigs:
		var r: Rig = rigs[k]
		var target := 1.0 if (talking or t - last_end < 0.6) else 0.0
		r.look = move_toward(r.look, target, 4.0 * dt)
		if r.speaking:
			var i := int((t - cur_start) * 20.0)
			if i < env.size():
				r.mouth = clampf(float(env[i]) * 1.5, 0.0, 1.0)
			elif env.is_empty():
				r.mouth = 0.5 + 0.5 * sin(t * 13.0)
			else:
				r.mouth = 0.0
		else:
			r.mouth = 0.0
			if t - last_end > 0.7 and r.emotion != "neutral":
				r.set_state("neutral", "idle", false)
		r.update(dt, null)
	if wheel != null:
		wheel.rotation.y = -main.player.steer_smooth * 1.8


# ------------------------------------------------------------ camera

# While somebody talks the camera rides with the car and films the speaker; between lines,
# in the air and during the opening drone shot it is left to the game's own director.
func _camera(dt: float, t: float) -> void:
	var pl: Car = main.player
	var want := (not cur.is_empty() or t - last_end < 0.45) and not done and t > INTRO
	if pl.airtime > 0.0 or main.cine_t > 0.0 or main.game_over:
		want = false
	if not want:
		if cam_on:
			cam_on = false
			main.cam_cut = true
		return
	cam_on = true
	var cam: Camera3D = main.cam
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var base := pl.global_position
	var pos := Vector3.ZERO
	var look_at_p := Vector3.ZERO
	match shot:
		"close":
			var r: Rig = rigs.get(shot_who, null)
			var hp: Vector3 = r.head.global_position + Vector3(0, 0.27, 0) if r != null else base + Vector3(0, 1.9, 0)
			var sx: float = r.seat_x if r != null else 0.0
			pos = hp + fwd * 2.9 + right * sx * 1.3 + Vector3(0, 0.1, 0)
			look_at_p = hp + right * sx * -0.35
			shot_fov = 42.0
		"side":
			pos = base + right * 3.1 + fwd * 0.9 + Vector3(0, 1.9, 0)
			look_at_p = base + Vector3(0, 1.85, 0.0)
			shot_fov = 50.0
		"behind":
			pos = base - fwd * 3.8 + Vector3(0, 2.9, 0)
			look_at_p = base + fwd * 2.5 + Vector3(0, 1.7, 0)
			shot_fov = 56.0
		_:
			pos = base + fwd * 4.4 + right * 0.5 + Vector3(0, 2.5, 0)
			look_at_p = base + Vector3(0, 1.85, 0)
			shot_fov = 50.0
	# never film from inside a wall
	var from := base + Vector3(0, 1.6, 0)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, pos, 1))
	if not hit.is_empty():
		pos = (hit["position"] as Vector3) + (from - pos).normalized() * 0.5
	pos += Vector3(sin(t * 2.3), sin(t * 3.1), sin(t * 1.7)) * 0.012
	# the game's own camera has already moved the camera this frame, so smooth from our own state
	cam_pos = pos if cam_new else cam_pos.lerp(pos, 1.0 - exp(-20.0 * dt))
	cam_fov = shot_fov if cam_new else lerpf(cam_fov, shot_fov, 1.0 - exp(-8.0 * dt))
	cam.global_position = cam_pos
	cam.look_at(look_at_p, Vector3.UP)
	cam.fov = cam_fov
	cam_new = false


# ------------------------------------------------------------ overlay

func _ui(t: float) -> void:
	var a := 1.0 if t < 1.8 else clampf(1.0 - (t - 1.8) / 0.8, 0.0, 1.0)
	ui_title.modulate.a = a
	ui_ep.modulate.a = a
	if done:
		ui_end.modulate.a = clampf((t - done_t) / 0.6, 0.0, 1.0)
