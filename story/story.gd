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
#         on foot:        park (stop at the kerb in the middle of a block; quiet street;
#                         "at": bench | icecream | chai puts up that set just ahead, the
#                         stalls with a vendor who can speak as "vendor"),
#                         exit_car / enter_car ("who": babu | shona | both; with a set they
#                         walk straight to it), walk / run ("who", "to": ahead | back | car |
#                         other | spot, "dist" m), sit (on the bench if there is one), stand,
#                         kneel, fall, dance, cheer ("who"), hug
#         in the hand:    hold ("who", "prop"), give ("who" gives "to" someone; the vendor
#                         hands out "prop", by default what the stall sells)
#         action:         arrive, grab, drive_off, chase, corner, fight, punch, look, appear,
#                         shot (see story/action.gd); events car_arrived, grabbed, fled, cornered, won
#                         events for "on" / "wait_for": parked, exited, arrived, seated
# "cast" entries with a "look" and no seat are side characters: they start on the pavement
# ("start": {"at": ahead | back | near:<who>, "dist"}), inside a story car ("start": {"car"}),
# or off screen until "appear". "cars": {"van": {"color"}} are the cars the story drives.
# "start_on_foot": true (and "start_spot") starts the episode parked, everybody on the pavement.
#   {"wait": seconds}  {"wait_for": event, "max_wait": s}
#   {"end": "happy" | "caught" | "crash" | "cliffhanger"}   the ending; lines after it play
#                         once the ending scene is set (the car has stopped ...)
# "dur" and "env" (voice length, loudness curve for the mouth) are filled in by
# tools/story/voices.py. The start time of every line goes to --story_log for tools/story/mix.py.
# Old screenplays with "lines" / "reactions" still play.

const Rig := preload("res://story/rig.gd")
const Roadster := preload("res://story/roadster.gd")
const Props := preload("res://story/props.gd")
const Street := preload("res://story/street.gd")
const Spots := preload("res://story/spots.gd")
const Action := preload("res://story/action.gd")
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
var max_duration := 90.0         # the clip may run this long if the story needs it
# on foot
var park_t := -1.0               # when the story asked to park (-1: not asked)
var parked := false
var street = null                # Street: the pavement beside the parked car
var exits := {}                  # who -> true while walking out of / back to the car
var boarding := {}               # who -> true while walking back to get in
var walkers := {}                # who -> true while on a walk / run command
var hug_until := 0.0
var foot_shot := "foot_wide"
var traffic_was := -1            # the traffic level before the street was cleared
var spot_kind := ""              # the set asked for with park "at"
var spot = null                  # Spots: the set on the pavement
var extras := {}                 # who -> rig of a side character on foot (the vendor)
var passing: Array = []          # things being handed over: {"node", "from", "to", "t0"}
var act                          # Action: other cars, grabbing, the chase, fights, drama shots
var to_place := {}               # who -> {"at", "dist"}: side characters waiting for the street

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
	act = Action.new()
	act.setup(self)
	_make_side_cast()
	_make_ui()
	if bool(data.get("start_on_foot", false)):
		_start_on_foot()
	for k: String in data.get("props", []):
		_prop_show(k)
	main.hud.visible = false
	if main.director != null:
		# tools/record.sh stops recording 20 s after --duration, so stay inside that
		max_duration = main.director.duration + 16.0
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
	if bool(car.get("roof", true)):
		Roadster.make_cabin(pl.vis, col)
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


# Side characters (anyone in the cast with a look and no seat): hidden until they are placed
# on the pavement, start inside a story car, or walk on with "appear".
func _make_side_cast() -> void:
	for who: String in cast:
		var c: Dictionary = cast[who]
		if rigs.has(who) or who == "vendor" or not c.has("look"):
			continue
		var r := Rig.new()
		main.add_child(r)
		r.build(who, c.get("look", {}), false, 0.0)
		r.seated = false
		r.pose = "stand"
		r.visible = false
		extras[who] = r
		var st: Dictionary = c.get("start", {})
		if str(st.get("car", "")) in act.cars:
			act.in_car[who] = str(st["car"])
		elif st.has("at"):
			to_place[who] = st


# The episode starts out of the car: it stands parked at the kerb, everybody on the pavement.
func _start_on_foot() -> void:
	main.player.linear_velocity = Vector3.ZERO
	_park_now(0.0)
	for k: String in rigs:
		var r: Rig = rigs[k]
		var st: Dictionary = cast[k].get("start", {})
		r.reparent(main, false)
		_place_on_foot(k, str(st.get("at", "car")), float(st.get("dist", 0.0)))
	var at := str(data.get("start_spot", ""))
	if at != "" and spot == null:
		_put_up_set(at)


# Stops right here (an on-foot start, or behind a cornered car) instead of finding a kerb.
func _park_now(t: float) -> void:
	var pl: Car = main.player
	stop_car = true
	main.bot.cruise = 0.0
	park_t = t
	parked = true
	street = Street.from_car(pl)
	if main.director != null:
		main.director.still = true
		main.director.cue("calm")
	_quiet_street(true)
	ev_log.append({"type": "parked", "t": t})
	for who: String in to_place.keys():
		_place_on_foot(who, str(to_place[who].get("at", "ahead")), float(to_place[who].get("dist", 8.0)))
	to_place.clear()


# Puts somebody on the pavement: "car" (beside the car), "ahead" / "back" (dist m along the
# street), "near:<who>" (next to them), "spot" (at the set).
func _place_on_foot(who: String, at: String, dist: float) -> void:
	var r := _rig_of(who)
	if r == null or street == null:
		return
	var f: float = street.dir.x + street.dir.z
	var a: float = street.along(main.player.global_position)
	var off := 0.0
	if at == "ahead":
		a += maxf(dist, 3.0) * f
	elif at == "back":
		a -= maxf(dist, 3.0) * f
	elif at.begins_with("near:") and _rig_of(at.substr(5)) != null:
		a = street.along(_rig_of(at.substr(5)).global_position) + 0.9 * f
		off = 0.35
	elif at == "spot" and spot != null and spot.stand.has(who):
		a = street.along(spot.stand[who])
	elif rigs.has(who):
		a += (0.7 if r.driver else -0.7) * f
	var p: Vector3 = street.point(street.clamp_along(a), off)
	r.visible = true
	r.stand_at(p, atan2(-street.outward().x, -street.outward().z) + PI)


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
	_park(t)
	_on_foot(t)
	_pass_things(t)
	act.tick(dt, t)
	_schedule(t)
	_ending(dt, t)
	_animate(dt, t)
	_camera(dt, t)
	_ui(t)
	_supporting_cast(t)


# The police are side characters: they follow the car (it reads as a chase) but keep their
# distance, unless the ending is the one where they catch it. And the clip runs on until
# the story is told, up to max_duration.
func _supporting_cast(t: float) -> void:
	if ending != "caught":
		for c in main.police:
			if is_instance_valid(c):
				c.hold = true
	var dir = main.director
	if dir != null and not done and dir.duration - t < 2.5 and dir.duration < max_duration:
		dir.duration = minf(dir.duration + 1.0, max_duration)


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
	acted.append({"do": kind, "t": snappedf(t, 0.01), "type": str(b.get("type", ""))})
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
			if _anyone_on_foot():
				pending.append({"kind": "go", "from": t, "until": t + 20.0})
			else:
				_drive_on()
		"park":
			if park_t < 0.0:
				park_t = t
				spot_kind = str(b.get("at", ""))
		"exit_car", "enter_car", "walk", "run", "sit", "stand", "kneel", "fall", "hug", "dance", "cheer", "hold", "give", \
				"arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "look", "appear", "shot":
			var a := b.duplicate()
			a.erase("do")
			a.merge({"kind": kind, "who": str(b.get("who", "both")), "to": str(b.get("to", "")),
				"dist": float(b.get("dist", 8.0)), "prop": str(b.get("prop", "")), "from": t, "until": t + 25.0}, true)
			pending.append(a)
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
		elif act.handles(a):
			ok = act.run(a, t)
		elif kind == "jump" and act.chase != "":
			ok = act.chase_jump()
		elif kind in ["hold", "give"]:
			ok = _hand_action(a, t)
		elif kind in ["exit_car", "enter_car", "walk", "run", "sit", "stand", "kneel", "fall", "hug", "dance", "cheer", "go"]:
			ok = _foot_action(a, t)
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


# ------------------------------------------------------------ on foot

# A lead out of the car and in the scene (not carried off, not inside another car).
func _anyone_on_foot() -> bool:
	for k: String in rigs:
		if _on_foot_now(k):
			return true
	return false


func _on_foot_now(k: String) -> bool:
	var r := _rig_of(k)
	return r != null and not r.seated and r.visible and r.pose != "carried" and not act.hidden(k)


func _who(sel: String) -> Array:
	if sel.contains(","):
		var out := []
		for k in sel.split(","):
			if _rig_of(k.strip_edges()) != null:
				out.append(k.strip_edges())
		return out
	if extras.has(sel):
		return [sel]
	if sel == "both" or not rigs.has(sel):
		return rigs.keys()
	return [sel]


func _other(k: String) -> Rig:
	for o: String in rigs:
		if o != k:
			return rigs[o]
	return null


# Where people walk along the pavement: the lane, or in front of a stall's counter.
func _lane() -> float:
	return -1.0 if spot != null and spot.kind != "bench" else 0.0


func _along_now(r: Rig) -> float:
	return street.along(r.global_position)


func _rig_of(k: String) -> Rig:
	return rigs.get(k, extras.get(k, null))


# The set asked for with park "at", put up just ahead of the car; a stall gets its vendor.
func _put_up_set(kind: String) -> void:
	var a := ""
	var b := ""
	for k: String in rigs:
		if (rigs[k] as Rig).driver:
			a = k
		else:
			b = k
	spot = Spots.build(kind, street, street.along(main.player.global_position), main, main, a, b)
	if spot == null or kind == "bench":
		return
	var c: Dictionary = cast.get("vendor", {})
	var look: Dictionary = c.get("look", {"style": "boy", "skin": "#c98b5e", "hair": "#1d1714", "shirt": "#f3efe4"})
	var v := Rig.new()
	main.add_child(v)
	v.build("vendor", look, false, 0.0)
	v.stand_at(spot.vendor_at, atan2(-spot.face.x, -spot.face.z))
	v.set_state("happy", "idle", false)
	extras["vendor"] = v
	if not cast.has("vendor"):
		cast["vendor"] = {"name": "BHAIYA", "color": "#f0a020"}


# Hands: picking something up and giving it to someone (in the car or on foot).
func _hand_action(a: Dictionary, t: float) -> bool:
	var kind := str(a["kind"])
	var who := str(a.get("who", ""))
	var prop := str(a.get("prop", ""))
	if kind == "hold":
		if not Props.KINDS.has(prop):
			return true
		var hands: Array = [extras[who]] if extras.has(who) else _who(who).map(func(k: String) -> Rig: return rigs[k])
		for r: Rig in hands:
			var n: Node3D = props.get(prop, null)
			if n != null:
				props.erase(prop)       # off the dashboard, into the hand
			else:
				n = Props.build(prop)
			r.hold(n)
		return true
	# give
	var giver := _rig_of(who)
	if giver == null:
		return true
	var to := str(a.get("to", ""))
	var takers: Array = []
	if to == "both" or (to == "" and who == "vendor"):
		takers = rigs.values()
	elif _rig_of(to) != null and to != who:
		takers = [_rig_of(to)]
	elif rigs.has(who):
		takers = [_other(who)]
	if takers.is_empty():
		return true
	# two people on foot come close enough first
	if takers.size() == 1 and not giver.seated and not (takers[0] as Rig).seated and rigs.has(who):
		var tk: Rig = takers[0]
		if giver.global_position.distance_to(tk.global_position) > 1.8:
			if giver.arrived() and street != null:
				var ta: float = street.along(tk.global_position)
				var ga: float = street.along(giver.global_position)
				var off := minf(street.offset(tk.global_position), _lane()) - 0.3
				giver.walk_to([street.point(ga, off), street.point(ta + (1.0 if ga > ta else -1.0), off)])
			return false
		if not giver.arrived():
			return false
	if prop == "" and giver.held != null and is_instance_valid(giver.held):
		prop = str(giver.held.name)
	if prop == "" or not Props.KINDS.has(prop):
		prop = spot.kind if spot != null and spot.kind in ["icecream", "chai"] else "gift"
	for tk: Rig in takers:
		var n: Node3D = null
		if takers.size() == 1 and giver.held != null and is_instance_valid(giver.held) and str(giver.held.name) == prop:
			n = giver.let_go()
		else:
			n = Props.build(prop)
			main.add_child(n)
			n.global_position = _hand(giver)
		if n.get_parent() != main:
			n.reparent(main, true)
		passing.append({"node": n, "from": giver, "to": tk, "t0": t})
	giver.reach_t = 0.9
	return true


func _hand(r: Rig) -> Vector3:
	return r.arm_r.to_global(Vector3(0, -0.56, -0.06))


# Things on their way from one hand to another: a short arc, then the taker holds it.
func _pass_things(t: float) -> void:
	for p: Dictionary in passing.duplicate():
		var n: Node3D = p["node"]
		var to: Rig = p["to"]
		var k := clampf((t - float(p["t0"])) / 0.55, 0.0, 1.0)
		if not is_instance_valid(n):
			passing.erase(p)
			continue
		if k > 0.4:
			to.reach_t = maxf(to.reach_t, 0.3)
		var a := _hand(p["from"])
		var b := _hand(to)
		n.global_position = a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.25, 0)
		if k >= 1.0:
			passing.erase(p)
			to.hold(n)


# Stopping at the kerb: wait until the block ahead is long enough to stop in its middle,
# then brake. The street is cleared of traffic and the police leave.
func _park(t: float) -> void:
	if park_t < 0.0 or parked:
		return
	var pl: Car = main.player
	var dir = main.director
	if not stop_car:
		var f := -pl.global_transform.basis.z
		var axis_ok := absf(f.x) > 0.96 or absf(f.z) > 0.96
		var a := pl.global_position.x if absf(f.x) > absf(f.z) else pl.global_position.z
		var sgn := signf(f.x) if absf(f.x) > absf(f.z) else signf(f.z)
		var frac := fposmod(a + World.HALF, World.PITCH)
		var to_next := World.PITCH - frac if sgn > 0.0 else frac
		if (axis_ok and to_next > 38.0 and World.PITCH - to_next > 6.0 and pl.airtime == 0.0) or t - park_t > 20.0:
			stop_car = true
			if dir != null:
				dir.still = true
				dir.cue("calm")
			_quiet_street(true)
	elif pl.speed < 0.4:
		parked = true
		street = Street.from_car(pl)
		if spot_kind != "" and spot == null:
			_put_up_set(spot_kind)
		ev_log.append({"type": "parked", "t": t})
		print("STORYPARK t=", snappedf(t, 0.01))


func _quiet_street(on: bool) -> void:
	if on and traffic_was < 0:
		traffic_was = main.traffic_cap
	elif not on and traffic_was >= 0:
		main.traffic_cap = traffic_was
		traffic_was = -1
	if on:
		main.traffic_cap = 0
		for c in main.civs.duplicate():
			if is_instance_valid(c) and c.global_position.distance_to(main.player.global_position) < 160.0:
				main.civs.erase(c)
				c.queue_free()


func _drive_on() -> void:
	main.bot.halt = false
	stop_car = false
	parked = false
	park_t = -1.0
	# the set stays where it is; the next stop is somewhere else
	spot = null
	spot_kind = ""
	main.bot.cruise = 26.0
	_quiet_street(false)
	if main.director != null:
		main.director.still = false


func _door(k: String) -> Vector3:
	var pl: Car = main.player
	var r: Rig = rigs[k]
	return pl.global_position + pl.global_transform.basis.x * signf(r.seat_x) * 1.55


# Where each character stands on the pavement next to the car (a little apart, facing each other).
func _spot(k: String, a: float) -> Vector3:
	var r: Rig = rigs[k]
	var fwd_sign: float = street.dir.x + street.dir.z
	return street.point(a + (0.7 if r.driver else -0.7) * fwd_sign)


# The way from a car door to the pavement: round the front of the car if the door is on the
# road side.
func _door_path(k: String) -> Array:
	var pl: Car = main.player
	var door := _door(k)
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	var pts := [door]
	var toward: Vector3 = street.outward()
	if (door - pl.global_position).dot(toward) < 0.0:
		var front := pl.global_position + fwd.normalized() * 3.0
		pts.append(front - toward * 1.6)
		pts.append(front + toward * 1.8)
	pts.append(_spot(k, street.along(pl.global_position)))
	return pts


func _foot_action(a: Dictionary, t: float) -> bool:
	var kind := str(a["kind"])
	if not parked and kind != "go":
		return false
	var ks := _who(str(a.get("who", "both")))
	match kind:
		"exit_car":
			for k: String in ks:
				var r: Rig = rigs[k]
				if not r.seated:
					continue
				var yaw: float = main.player.global_rotation.y
				r.reparent(main, true)
				r.stand_at(_door(k), yaw)
				var way := _door_path(k).slice(1)
				if spot != null and spot.stand.has(k):
					way.append(spot.stand[k])
				if act.cornered != "":
					# straight out of the door and into the action
					var out: Vector3 = _door(k) - main.player.global_position
					out.y = 0.0
					way = [_door(k) + out.normalized() * 1.0]
				r.walk_to(way, false, 1.4)
				exits[k] = true
			cam_new = true
			foot_shot = "foot_wide"
		"enter_car":
			for k: String in ks:
				var r: Rig = rigs[k]
				if r.seated:
					continue
				var back := _door_path(k)
				back.reverse()
				r.stand_up()
				# in a hurry when somebody is getting away
				r.walk_to(back, act.cars.values().any(func(v) -> bool: return v.mode == "flee"), 1.4)
				boarding[k] = true
		"walk", "run":
			var to := str(a.get("to", ""))
			if to == "":
				to = "ahead"
			var dist := float(a.get("dist", 8.0))
			var i := 0
			ks = ks.filter(func(k: String) -> bool: return _on_foot_now(k) or (extras.has(k) and extras[k].visible))
			# a group walks together, side by side, from where the first of them stands
			var lead_here: float = street.along(_rig_of(ks[0]).global_position) if not ks.is_empty() else 0.0
			for k: String in ks:
				var r: Rig = _rig_of(k)
				var here: float = lead_here if ks.size() > 1 else street.along(r.global_position)
				var target := here
				var person := _rig_of(to) if to not in ["other", "car", "back", "ahead", "spot", ""] else null
				if person != null and person != r:
					var pa: float = street.along(person.path.back() if not person.path.is_empty() else person.global_position)
					target = pa + (1.1 if street.along(r.global_position) > pa else -1.1)
				else:
					match to:
						"back":
							target = here - dist * (street.dir.x + street.dir.z)
						"car":
							target = street.along(main.player.global_position)
						"other":
							var o := _other(k)
							if o != null:
								var op: Vector3 = o.path.back() if not o.path.is_empty() else o.global_position
								var oa: float = street.along(op)
								target = oa + (1.1 if here > oa else -1.1)
						_:
							target = here + dist * (street.dir.x + street.dir.z)
				var off := _lane() + ((i - (ks.size() - 1) * 0.5) * 0.8 if ks.size() > 1 else 0.0)
				r.stand_up()
				if to == "spot" and spot != null and spot.stand.has(k):
					r.walk_to([spot.stand[k]], kind == "run")
				else:
					r.walk_to([street.point(_along_now(r), off), street.point(street.clamp_along(target), off)], kind == "run")
				walkers[k] = true
				i += 1
		"sit":
			for k: String in ks:
				var r: Rig = _rig_of(k)
				if spot != null and spot.seats.has(k):
					r.stand_up()
					r.sit_on([spot.stand[k], spot.seats[k]], atan2(-spot.face.x, -spot.face.z), Spots.BENCH_H)
				else:
					r.sit_down()
		"dance":
			for k: String in ks:
				_rig_of(k).dance()
		"cheer":
			for k: String in ks:
				_rig_of(k).cheer()
		"stand":
			for k: String in ks:
				_rig_of(k).stand_up()
		"fall":
			for k: String in ks:
				_rig_of(k).fall_down()
		"kneel":
			for k: String in ks:
				_rig_of(k).kneel()
		"hug":
			var keys := rigs.keys()
			if keys.size() == 2:
				var r1: Rig = rigs[keys[0]]
				var r2: Rig = rigs[keys[1]]
				var mid := (r1.global_position + r2.global_position) * 0.5
				var ax := street.dir as Vector3
				r1.stand_up()
				r2.stand_up()
				r1.walk_to([Vector3(mid.x, 0, mid.z) - ax * 0.42])
				r2.walk_to([Vector3(mid.x, 0, mid.z) + ax * 0.42])
				hug_until = t + 3.0
		"go":
			if _anyone_on_foot():
				return false
			_drive_on()
	return true


func _on_foot(t: float) -> void:
	if not parked and not _anyone_on_foot():
		return
	if parked:
		_quiet_street(true)     # traffic from further away would drive into the scene
	# people standing still look at whoever is talking nearby, else at the nearest person
	var speaker: Rig = _rig_of(shot_who) if not cur.is_empty() else null
	var everyone: Array = rigs.values() + extras.values()
	for r: Rig in everyone:
		if r.seated or not r.visible or r.pose == "carried":
			continue
		var target := Vector3.INF
		var look_at: Rig = _rig_of(act.looks.get(r.who, "")) if act.looks.has(r.who) else null
		if look_at != null:
			target = look_at.global_position
		elif speaker != null and speaker != r and speaker.visible and speaker.global_position.distance_to(r.global_position) < 7.0:
			target = speaker.global_position
		else:
			var o := _other(r.who) if rigs.has(r.who) else null
			if o != null and _on_foot_now(o.who) and o.global_position.distance_to(r.global_position) < 7.0:
				target = o.global_position
			else:
				var bd := 7.0
				for q: Rig in everyone:
					if q != r and q.visible and not q.seated and q.global_position.distance_to(r.global_position) < bd:
						bd = q.global_position.distance_to(r.global_position)
						target = q.global_position
		if extras.has("vendor") and rigs.has(r.who) and passing.any(func(p: Dictionary) -> bool: return p["from"] == extras["vendor"]):
			target = (extras["vendor"] as Rig).global_position    # taking from the vendor
		r.face_point = target if target != Vector3.INF else main.player.global_position
		if rigs.has(r.who):
			r.hug = t < hug_until and r.arrived()
	if not exits.is_empty() and exits.keys().all(func(k: String) -> bool: return (rigs[k] as Rig).arrived()):
		exits.clear()
		ev_log.append({"type": "exited", "t": t})
	if not walkers.is_empty() and walkers.keys().all(func(k: String) -> bool: return _rig_of(k) == null or _rig_of(k).arrived()):
		walkers.clear()
		ev_log.append({"type": "arrived", "t": t})
	for k: String in boarding.keys():
		var r: Rig = rigs[k]
		if r.arrived():
			boarding.erase(k)
			r.reparent(main.player.vis, false)
			r.sit_in_car(Vector3(r.seat_x, Roadster.SEAT_Y, Roadster.SEAT_Z))
			if boarding.is_empty():
				ev_log.append({"type": "seated", "t": t})
				cam_new = true


# ------------------------------------------------------------ endings

func _begin_ending(kind: String, t: float) -> void:
	ending = kind if kind in ["happy", "caught", "crash", "cliffhanger"] else "happy"
	if parked and ending == "crash":
		ending = "happy"    # a parked car does not spin out: a quiet closing shot instead
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
	if parked and ending != "caught":
		end_ready = true
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
	for k: String in extras:
		var r: Rig = extras[k]
		if k == who:
			r.set_state(str(line.get("emotion", "happy")), str(line.get("gesture", "talk")), true)
		else:
			r.set_state("happy", "idle", false)
	played.append({"id": str(line.get("id", "")), "t": snappedf(t, 0.01)})
	_write_log()
	shot_who = who
	if extras.has(who):
		shot = "close"          # filmed by the camera on foot
	elif not rigs.has(who):
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
	for r: Rig in rigs.values() + extras.values():
		r.speaking = false


func _write_log() -> void:
	if log_path == "":
		return
	var fa := FileAccess.open(log_path, FileAccess.WRITE)
	if fa == null:
		return
	fa.store_string(JSON.stringify({"lines": played, "actions": acted, "ending": ending,
		"events": ev_log, "end": snappedf(done_t, 0.01) if done else -1.0}))
	fa.close()


# ------------------------------------------------------------ characters

func _animate(dt: float, t: float) -> void:
	var talking := not cur.is_empty()
	var env: Array = cur.get("env", [])
	for r: Rig in rigs.values() + extras.values():
		var target := 1.0 if (talking or t - last_end < 0.6) else 0.0
		if talking and not rigs.has(shot_who) and not extras.has(shot_who):
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
			var calm := "happy" if extras.has(r.who) else "neutral"
			if t - last_end > calm_after and r.emotion != calm and not (ending == "happy" and end_ready):
				r.set_state(calm, "idle", false)
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
	if not act.shot.is_empty():
		_drama_camera(dt, t)
		return
	if not cur.is_empty() and act.hidden(shot_who):
		_van_camera(dt, t)
		return
	if _anyone_on_foot() or (parked and not exits.is_empty()) or (extras.has(shot_who) and not cur.is_empty()):
		_foot_camera(dt, t)
		return
	if act.chase != "" and cur.is_empty():
		_chase_camera(dt, t)
		return
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


# On foot the story films everything itself: a wide shot as they get out, a tracking shot
# while they walk, a two-shot or the speaker's face while they talk.
# Shots the story asks for: a push in on a face, over a shoulder, high and wide, a car.
func _drama_camera(dt: float, t: float) -> void:
	cam_on = true
	var sh: Dictionary = act.shot
	var r := _rig_of(str(sh.get("who", "")))
	var other := _rig_of(str(sh.get("to", "")))
	var k := clampf((t - float(sh["t0"])) / maxf(float(sh["until"]) - float(sh["t0"]), 0.1), 0.0, 1.0)
	var pos := cam_pos
	var look := cam_pos + Vector3.FORWARD
	var fov := 46.0
	var smooth := 8.0
	match str(sh["type"]):
		"zoom":
			if r != null:
				var hp := r.head.global_position + Vector3(0, 0.25 * r.size, 0)
				var facing := -r.global_transform.basis.z
				facing.y = 0.0
				facing = facing.normalized()
				var e := 1.0 - pow(1.0 - k, 3.0)
				pos = hp + facing * lerpf(3.4, 1.15, e) + Vector3(0, 0.06, 0)
				look = hp
				fov = lerpf(54.0, 32.0, e)
				smooth = 30.0
		"pov":
			if r != null and other != null:
				var d := other.global_position - r.global_position
				d.y = 0.0
				d = d.normalized()
				pos = r.head.global_position + Vector3(0, 0.32, 0) - d * 0.9 + d.cross(Vector3.UP) * 0.45
				look = other.head.global_position + Vector3(0, 0.1, 0)
				fov = 38.0
		"car":
			var v = act.cars.get(str(sh.get("car", "")), null)
			if v != null:
				var right: Vector3 = v.forward().cross(Vector3.UP)
				pos = v.global_position + v.forward() * 9.0 + right * 3.0 * act._kerb_side(v) + Vector3(0, 2.2, 0)
				look = v.global_position + Vector3(0, 1.2, 0)
				fov = 50.0
		_:
			var c: Vector3 = r.global_position if r != null else main.player.global_position
			var out: Vector3 = street.outward() if street != null else Vector3.RIGHT
			var along: Vector3 = street.dir if street != null else Vector3.FORWARD
			pos = c - out * 11.0 + along * 5.0 + Vector3(0, 6.5, 0)
			look = c + Vector3(0, 1.0, 0)
			fov = 50.0
	_put_camera(pos, look, fov, smooth, dt)


# Somebody inside a story car is talking (or screaming): film the car from beside it.
func _van_camera(dt: float, t: float) -> void:
	cam_on = true
	var v = act.cars[act.in_car[shot_who]]
	var right: Vector3 = v.forward().cross(Vector3.UP)
	var pos: Vector3 = v.global_position + right * 4.2 + v.forward() * 2.5 + Vector3(0, 1.9, 0)
	_put_camera(pos, v.global_position + Vector3(0, 1.4, 0), 52.0, 10.0, dt)


# The chase: from behind the leads' car, looking up the road at the van; the flight off a
# ramp from beside it.
func _chase_camera(dt: float, t: float) -> void:
	cam_on = true
	var v = act.cars[act.chase]
	var pl: Car = main.player
	var to_van: Vector3 = v.global_position - pl.global_position
	to_van.y = 0.0
	var d := to_van.length()
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var aim := to_van.normalized() if d > 1.0 and d < 80.0 and to_van.normalized().dot(fwd) > 0.2 else fwd
	var pos: Vector3
	var look: Vector3
	var fov := 58.0
	if act.jump_lip != Vector3.INF and (v.airborne or pl.airtime > 0.05) and v.global_position.distance_to(act.jump_lip) < 70.0:
		var right := aim.cross(Vector3.UP)
		pos = act.jump_lip + right * 10.0 - aim * 3.0 + Vector3(0, 2.5, 0)
		look = (v.global_position + pl.global_position) * 0.5 + Vector3(0, 2.0, 0)
		fov = 60.0
	else:
		pos = pl.global_position - aim * 9.5 + Vector3(0, 3.6, 0)
		look = pl.global_position + aim * minf(d, 40.0) * 0.6 + Vector3(0, 1.0, 0)
	_put_camera(pos, look, fov, 4.0, dt)


func _put_camera(pos: Vector3, look: Vector3, fov: float, smooth: float, dt: float) -> void:
	var cam: Camera3D = main.cam
	cam_pos = pos if cam_new else cam_pos.lerp(pos, 1.0 - exp(-smooth * dt))
	cam_fov = fov if cam_new else lerpf(cam_fov, fov, 1.0 - exp(-smooth * dt))
	cam_new = false
	cam.global_position = cam_pos
	if cam_pos.distance_to(look) > 0.05:
		cam.look_at(look, Vector3.UP)
	cam.fov = cam_fov


func _foot_camera(dt: float, t: float) -> void:
	cam_on = true
	var cam: Camera3D = main.cam
	var people: Array = []
	for r: Rig in rigs.values() + extras.values():
		if not r.seated and r.visible and r.pose != "carried" and not act.hidden(r.who):
			people.append(r)
	# the group around whoever is talking (or walking): people far down the street are not in it
	var focus: Rig = _rig_of(shot_who) if not cur.is_empty() else null
	if focus == null or not people.has(focus):
		focus = null
		for r: Rig in people:
			if not r.arrived():
				focus = r
				break
		if focus == null and not people.is_empty():
			focus = people[0]
			for r: Rig in people:
				if rigs.has(r.who):
					focus = r
					break
	if focus != null:
		people = people.filter(func(r: Rig) -> bool: return r.global_position.distance_to(focus.global_position) < 8.0)
	var mid: Vector3 = main.player.global_position
	if not people.is_empty():
		mid = Vector3.ZERO
		for r: Rig in people:
			mid += r.global_position
		mid /= people.size()
	mid.y = 0.0
	var walking := false
	for r: Rig in people:
		if not r.arrived():
			walking = true
	var s := foot_shot
	var fighters := _fighters()
	if not fighters.is_empty() and cur.is_empty():
		s = "foot_fight"
	elif not cur.is_empty() and extras.has(shot_who):
		s = "foot_close"
	elif not cur.is_empty():
		s = "foot_close" if (shot_i % 2 == 0 and rigs.has(shot_who) and not (rigs[shot_who] as Rig).seated) else "foot_two"
	elif (not exits.is_empty() or not boarding.is_empty()) and _near_car(people, 5.0):
		s = "foot_wide"
	elif walking:
		s = "foot_track"
	elif ending != "" and end_ready:
		s = "foot_orbit"
	elif t - last_end > 0.8:
		s = "foot_two"
	if s != foot_shot:
		foot_shot = s
		cam_new = true
	var along: Vector3 = street.dir if street != null else Vector3.FORWARD
	var out: Vector3 = street.outward() if street != null else Vector3.RIGHT
	var pos := Vector3.ZERO
	var look := mid + Vector3(0, 1.5, 0)
	var fov := 48.0
	var cands: Array[Vector3] = []     # camera spots in order of preference: the first clear one is used
	if s == "foot_close":
		var r: Rig = _rig_of(shot_who)
		var others: Array = people.filter(func(q: Rig) -> bool: return q != r)
		var hp := r.head.global_position + Vector3(0, 0.25 * r.size, 0)
		var facing := -r.global_transform.basis.z
		facing.y = 0.0
		facing = facing.normalized()
		var side := -out - facing * facing.dot(-out)
		side = side.normalized() if side.length() > 0.2 else facing.cross(Vector3.UP)
		# a three-quarter view from the road side, turned further while the partner is in the way
		for a: float in [0.5, 0.85, 1.2, 1.55]:
			var p := hp + (facing * cos(a) + side * sin(a)) * 2.4 + Vector3(0, 0.12, 0)
			if not r.hug and others.all(func(o: Rig) -> bool: return o.pose in ["fall", "ko"] or not _blocks(o, p, hp)):
				cands.append(p)
		if cands.is_empty():
			s = "foot_two"      # hugging, or too close together: film them both
		else:
			look = hp
			fov = 40.0
	match s:
		"foot_track":
			var lead := along
			for r: Rig in people:
				if not r.arrived():
					lead = (r.path[0] - r.global_position)
					lead.y = 0.0
					lead = lead.normalized()
					break
			# in front of them (faces), else from behind
			cands.append(mid + lead * 4.6 - out * 2.4 + Vector3(0, 2.0, 0))
			cands.append(mid - lead * 4.2 - out * 2.2 + Vector3(0, 2.3, 0))
			look = mid + lead * 0.8 + Vector3(0, 1.3, 0)
			fov = 50.0
		"foot_fight":
			# side-on to the two fighting, from whichever side is clear
			var fa: Rig = fighters[0]
			var fb: Rig = fighters[1]
			var fm := (fa.global_position + fb.global_position) * 0.5
			fm.y = 0.0
			var ax := fb.global_position - fa.global_position
			ax.y = 0.0
			ax = ax.normalized() if ax.length() > 0.1 else along
			var side_v := ax.cross(Vector3.UP)
			for sg: float in [1.0, -1.0]:
				cands.append(fm + side_v * sg * 4.6 + Vector3(0, 1.6, 0))
				cands.append(fm + side_v * sg * 3.4 - ax * 2.5 + Vector3(0, 1.8, 0))
			# a van or a wall beside them: higher and further, then from above
			for sg: float in [1.0, -1.0]:
				cands.append(fm + side_v * sg * 6.5 + Vector3(0, 4.2, 0))
			cands.append(fm - ax * 5.0 + Vector3(0, 7.0, 0))
			look = fm + Vector3(0, 1.1, 0)
			fov = 50.0
		"foot_orbit":
			orbit_a += dt * 0.2
			var ang := atan2(along.x, along.z) + orbit_a + 0.9
			cands.append(mid + Vector3(sin(ang), 0, cos(ang)) * 5.0 + Vector3(0, 2.0, 0))
			look = mid + Vector3(0, 1.2, 0)
			fov = 46.0
		"foot_wide":
			# getting out of / into the car: the car from the front, turning to follow them
			var car: Vector3 = main.player.global_position
			car.y = 0.0
			cands.append(car + along * 7.5 - out * 2.5 + Vector3(0, 2.4, 0))
			cands.append(car - along * 7.5 - out * 2.5 + Vector3(0, 2.4, 0))
			look = car.lerp(mid, 0.6) + Vector3(0, 1.1, 0)
			fov = 50.0
		"foot_two":
			# two-shot from the road, looking at both (and the vendor) and the buildings behind
			var group: Array = people
			var gm := mid
			if group.size() > people.size():
				gm = Vector3.ZERO
				for r: Rig in group:
					gm += r.global_position
				gm /= group.size()
				gm.y = 0.0
			var spread := 0.0
			for r1: Rig in group:
				for r2: Rig in group:
					spread = maxf(spread, r1.global_position.distance_to(r2.global_position))
			var back := clampf(spread * 1.6 + 2.4, 5.2, 8.0)
			for a: float in [0.6, -0.6, 2.4, -2.4]:
				cands.append(gm - out * back + along * a + Vector3(0, 1.75, 0))
			# from along the pavement, when something stands on the road
			for a: float in [6.5, -6.5]:
				cands.append(gm + along * a - out * 0.4 + Vector3(0, 1.8, 0))
			look = gm + Vector3(0, 1.4, 0)
			fov = 46.0
	if cands.is_empty():
		cands.append(mid - out * 5.2 + Vector3(0, 1.75, 0))
	# street trees and lamp posts have no collision, so look for them separately; cars
	# (a van parked on the road) and walls must not stand in between either
	pos = cands[0]
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for p: Vector3 in cands:
		var q2 := PhysicsRayQueryParameters3D.create(look, p, 1 | 4)
		q2.exclude = [main.player.get_rid()]
		if not _post_between(look, p) and space.intersect_ray(q2).is_empty():
			pos = p
			break
	var from := mid + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, pos, 1)
	q.exclude = [main.player.get_rid()]
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = (hit["position"] as Vector3) + (from - pos).normalized() * 0.5
	pos += Vector3(sin(t * 2.3), sin(t * 3.1), sin(t * 1.7)) * 0.01
	cam_pos = pos if cam_new else cam_pos.lerp(pos, 1.0 - exp(-6.0 * dt))
	cam_fov = fov if cam_new else lerpf(cam_fov, fov, 1.0 - exp(-6.0 * dt))
	cam.global_position = cam_pos
	if cam_pos.distance_to(look) > 0.05:
		cam.look_at(look, Vector3.UP)
	cam.fov = cam_fov
	cam_new = false


# The two in the fight going on (attacker, opponent), or [] when nobody is fighting.
func _fighters() -> Array:
	for f: Dictionary in act.fights:
		if f["i"] < f["list"].size():
			var a := _rig_of(f["a"])
			var b := _rig_of(f["list"][f["i"]])
			if a != null and b != null and a.visible and not a.seated:
				return [a, b]
	return []


func _near_car(people: Array, d: float) -> bool:
	var c: Vector3 = main.player.global_position
	for r: Rig in people:
		if Vector2(r.global_position.x - c.x, r.global_position.z - c.z).length() > d:
			return false
	return true


# Whether a street tree or lamp post stands between the camera and what it films.
func _post_between(a: Vector3, b: Vector3) -> bool:
	var pr = main.world.props
	var a2 := Vector3(a.x, 0, a.z)
	var b2 := Vector3(b.x, 0, b.z)
	var key: Vector2i = main.world.block_of(a)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for d: Dictionary in pr.block_props.get(key + Vector2i(dx, dz), []):
				if not d.get("alive", true) or not (d["t"] in ["tree", "lamp"]):
					continue
				var p: Vector3 = d["p"]
				p.y = 0.0
				if p.distance_to(Geometry3D.get_closest_point_to_segment(p, a2, b2)) < 0.6:
					return true
	return false


# Whether this character's head or chest is in the way between the camera and a point.
func _blocks(r: Rig, from: Vector3, to: Vector3) -> bool:
	for p: Vector3 in [r.head.global_position + Vector3(0, 0.25, 0), r.torso.global_position]:
		if p.distance_to(Geometry3D.get_closest_point_to_segment(p, from, to)) < 0.7:
			return true
	return false


# ------------------------------------------------------------ overlay

func _ui(t: float) -> void:
	var a := 1.0 if t < 1.8 else clampf(1.0 - (t - 1.8) / 0.8, 0.0, 1.0)
	ui_title.modulate.a = a
	ui_ep.modulate.a = a
	if done:
		ui_end.modulate.a = clampf((t - done_t) / 0.6, 0.0, 1.0)
