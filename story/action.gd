extends RefCounted
# Story lab: the action side of an episode. Other people's cars (the villains' van), side
# characters getting in and out of them, grabbing somebody and carrying them off, the car
# chase, fist fights with comic-book "DHISHUM!" pops, and the dramatic camera shots.
# The story node owns this and hands it the actions it does not handle itself.
#
#   arrive     {"car", "to": who}      the car drives in and stops on the road beside who
#   exit_car / enter_car  ("who", "car")  side characters (or a kidnapped lead) and a story car
#   grab       {"who", "to"}           who walks up to "to" and carries them off on a shoulder
#   drive_off  {"car"}                 the car speeds off through the city
#   chase      {"car"}                 the leads' car follows it (a lead must be driving)
#   corner     {"car"}                 the car skids to a stop; the leads' car stops behind it
#   fight      {"who", "to": "a,b"}    who fights them one after the other and knocks them out
#   punch      {"who", "to", "ko"}     a single punch
#   look       {"who", "to"}           who turns to look at somebody
#   appear     {"who", "at": ahead | back | near:<who>, "dist"}   a side character walks on
#   shot       {"type": zoom | pov | wide, "who", "to", "dur"}    a dramatic camera shot
# Events: car_arrived, grabbed, fled, cornered, won.

const Van := preload("res://story/van.gd")
const KINDS := ["arrive", "grab", "drive_off", "chase", "corner", "fight", "punch", "look", "appear", "shot"]
const POPS := ["DHISHUM!", "POW!", "BAM!", "DHISHKYAON!"]

var s                        # the story node
var cars := {}               # id -> van
var in_car := {}             # who -> car id: inside a story car (not shown)
var carrying := {}           # carrier -> victim
var boarding := {}           # who -> car id while walking to its door
var fights: Array = []
var chase := ""
var chase_t := 0.0
var cornered := ""
var shot := {}               # a forced camera shot: {"type", "who", "to", "t0", "until"}
var looks := {}              # who -> who they look at
var pops: Array = []         # {"label", "t0"}
var trace_t := 0.0
var stop_wait := 0.0
var corner_next := ""         # cut it off as soon as the car is close enough
var jump_lip := Vector3.INF   # the chase's ramp: the camera films the flight from beside it


func setup(story) -> void:
	s = story
	var defs: Dictionary = s.data.get("cars", {})
	for id: String in defs:
		var c: Dictionary = defs[id]
		var v := Van.new()
		s.main.add_child(v)
		v.setup(s.main, Color.from_string(str(c.get("color", "#2b2b30")), Color(0.17, 0.17, 0.19)))
		v.visible = false
		cars[id] = v


func handles(a: Dictionary) -> bool:
	var kind := str(a["kind"])
	if kind in KINDS:
		return true
	if kind in ["exit_car", "enter_car"]:
		if str(a.get("car", "")) in cars:
			return true
		for k: String in _names(str(a.get("who", ""))):
			if in_car.has(k):
				return true
	return false


func _names(who: String) -> Array:
	var out := []
	for k in who.split(","):
		k = k.strip_edges()
		if k == "both":
			out.append_array(s.rigs.keys())
		elif k != "" and s._rig_of(k) != null:
			out.append(k)
	return out


func _event(kind: String, t: float) -> void:
	s.ev_log.append({"type": kind, "t": t})
	print("STORYEVENT ", kind, " t=", snappedf(t, 0.01))


func hidden(who: String) -> bool:
	return in_car.has(who)


# One action; true when it is done (or cannot happen), false to try again next frame.
func run(a: Dictionary, t: float) -> bool:
	var kind := str(a["kind"])
	var who := str(a.get("who", ""))
	var to := str(a.get("to", ""))
	var car_id := str(a.get("car", ""))
	var v = cars.get(car_id, null)
	match kind:
		"arrive":
			if v == null:
				return true
			if s.street == null:
				return false              # the car arrives where the story has stopped
			if not a.has("_started"):
				a["_started"] = true
				var tr = s._rig_of(to)
				var at: float = s.street.along(tr.global_position) if tr != null else s.street.along(s.main.player.global_position) + 8.0
				var fwd: Vector3 = s.street.dir
				var f: float = fwd.x + fwd.z
				var stop: Vector3 = s.street.point(at, -4.0)
				# in on the far lane past the parked car, then over to the kerb
				v.place(s.street.point(at - 70.0 * f, -11.9), fwd)
				v.path.assign([s.street.point(at - 16.0 * f, -11.9), stop])
				v.stop_point = stop
				v.mode = "arrive"
				v.speed = 18.0
				v.visible = true
				s.main.play_sfx("screech", stop, -10.0)
				# film it pulling up
				shot = {"type": "car", "car": car_id, "t0": t, "until": t + 3.6}
				s.cam_new = true
				return false
			if v.mode == "parked":
				_event("car_arrived", t)
				return true
			return false
		"exit_car":
			var names := _names(who) if who != "all" else in_car.keys().filter(func(k: String) -> bool: return in_car[k] == car_id)
			for k: String in names:
				if not in_car.has(k):
					continue
				var c = cars[in_car[k]]
				var r = s._rig_of(k)
				in_car.erase(k)
				r.visible = true
				var side := _kerb_side(c)
				var at: Vector3 = c.door(side)
				var out: Vector3 = c.forward().cross(Vector3.UP) * side
				r.stand_at(at, atan2(-out.x, -out.z))
				r.walk_to([at + out * 1.2])
				r.set_state("angry" if k.begins_with("goon") else "shock", "idle", false)
			_event("exited", t)
			return true
		"enter_car":
			if v == null:
				return true
			if not a.has("_started"):
				a["_started"] = true
				for k: String in _names(who):
					var r = s._rig_of(k)
					r.stand_up()
					r.walk_to([v.door(_kerb_side(v))], true)
					boarding[k] = car_id
				return false
			for k: String in boarding.keys():
				var r = s._rig_of(k)
				if r.arrived() or r.global_position.distance_to(v.door(_kerb_side(v))) < 1.0:
					_board(k, boarding[k])
					boarding.erase(k)
			if boarding.is_empty():
				_event("seated", t)
				return true
			return false
		"grab":
			var g = s._rig_of(who)
			var victim = s._rig_of(to)
			if g == null or victim == null:
				return true
			var d: Vector3 = victim.global_position - g.global_position
			d.y = 0.0
			if d.length() > 1.0:
				if g.arrived():
					g.stand_up()
					g.walk_to(_route(g.global_position, _outside(victim.global_position - d.normalized() * 0.7)), true)
				return false
			if not g.arrived():
				return false
			if victim.seated:
				return true
			victim.reparent(g.torso, false)
			victim.be_carried()
			carrying[who] = to
			_pop("AAAH!", victim.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.5, 0.6))
			_event("grabbed", t)
			return true
		"drive_off":
			if v == null:
				return true
			v.flee()
			v.top = 12.0         # not too far before the chase starts
			s.main.play_sfx("screech", v.global_position, -6.0)
			_event("fled", t)
			return true
		"chase":
			if v == null:
				return true
			chase = car_id
			chase_t = 0.0
			s._drive_on()
			s.main.bot.external = true
			if s.main.director != null:
				s.main.director.still = false
			return true
		"corner":
			if v == null:
				return true
			# it is cut off once the car has caught up with it, so they stop close together
			stop_wait = 0.0
			corner_next = car_id
			return true
		"fight":
			var targets := _names(to)
			if s._rig_of(who) == null or targets.is_empty():
				return true
			fights.append({"a": who, "list": targets, "i": 0, "phase": "approach", "t0": t})
			return true
		"punch":
			var pa = s._rig_of(who)
			var pb = s._rig_of(to)
			if pa == null or pb == null:
				return true
			fights.append({"a": who, "list": [to], "i": 0, "phase": "one", "t0": t, "ko": bool(a.get("ko", false))})
			return true
		"look":
			if to == "":
				looks.erase(who)
			else:
				for k: String in _names(who):
					looks[k] = to
			return true
		"appear":
			if s.street == null:
				return false
			var r = s._rig_of(who)
			if r == null:
				return true
			s._place_on_foot(who, str(a.get("at", "ahead")), float(a.get("dist", 10.0)))
			return true
		"shot":
			shot = {"type": str(a.get("type", "zoom")), "who": who, "to": to, "t0": t,
				"until": t + clampf(float(a.get("dur", 2.4)), 0.8, 6.0)}
			s.cam_new = true
			if shot["type"] == "zoom":
				s.main.slowmo(1.0, 0.5)
			return true
	return true


# The van's trail cut down to its corners, so the driver sees each turn coming (a point every
# 3 m hides the corners: it would take them flat out and run wide onto the grass).
func _corners(pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out := [pts[0]]
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[i] - out.back()
		var b: Vector3 = pts[i + 1] - pts[i]
		a.y = 0.0
		b.y = 0.0
		if a.length() > 0.1 and b.length() > 0.1 and absf(a.signed_angle_to(b, Vector3.UP)) > 0.2:
			out.append(pts[i])
	out.append(pts.back())
	return out


# A jump in the middle of a chase: a kicker ramp on the van's road, so the van flies off
# it first and the chasing car after it. False while the van's straight is too short.
func chase_jump() -> bool:
	var v = cars[chase]
	if v.path.is_empty() or v.speed < 12.0:
		return false
	var room: float = v.global_position.distance_to(v.path[0])
	var f: Vector3 = v.forward()
	if room < 50.0 or (absf(f.x) < 0.97 and absf(f.z) < 0.97):
		return false              # not on a long straight yet
	var origin: Vector3 = v.global_position + v.forward() * 22.0
	origin.y = 0.0
	var info: Dictionary = s.main.stunts.build_kicker(origin, v.forward())
	jump_lip = info["lip"]
	return true


# The van's side toward the pavement (+1 right of its heading).
func _kerb_side(c) -> float:
	if s.street == null:
		return 1.0
	var right: Vector3 = c.forward().cross(Vector3.UP)
	return 1.0 if right.dot(s.street.outward()) > 0.0 else -1.0


func _board(k: String, car_id: String) -> void:
	var r = s._rig_of(k)
	in_car[k] = car_id
	r.visible = false
	r.path.clear()
	if carrying.has(k):
		var victim = s._rig_of(carrying[k])
		carrying.erase(k)
		victim.reparent(s.main, true)
		victim.rotation = Vector3.ZERO
		victim.pose = "stand"
		victim.visible = false
		in_car[victim.who] = car_id


func tick(dt: float, t: float) -> void:
	_chase_tick(dt, t)
	_fight_tick(t)
	# nobody walks into (or is knocked back into) a parked van
	for r in s.rigs.values() + s.extras.values():
		if r.visible and not r.seated and r.pose != "carried":
			for v in cars.values():
				if v.visible and v.speed < 0.5:
					_keep_out(r, v)
	for p: Dictionary in pops.duplicate():
		var l: Label3D = p["label"]
		var k := (t - float(p["t0"])) / 0.9
		if k >= 1.0 or not is_instance_valid(l):
			if is_instance_valid(l):
				l.queue_free()
			pops.erase(p)
			continue
		l.scale = Vector3.ONE * (0.6 + 0.8 * minf(k * 5.0, 1.0))
		l.modulate.a = 1.0 if k < 0.7 else (1.0 - k) / 0.3
		l.outline_modulate.a = l.modulate.a
		l.position.y += dt * 0.6
	if not shot.is_empty() and t > float(shot["until"]):
		shot = {}
		s.cam_new = true


# The leads' car follows the van's trail, keeping a gap; stops behind it once it is cornered.
func _chase_tick(dt: float, t: float) -> void:
	if chase == "":
		return
	var v = cars[chase]
	var bot = s.main.bot
	var pl: Car = s.main.player
	chase_t -= dt
	var trail: Array[Vector3] = v.trail
	var pp := pl.global_position
	# the trail point nearest the car, and the distance along the trail to the van
	var best := 0
	var bd := 1e9
	for i in trail.size():
		var d := pp.distance_to(trail[i])
		if d < bd:
			bd = d
			best = i
	var gap := bd
	for i in range(best, trail.size() - 1):
		gap += trail[i].distance_to(trail[i + 1])
	gap += trail.back().distance_to(v.global_position) if not trail.is_empty() else 0.0
	if corner_next == chase:
		v.top = minf(v.top, 15.0)
		if gap < 34.0 or stop_wait > 8.0:
			corner_next = ""
			v.spin = 0.8
			v.stop_here()
			cornered = chase
			stop_wait = 0.0
			s.main.play_sfx("screech", v.global_position, -4.0)
		else:
			stop_wait += dt
	var stopped: bool = cornered == chase and v.stopped()
	if chase_t <= 0.0 and best + 1 < trail.size():
		chase_t = 0.5
		var pts := _corners(trail.slice(best + 1))
		if stopped:
			# pull up behind it, not alongside: the plan ends a car length or two short
			while pts.size() > 1 and (pts.back() as Vector3).distance_to(v.global_position) < 11.0:
				pts.pop_back()
		else:
			pts.append(v.global_position)
		var kinds := []
		for i in pts.size():
			kinds.append("road")
		bot.set_plan(pts, kinds, "chase")
	trace_t -= dt
	if trace_t <= 0.0:
		trace_t = 2.0
		print("STORYCHASE t=%.1f van=%s mode=%s v=%.1f gap=%.1f car_v=%.1f plan=%s" % [t, str(v.global_position.snapped(Vector3.ONE)), v.mode, v.speed, gap, pl.speed, bot.plan_name])
	if stopped:
		stop_wait += dt
		# how far behind the van the car is, along the van's road (negative: already past it)
		var behind: float = (v.global_position - pp).dot(v.forward())
		bot.cruise = minf(sqrt(2.0 * 4.0 * maxf(gap - 13.0, 0.0)), 20.0)
		if behind < 24.0 or gap < 24.0:
			bot.halt = true
		if pl.speed < 0.6 and (bot.halt or stop_wait > 8.0):
			chase = ""
			bot.external = false
			bot.halt = true
			s._park_now(t)
			_event("cornered", t)
	else:
		bot.cruise = clampf(v.speed + (gap - 20.0) * 0.6, 6.0, 42.0)
		# the van eases off when the car falls behind and pulls away when it gets close,
		# so the chase stays tight and on screen
		v.top = clampf(27.0 - (gap - 25.0) * 0.18, 13.0, 28.0)


# Fights: walk up, trade punches, the last one knocks them out. Comic pops on every hit.
func _fight_tick(t: float) -> void:
	for f: Dictionary in fights.duplicate():
		var a = s._rig_of(f["a"])
		if f["i"] >= f["list"].size():
			fights.erase(f)
			a.set_pose("stand")
			a.set_state("smug", "idle", false)
			if fights.is_empty():
				_event("won", t)
			continue
		if a.seated or not a.visible:
			continue                  # still getting out of the car
		var b = s._rig_of(f["list"][f["i"]])
		if b == null or b.pose == "ko":
			f["i"] += 1
			f["phase"] = "approach"
			continue
		var el := t - float(f["t0"])
		a.face_point = b.global_position
		b.face_point = a.global_position
		match f["phase"]:
			"approach", "one":
				var d: Vector3 = b.global_position - a.global_position
				d.y = 0.0
				if d.length() > 1.4:
					if a.arrived():
						# they come at each other and meet in the middle
						var mid: Vector3 = (a.global_position + b.global_position) * 0.5
						var far: bool = d.length() > 4.0 and not b.seated and b.visible
						a.walk_to(_route(a.global_position, _outside((mid if far else b.global_position) - d.normalized() * 0.55)), true)
						if far:
							b.walk_to(_route(b.global_position, _outside(mid + d.normalized() * 0.55)), true)
					continue
				if not a.arrived():
					continue
				a.set_pose("fight")
				b.set_pose("fight")
				a.set_state("angry", "idle", false)
				b.set_state("angry", "idle", false)
				f["phase"] = "trade" if f["phase"] == "approach" else "single"
				f["t0"] = t
				f["step"] = 0
				print("STORYFIGHT ", f["a"], " vs ", f["list"][f["i"]], " t=", snappedf(t, 0.01))
			"single":
				if f["step"] == 0 and el > 0.25:
					a.set_pose("punch")
					f["step"] = 1
				elif f["step"] == 1 and el > 0.45:
					_hit(b, bool(f.get("ko", false)), t)
					f["step"] = 2
				elif f["step"] == 2 and el > 1.2:
					f["i"] = f["list"].size()
			"trade":
				# A punches, B is hit; B punches back, A is hit; A's big punch knocks B out
				var steps := [[0.35, "a_punch"], [0.55, "b_hit"], [1.35, "b_punch"], [1.55, "a_hit"],
					[2.3, "a_punch"], [2.5, "b_ko"], [3.4, "next"]]
				var i: int = f["step"]
				if i < steps.size() and el > float(steps[i][0]):
					match str(steps[i][1]):
						"a_punch":
							a.set_pose("punch")
						"b_punch":
							b.set_pose("punch")
						"b_hit":
							_hit(b, false, t)
						"a_hit":
							_hit(a, false, t)
						"b_ko":
							_hit(b, true, t)
						"next":
							f["i"] += 1
							f["phase"] = "approach"
							a.set_pose("stand")
					f["step"] = i + 1


func _keep_out(r, v) -> void:
	var p := _out_of(v, r.global_position, 0.35)
	r.global_position = Vector3(p.x, r.global_position.y, p.z)


# The point moved out of a stopped car's box (through its nearest side), with a margin.
func _out_of(v, at: Vector3, margin: float) -> Vector3:
	var lp: Vector3 = v.to_local(at)
	var hx := 1.1 + margin
	var hz := 2.6 + margin
	if absf(lp.x) < hx and absf(lp.z) < hz:
		if hx - absf(lp.x) < hz - absf(lp.z):
			lp.x = hx * signf(lp.x if lp.x != 0.0 else 1.0)
		else:
			lp.z = hz * signf(lp.z if lp.z != 0.0 else 1.0)
		var p: Vector3 = v.to_global(lp)
		return Vector3(p.x, at.y, p.z)
	return at


# A way from a to b that goes round a parked car instead of through it: via the corner of
# the car (with room to spare) that makes the shortest detour.
func _route(a: Vector3, b: Vector3) -> Array:
	for v in cars.values():
		if not v.visible or v.speed > 0.5:
			continue
		var la: Vector3 = v.to_local(a)
		var lb: Vector3 = v.to_local(b)
		var blocked := false
		for i in range(1, 10):
			var p := la.lerp(lb, i / 10.0)
			if absf(p.x) < 1.3 and absf(p.z) < 2.8:
				blocked = true
				break
		if not blocked:
			continue
		var best := Vector3.INF
		var bl := 1e9
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var c := Vector3(cx * 2.0, 0, cz * 3.5)
				var l := la.distance_to(c) + c.distance_to(lb)
				if l < bl:
					bl = l
					best = c
		var w: Vector3 = v.to_global(best)
		return [Vector3(w.x, 0, w.z), b]
	return [b]


# Somewhere to walk to that is not inside a parked car.
func _outside(at: Vector3) -> Vector3:
	for v in cars.values():
		if v.visible and v.speed < 0.5:
			at = _out_of(v, at, 0.6)
	return at


func _hit(r, ko: bool, t: float) -> void:
	r.set_pose("ko" if ko else "hit")
	r.set_state("shock" if not ko else "sad", "idle", false)
	var at: Vector3 = r.head.global_position + Vector3(0, 0.5, 0)
	_pop(POPS[randi() % POPS.size()] if not ko else "KO!", at, Color(1.0, 0.85, 0.1) if not ko else Color(1.0, 0.25, 0.2))
	s.main.play_sfx("crash_a", at, -14.0 if not ko else -8.0)
	s.main.shake_cam(0.35 if not ko else 0.8)
	if ko:
		s.main.slowmo(0.9, 0.35)


func _pop(text: String, at: Vector3, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 120
	l.outline_size = 26
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_modulate = Color(0.05, 0.02, 0.02)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	s.main.add_child(l)
	l.global_position = at
	pops.append({"label": l, "t0": s.main.clock})
