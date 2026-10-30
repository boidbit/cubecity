extends Node
# Story lab (experiment). Started with "-- --bot=chase --story=<screenplay.json>": two
# blocky characters drive around in the player's car and act out a screenplay. The
# director runs in "scripted" mode: nothing happens by itself, the police, the
# helicopter or a jump only show up when the screenplay asks for them (cue()).
# Everything lives under res://story; the game only creates this node when --story is given.
#
# Screenplay (JSON, see story/screenplays and tools/story/write.py). "beats" run in order:
#   {"say": who, "sub", "tts", "emotion", "react", "gesture", "on"}   a line of dialogue
#        "on": wait (up to "max_wait" s) for a chase event first: takeoff, big_air (landing),
#              prop_fly, near_miss, cop_wrecked, roadblock
#   {"do": action, ...}   police (stars), calm, heli, heli_off, jump, roadblock, crossers,
#                         boom, swat, prop_show / prop_fly / prop_hide (prop), slowmo, stop, go
#   {"wait": seconds}  {"wait_for": event, "max_wait": s}
#   {"end": "happy" | "caught" | "crash" | "cliffhanger"}   the ending; lines after it play
#                         once the ending scene is set (the car has stopped ...)
# "dur" and "env" (voice length, loudness curve for the mouth) are filled in by
# tools/story/voices.py. The start time of every line goes to --story_log for tools/story/mix.py.
# Old screenplays with "lines" / "reactions" still play.

const Rig := preload("res://story/rig.gd")
const Roadster := preload("res://story/roadster.gd")
const Props := preload("res://story/props.gd")
const DEFAULT_SCREENPLAY := "res://story/screenplays/ep1_date_night.json"
const INTRO := 2.6          # the opening drone shot; the title card sits on it
const END_HOLD := 3.4       # seconds the end card stays after the last line
const REACT_COOLDOWN := 3.5
const REACT_MAX_WAIT := 2.4
const ACTION_TRIES := 14.0  # seconds a cue keeps trying (the car may need to reach a ramp)

var main
var data := {}
var cast := {}
var rigs := {}                   # who -> rig
var wheel: Node3D
var props := {}                  # kind -> Node3D in the car
var beats: Array = []
var reactions: Array = []
var queue: Array = []            # reactions waiting for their turn
var bi := 0                      # next beat
var said := 0                    # lines started so far
var cur := {}
var cur_start := 0.0
var cur_end := 0.0
var cur_is_reaction := false
var last_end := -9.0
var last_react := -9.0
var wait_until := 0.0
var start_t := 2.8
var gap := 0.3
var ev_seen := 0
var ev_log: Array = []           # [{"type", "t"}]
var airborne := false
var pending: Array = []          # cues still trying: {"kind", "arg", "until", "prop"}
var played: Array = []
var acted: Array = []
var log_path := ""
var done := false
var done_t := 0.0
var ending := ""
var end_t := 0.0
var end_ready := false
var stop_car := false
var flying: RigidBody3D = null
var prop_shot_until := 0.0
var shot := "two"
var forced_shot := ""       # --story_shot=two|close|side|behind: for testing one camera angle
var shot_who := ""
var shot_i := 0
var shot_fov := 52.0
var cam_on := false
var cam_new := true
var cam_pos := Vector3.ZERO
var cam_fov := 50.0
var orbit_a := 0.0

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
	cast = data.get("cast", {})
	beats = data.get("beats", [])
	if beats.is_empty():
		for l: Dictionary in data.get("lines", []):
			var b := l.duplicate()
			b["say"] = b.get("who", "")
			beats.append(b)
	reactions = data.get("reactions", [])
	start_t = float(data.get("start", start_t))
	gap = float(data.get("gap", gap))
	_dress_car()
	_make_cast()
	_make_ui()
	for k: String in data.get("props", []):
		_prop_show(k)
	main.hud.visible = false
	print("STORY ", data.get("title", ""), " beats=", beats.size(), " reactions=", reactions.size())


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
	for who: String in cast:
		var c: Dictionary = cast[who]
		var seat := str(c.get("seat", ""))
		if seat != "driver" and seat != "passenger":
			continue        # voices only (the police on the radio)
		var is_driver := seat == "driver"
		var x: float = Roadster.SEAT_X if is_driver else -Roadster.SEAT_X
		var r := Rig.new()
		pl.vis.add_child(r)
		r.position = Vector3(x, Roadster.SEAT_Y, Roadster.SEAT_Z)
		r.build(who, c.get("look", {}), is_driver, x)
		rigs[who] = r
		if is_driver:
			wheel = Roadster.make_wheel(pl.vis, x)


func _prop_show(kind: String) -> void:
	if props.has(kind) or not Props.KINDS.has(kind):
		return
	var n: Node3D = Props.build(kind)
	main.player.vis.add_child(n)
	n.position = Props.SLOTS[mini(props.size(), Props.SLOTS.size() - 1)]
	props[kind] = n


func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	ui_scale = vs.x / 1080.0 if main.vertical else vs.x / 1920.0 * 1.5
	ui_name = _label(layer, 40, 10)
	ui_sub = _label(layer, 56, 14)
	ui_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_sub.custom_minimum_size = Vector2(vs.x * 0.88, 0)
	ui_sub.size = Vector2(vs.x * 0.88, 10)
	ui_sub.position = Vector2(vs.x * 0.06, vs.y * 0.7)
	ui_name.position = Vector2(vs.x * 0.06, vs.y * 0.7 - 70.0 * ui_scale)
	ui_title = _label(layer, 110, 20)
	ui_title.text = str(data.get("title", ""))
	ui_title.size = Vector2(vs.x, 140.0 * ui_scale)
	ui_title.position = Vector2(0, vs.y * 0.2)
	ui_ep = _label(layer, 48, 12)
	ui_ep.text = str(data.get("episode", ""))
	ui_ep.size = Vector2(vs.x, 70.0 * ui_scale)
	ui_ep.position = Vector2(0, vs.y * 0.2 + 150.0 * ui_scale)
	ui_end = _label(layer, 70, 16)
	ui_end.text = str(data.get("end_text", ""))
	ui_end.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_end.size = Vector2(vs.x * 0.9, 100.0 * ui_scale)
	ui_end.position = Vector2(vs.x * 0.05, vs.y * 0.4)
	ui_end.modulate.a = 0.0
	ui_name.visible = false
	ui_sub.visible = false


func _label(parent: Node, size: int, outline: int) -> Label:
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
	_actions(t)
	_schedule(t)
	_ending(dt, t)
	_animate(dt, t)
	_camera(dt, t)
	_ui(t)


func _est_dur(line: Dictionary) -> float:
	return clampf(0.075 * str(line.get("sub", "")).length(), 1.2, 6.0)


func _event_since(kind: String, t0: float) -> bool:
	for e: Dictionary in ev_log:
		if str(e["type"]) == kind and float(e["t"]) >= t0:
			return true
	return false


# Chase events: remembered for "on" / "wait_for", and they can trigger a reaction line.
func _collect_events(t: float) -> void:
	# the game logs big_air on landing; the story also wants the moment the car takes off
	var air: bool = main.player.airtime > 0.15
	if air and not airborne:
		ev_log.append({"type": "takeoff", "t": t})
	airborne = air
	while ev_seen < main.events.size():
		var kind: String = main.events[ev_seen]["type"]
		ev_seen += 1
		ev_log.append({"type": kind, "t": t})
		# no reactions until the story has got going (the first two lines are the hook)
		if done or ending != "" or said < 2 or t - last_react < REACT_COOLDOWN:
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
	if t < start_t or t < wait_until or done:
		return
	while bi < beats.size():
		var b: Dictionary = beats[bi]
		if b.has("say"):
			if t - last_end < gap:
				return
			if ending != "" and not end_ready:
				return
			var on := str(b.get("on", ""))
			if on != "":
				if not b.has("_from"):
					b["_from"] = t
				var from: float = b["_from"]
				if not _event_since(on, from - 1.5) and t - from < float(b.get("max_wait", 9.0)):
					return
			bi += 1
			_start_line(b, t, false)
			return
		elif b.has("do"):
			bi += 1
			_do(b, t)
		elif b.has("wait"):
			bi += 1
			wait_until = t + clampf(float(b["wait"]), 0.0, 8.0)
			return
		elif b.has("wait_for"):
			if not b.has("_from"):
				b["_from"] = t
			var from2: float = b["_from"]
			if _event_since(str(b["wait_for"]), from2 - 1.5) or t - from2 > float(b.get("max_wait", 9.0)):
				bi += 1
				continue
			return
		elif b.has("end"):
			bi += 1
			_begin_ending(str(b["end"]), t)
		else:
			bi += 1
	if ending != "" and not end_ready:
		return
	if t - last_end > 0.2:
		_finish(t)


func _finish(t: float) -> void:
	done = true
	done_t = t
	var dir = main.director
	if dir != null:
		dir.duration = minf(dir.duration, t + END_HOLD)
	_write_log()


# ------------------------------------------------------------ actions

func _do(b: Dictionary, t: float) -> void:
	var kind := str(b["do"])
	var arg := float(b.get("stars", b.get("arg", 0.0)))
	acted.append({"do": kind, "t": snappedf(t, 0.01)})
	match kind:
		"prop_show":
			_prop_show(str(b.get("prop", "")))
		"prop_hide":
			var n: Node3D = props.get(str(b.get("prop", "")), null)
			if n != null:
				n.visible = false
		"prop_fly":
			# flies off when the car is in the air (or right away if there is no jump coming)
			pending.append({"kind": "prop_fly", "prop": str(b.get("prop", "")), "from": t, "until": t + 25.0})
		"slowmo":
			main.slowmo(1.6, 0.35)
		"stop":
			stop_car = true
		"go":
			stop_car = false
			main.bot.cruise = 26.0
		_:
			pending.append({"kind": kind, "arg": arg, "from": t, "until": t + ACTION_TRIES})
	print("STORYDO ", kind, " t=", snappedf(t, 0.01))


func _actions(t: float) -> void:
	var dir = main.director
	for a: Dictionary in pending.duplicate():
		var kind := str(a["kind"])
		var ok := false
		if kind == "prop_fly":
			# wait for the jump if one is on its way; otherwise it just flies off
			var jump_coming: bool = main.bot.busy() or pending.any(func(p: Dictionary) -> bool: return p["kind"] == "jump")
			ok = main.player.airtime > 0.12 or (t > float(a["from"]) + 2.0 and not jump_coming)
			if ok:
				_fly_prop(str(a.get("prop", "")), t)
		elif dir != null:
			var arg: float = t - float(a["from"]) if kind == "jump" else float(a.get("arg", 0.0))
			ok = dir.cue(kind, arg)
		if ok or t > float(a["until"]):
			pending.erase(a)
			print("STORYDO ", kind, " done" if ok else " could not happen", " t=", snappedf(t, 0.01),
				" plan=", main.bot.plan_name)


func _fly_prop(kind: String, t: float) -> void:
	var n: Node3D = props.get(kind, null)
	if n == null or not n.visible:
		return
	props.erase(kind)
	flying = Props.fly(n, main.player)
	prop_shot_until = t + 1.7
	main.slowmo(1.4, 0.4)
	cam_new = true
	main.log_event("prop_fly")


# ------------------------------------------------------------ endings

func _begin_ending(kind: String, t: float) -> void:
	ending = kind if kind in ["happy", "caught", "crash", "cliffhanger"] else "happy"
	end_t = t
	end_ready = false
	var dir = main.director
	var pl: Car = main.player
	match ending:
		"happy":
			if dir != null:
				dir.cue("calm")
			stop_car = true
		"caught":
			if dir != null:
				if main.alive_police() == 0:
					dir.cue("police", 2.0)
				dir.still = true
			stop_car = true
		"crash":
			# spin out, smoke, slow motion
			if dir != null:
				dir.still = true
				dir.cue("calm")
			var side := pl.global_transform.basis.x
			pl.apply_central_impulse(side * pl.mass * 6.0)
			pl.apply_torque_impulse(Vector3.UP * pl.mass * 9.0)
			pl.hp = minf(pl.hp, 22.0)
			pl._update_look()
			main.fx.crash(pl.global_position, 22.0)
			main.slowmo(2.2, 0.3)
			main.shake_cam(0.9)
			stop_car = true
		"cliffhanger":
			main.slowmo(8.0, 0.06)
			end_ready = true
	cam_new = true
	print("STORYEND ", ending, " t=", snappedf(t, 0.01))


func _ending(dt: float, t: float) -> void:
	if stop_car:
		main.bot.cruise = move_toward(main.bot.cruise, 0.0, 14.0 * dt)
		main.bot.drift_style = false
	if ending == "" or end_ready:
		return
	var pl: Car = main.player
	var stopped: bool = pl.speed < 1.5 and main.bot.cruise <= 0.1
	match ending:
		"caught":
			var near := false
			for c in main.police:
				if is_instance_valid(c) and not c.dead and c.global_position.distance_to(pl.global_position) < 14.0:
					near = true
			end_ready = (stopped and near) or t - end_t > 7.0
		_:
			end_ready = stopped or t - end_t > 6.0


# ------------------------------------------------------------ lines

func _start_line(line: Dictionary, t: float, is_reaction: bool) -> void:
	cur = line
	cur_is_reaction = is_reaction
	cur_start = t
	cur_end = t + float(line.get("dur", _est_dur(line)))
	said += 1
	var who := str(line.get("say", line.get("who", "")))
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
	if not rigs.has(who):
		shot = "police"
	elif ending in ["happy", "crash", "cliffhanger"] and end_ready:
		shot = ["orbit", "close", "orbit", "two"][shot_i % 4]
	elif ending == "caught":
		shot = ["two", "close", "police_wide"][shot_i % 3]
	elif main.alive_police() > 0:
		shot = ["two", "close", "behind", "close", "side", "close"][shot_i % 6]
	else:
		shot = ["two", "close", "side", "close", "two", "close"][shot_i % 6]
	if is_reaction:
		shot = "close"
	if forced_shot != "":
		shot = forced_shot
	shot_i += 1
	cam_new = true
	ui_name.text = str(c.get("name", who.to_upper()))
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color.from_string(str(c.get("color", "#2f6bff" if who == "police" else "#ffffff")), Color.WHITE)
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
	fa.store_string(JSON.stringify({"lines": played, "actions": acted, "ending": ending,
		"end": snappedf(done_t, 0.01) if done else -1.0}))
	fa.close()


# ------------------------------------------------------------ characters

func _animate(dt: float, t: float) -> void:
	var talking := not cur.is_empty()
	var env: Array = cur.get("env", [])
	for k: String in rigs:
		var r: Rig = rigs[k]
		var target := 1.0 if (talking or t - last_end < 0.6) else 0.0
		if talking and not rigs.has(shot_who):
			target = 0.0          # somebody outside the car is talking: both look ahead
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
			var calm_after := 2.5 if ending != "" else 0.7
			if t - last_end > calm_after and r.emotion != "neutral" and not (ending == "happy" and end_ready):
				r.set_state("neutral", "idle", false)
		r.update(dt, null)
	if wheel != null:
		wheel.rotation.y = -main.player.steer_smooth * 1.8


# ------------------------------------------------------------ camera

func _nearest_police() -> Car:
	var best: Car = null
	var bd := 1e9
	for c in main.police:
		if is_instance_valid(c) and not c.dead:
			var d: float = c.global_position.distance_to(main.player.global_position)
			if d < bd:
				bd = d
				best = c
	return best


# While somebody talks the camera rides with the car and films the speaker; between lines
# and in the air it is left to the game's own director. Endings and a flying prop keep it.
func _camera(dt: float, t: float) -> void:
	var pl: Car = main.player
	var want := (not cur.is_empty() or t - last_end < 0.45) and not done and t > INTRO
	if pl.airtime > 0.0 or main.cine_t > 0.0 or main.game_over:
		want = false
	if ending != "" and end_ready:
		want = true
	var prop_shot := t < prop_shot_until and is_instance_valid(flying)
	if prop_shot:
		want = true
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
	var heads := base + Vector3(0, 1.9, 0) - fwd * Roadster.SEAT_Z
	var s := shot
	if prop_shot:
		s = "prop"
	elif ending != "" and end_ready and cur.is_empty():
		s = "orbit" if ending != "caught" else "police_wide"
	match s:
		"prop":
			var fp: Vector3 = flying.global_position
			pos = base - fwd * 2.0 + right * 3.0 + Vector3(0, 3.0, 0)
			look_at_p = fp
			shot_fov = 55.0
		"close":
			var r: Rig = rigs.get(shot_who, null)
			var hp: Vector3 = r.head.global_position + Vector3(0, 0.27, 0) if r != null else heads
			var sx: float = r.seat_x if r != null else 0.0
			pos = hp + fwd * 2.9 + right * sx * 1.3 + Vector3(0, 0.1, 0)
			look_at_p = hp + right * sx * -0.35
			shot_fov = 42.0
		"side":
			pos = base + right * 3.1 + fwd * 0.9 + Vector3(0, 1.9, 0)
			look_at_p = base + Vector3(0, 1.85, 0.0)
			shot_fov = 50.0
		"behind":
			pos = base - fwd * 4.6 + Vector3(0, 3.2, 0)
			look_at_p = base + fwd * 2.5 + Vector3(0, 1.7, 0)
			shot_fov = 60.0
		"police", "police_wide":
			var pc := _nearest_police()
			if pc != null:
				# over the police car's shoulder: the police in front, the pink car ahead of them
				var to := heads - pc.global_position
				to.y = 0.0
				to = to.normalized()
				var back := 6.0 if s == "police" else 10.0
				pos = pc.global_position - to * back + to.cross(Vector3.UP) * 1.6 + Vector3(0, 2.6 if s == "police" else 5.0, 0)
				look_at_p = pc.global_position + to * 9.0 + Vector3(0, 1.0, 0)
			else:
				pos = base - fwd * 5.0 + Vector3(0, 3.0, 0)
				look_at_p = base + fwd * 3.0 + Vector3(0, 1.5, 0)
			shot_fov = 50.0
		"orbit":
			orbit_a += dt * 0.22
			var ang := atan2(fwd.x, fwd.z) + orbit_a + 0.6
			pos = heads + Vector3(sin(ang), 0, cos(ang)) * 5.2 + Vector3(0, 0.9, 0)
			look_at_p = heads
			shot_fov = 46.0
		_:
			pos = base + fwd * 4.4 + right * 0.5 + Vector3(0, 2.5, 0)
			look_at_p = base + Vector3(0, 1.85, 0)
			shot_fov = 50.0
	# never film from inside a wall (checked from whatever the shot is looking at)
	var from := base + Vector3(0, 1.6, 0)
	if s in ["police", "police_wide"] and _nearest_police() != null:
		from = _nearest_police().global_position + Vector3(0, 1.6, 0)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, pos, 1))
	if not hit.is_empty():
		pos = (hit["position"] as Vector3) + (from - pos).normalized() * 0.5
	pos += Vector3(sin(t * 2.3), sin(t * 3.1), sin(t * 1.7)) * 0.012
	# the game's own camera has already moved the camera this frame, so smooth from our own state
	cam_pos = pos if cam_new else cam_pos.lerp(pos, 1.0 - exp(-20.0 * dt))
	cam_fov = shot_fov if cam_new else lerpf(cam_fov, shot_fov, 1.0 - exp(-8.0 * dt))
	cam.global_position = cam_pos
	if cam_pos.distance_to(look_at_p) > 0.05:
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
