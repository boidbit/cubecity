extends SceneTree
# Headless physics test: what a street lamp or a tree does to the player's car.
# Run it with tools/test_props.sh <godot binary> (CI does). It exits 1 if anything fails.
#
# The car is put on the road next to a strip of pavement with nothing behind the prop (no building to
# run into), left to settle on its suspension, given a speed and let go to coast into one lamp or tree.
# Every case with a speed check is run twice on the same strip: first as a "control" with the prop
# switched off, which shows what the car does anyway, then for real. The ratio of the two speeds half a
# second after the hit is the share of its speed the car kept. The test checks that:
#   - a lamp or a tree hit head-on at 15, 25 and 35 m/s is knocked down, the car keeps most of its
#     speed (lamp 70..97 %, tree 60..95 %: it is slowed a bit, never stopped) and is not flipped;
#   - the fallen prop is on a collision layer the car does not touch (as a solid 60 kg box inside
#     the car's nose it used to stop a car doing 25 m/s dead);
#   - driving past a lamp with a metre of air between them hits nothing, brushing it does;
#   - a car crawling at 3.5 m/s that runs into a lamp or a tree hits it (they are not ghosts).
#
# A strip is only used if a physics query finds nothing solid in the way and the ground flat (a strip
# that is not is printed as INFO and another one is taken). A run in which the car still touches
# something else before the prop, or leaves the ground, is thrown away (printed as SKIP) and the case
# is tried on another strip; a case that gets no usable run in four tries fails, and so does a test
# that has to throw away more than MAX_SKIPS runs. The car cannot shed a bumper (its detachable
# parts are removed), which would lie in its path.

const RUN_UP := 13.0        # metres from the start to the prop (the start is on the road)
const BEHIND := 40.0        # clear metres wanted behind the prop when choosing a strip
const AHEAD := 36.0         # metres past the prop the physics query checks (a car at 35 m/s covers them in a second)
const AFTER := 1.2          # seconds recorded after the hit
const ATTEMPTS := 4         # strips tried for a case before it is called a failure
const MAX_SKIPS := 12       # more unusable strips than this over the whole test is a failure too
const CAR_HALF_W := 0.91    # the car's footprint, as in Car.build (kept apart from the game's constants
const CAR_HALF_L := 2.05    # on purpose: the test must say what is right, not repeat what the game says)

var main
var world: World
var props: Props
var player: Car
var passed := 0
var failed := 0
var skipped := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)      # its _ready runs when the tree starts, so world and player are fetched in _run
	_run.call_deferred()


func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ty in ["lamp", "tree"]:
		for v in [15.0, 25.0, 35.0]:
			out.append({"name": "%s head-on at %d m/s" % [ty, int(v)], "type": ty, "v0": v, "breaks": true,
				"lo": 0.70 if ty == "lamp" else 0.60, "hi": 0.97 if ty == "lamp" else 0.95})
	out.append({"name": "lamp passed with a metre of air (centre 1.9 m)", "type": "lamp", "v0": 20.0, "graze": 1.9, "breaks": false})
	out.append({"name": "lamp brushed by the side of the car (centre 0.7 m)", "type": "lamp", "v0": 20.0, "graze": 0.7, "breaks": true,
		"lo": 0.80, "hi": 0.99})
	for ty in ["lamp", "tree"]:
		# a short run-up: a coasting car loses speed, and it must still be doing more than 2 m/s on arrival
		out.append({"name": "%s at 3.5 m/s is not a ghost" % ty, "type": ty, "v0": 3.5, "breaks": true, "run_up": 4.0})
	return out


func _run() -> void:
	for i in 30:
		await process_frame
	world = main.world
	props = world.props
	player = main.player
	main.traffic_cap = 0
	for c in _cases():
		await _run_case(c)
	if skipped > MAX_SKIPS:
		_fail("strips", "%d runs had to be thrown away (more than %d): the pavement near the props is not as clean as the test assumes" % [skipped, MAX_SKIPS])
	var line := "RESULT: %d passed, %d failed" % [passed, failed]
	if skipped > 0:
		line += " (%d runs thrown away and repeated on another strip)" % skipped
	print(line)
	quit(1 if failed > 0 else 0)


func _run_case(c: Dictionary) -> void:
	var why := ""
	var spoilt := 0              # runs thrown away because something else got in the car's way
	var rejected := 0            # strips turned down before a run (not clean)
	while spoilt < ATTEMPTS and rejected < 30:
		var strip := _pick(c)
		if strip.is_empty():
			_fail(c["name"], "no clean strip of pavement left to test on")
			return
		var ctl := {}
		if c.has("lo"):
			ctl = await _drive(c, strip, true)
			if not ctl["ok"]:
				why = "control run: " + str(ctl["why"])
				if ctl["pre"]:
					rejected += 1
					print("INFO  ", c["name"], ": strip turned down, ", why)
				else:
					spoilt += 1
					_skip(c["name"], why)
				continue
		var real := await _drive(c, strip, false)
		if not real["ok"]:
			why = str(real["why"])
			if real["pre"]:
				rejected += 1
				print("INFO  ", c["name"], ": strip turned down, ", why)
			else:
				spoilt += 1
				_skip(c["name"], why)
			continue
		_evaluate(c, ctl, real)
		return
	_fail(c["name"], "no usable strip (%d runs spoilt, %d strips turned down), the last: %s" % [spoilt, rejected, why])


# ------------------------------------------------------------ finding a clean strip

func _seg_dist(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(pt.x, pt.z)
	var pa := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - pa
	var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(pa + ab * t)


# The way the car drives at this prop, or {} if the strip is not worth trying.
func _geo(key: Vector2i, d: Dictionary, c: Dictionary) -> Dictionary:
	var pos: Vector3 = d["p"]
	var xa: float = world.line(key.x)
	var xb: float = world.line(key.x + 1)
	var za: float = world.line(key.y)
	var zb: float = world.line(key.y + 1)
	var perp := Vector3.ZERO     # from the road toward the prop (props stand 8.3 m in from the road's centre line)
	if absf(pos.x - (xa + 8.3)) < 0.01:
		perp = Vector3(1, 0, 0)
	elif absf(pos.x - (xb - 8.3)) < 0.01:
		perp = Vector3(-1, 0, 0)
	elif absf(pos.z - (za + 8.3)) < 0.01:
		perp = Vector3(0, 0, 1)
	elif absf(pos.z - (zb - 8.3)) < 0.01:
		perp = Vector3(0, 0, -1)
	else:
		return {}
	var along := perp.cross(Vector3.UP)
	var heading := perp
	var run_up: float = c.get("run_up", RUN_UP)
	var start := pos - perp * run_up
	var end := pos + perp * BEHIND
	var length := run_up + AHEAD
	if c.has("graze"):
		heading = along
		start = pos - perp * float(c["graze"]) - along * run_up
		end = pos + along * 14.0
		length = run_up + 14.0
	start.y = 0.9
	# not on the railway row
	var rz: float = main.rail.z
	for q: Vector3 in [start, pos, end]:
		if absf(q.z - rz) < 20.0:
			return {}
	# no building near the way (3.5 m of room each side)
	var lo := Vector3(minf(start.x, end.x), 0, minf(start.z, end.z))
	var hi := Vector3(maxf(start.x, end.x), 0, maxf(start.z, end.z))
	for b: Building in world.buildings:
		var x0 := b.origin.x - 3.5
		var x1 := b.origin.x + b.nx * Building.C + 3.5
		var z0 := b.origin.z - 3.5
		var z1 := b.origin.z + b.nz * Building.C + 3.5
		if hi.x > x0 and lo.x < x1 and hi.z > z0 and lo.z < z1:
			return {}
	# other lamps and trees on the way are switched off; anything else near it (cars, barrels,
	# pickups, a gas station) makes the strip unusable
	var off := []
	for k2 in props.block_props:
		for o: Dictionary in props.block_props[k2]:
			if o == d or not o["alive"]:
				continue
			var dd := _seg_dist(o["p"], start, end)
			if o["t"] == "tree" or o["t"] == "lamp":
				if dd < 3.5:
					off.append(o)
			elif dd < 12.0:
				return {}
	return {"prop": d, "heading": heading, "start": start, "off": off, "length": length}


func _pick(c: Dictionary) -> Dictionary:
	for key in props.block_props:
		for d: Dictionary in props.block_props[key]:
			if d["t"] != c["type"] or not d["alive"] or d.get("used", false):
				continue
			var g := _geo(key, d, c)
			if g.is_empty():
				continue
			d["used"] = true
			return g
	return {}


# Asks the physics engine whether anything solid is in the car's way along the strip, and whether
# the ground is flat there. "" if all is well, else what is wrong. The car must be placed and the
# blocks around it loaded.
func _strip_clear(strip: Dictionary) -> String:
	var space := player.get_world_3d().direct_space_state
	var h: Vector3 = strip["heading"]
	var start: Vector3 = strip["start"]
	var side := h.cross(Vector3.UP)
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.4, 5.0)           # the car (1.82 x 4.1 m) with room to spare, clear of the ground
	var ex: Array[RID] = [player.get_rid()]
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | 2 | 4
	q.exclude = ex
	var yaw := atan2(-h.x, -h.z)
	var d := 0.0
	while d <= float(strip["length"]):
		var at := start + h * d
		q.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 1.2, at.z))
		var hits := space.intersect_shape(q, 4)
		if not hits.is_empty():
			var col := hits[0]["collider"] as Node
			return "something solid %.0f m along the strip: %s '%s'" % [d, col.get_class(), col.name]
		for off: float in [-0.9, 0.0, 0.9]:
			var p := at + side * off
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 3.0, p.z), Vector3(p.x, -2.0, p.z), 1))
			if r.is_empty() or absf((r["position"] as Vector3).y) > 0.08:
				return "the ground is not flat %.0f m along the strip" % d
		d += 2.0
	return ""


func _radius(d: Dictionary) -> float:
	return 0.24 * float(d["s"]) if d["t"] == "tree" else 0.12


# ------------------------------------------------------------ one run

func _place(h: Vector3, at: Vector3, v: Vector3) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, atan2(-h.x, -h.z)), at)
	player.linear_velocity = v
	player.angular_velocity = Vector3.ZERO
	player.steering = 0.0
	player.steer_smooth = 0.0


# One run on a strip: settle, check the strip, release the car, record until it is past the prop.
# Returns {"ok": false, "why", "pre"} if the run is no use ("pre": the strip was turned down before
# the car was let go; else the car touched something else on its way), else everything _evaluate needs.
func _drive(c: Dictionary, strip: Dictionary, control: bool) -> Dictionary:
	var prop: Dictionary = strip["prop"]
	var h: Vector3 = strip["heading"]
	var start: Vector3 = strip["start"]
	for o: Dictionary in strip["off"]:
		o["alive"] = false
	prop["alive"] = not control
	for civ in main.civs.duplicate():
		if is_instance_valid(civ):
			civ.queue_free()
	main.civs.clear()
	for cop in main.police.duplicate():
		if is_instance_valid(cop):
			cop.queue_free()
	main.police.clear()
	main.heat = 0.0
	main.level = 0
	main.game_over = false
	main.hud.in_gas = 0.0
	main.hud.in_steer = 0.0
	player.dead = false
	player.hp = 100.0
	player.last_hurt = main.clock
	player.parts.clear()
	_place(h, start, Vector3.ZERO)
	world.load_around(start, true)
	# let the car sit on its suspension, once, without being moved again
	var rested := 0
	var waited := 0
	while rested < 40 and waited < 300:
		await physics_frame
		waited += 1
		if player.linear_velocity.length() < 0.15 and player.airtime == 0.0:
			rested += 1
		else:
			rested = 0
	if rested < 40:
		return {"ok": false, "why": "the car would not settle on the strip", "pre": true}
	var bad := _strip_clear(strip)
	if bad != "":
		return {"ok": false, "why": bad, "pre": true}

	var known := {}                              # debris nodes that exist already (older ones are freed after 8 s)
	for n in world.debris_root.get_children():
		known[n.get_instance_id()] = true
	# let go: only the speed is set, the car stays where it settled (putting it back at the start height
	# would lift it off its wheels)
	player.linear_velocity = h * float(c["v0"])
	player.angular_velocity = Vector3.ZERO
	var rec: Array = []
	var touched := {}
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var te := -1.0                               # when the prop was hit (control: when the car would have hit it)
	var first_contact := -1.0
	var air := 0.0                               # the longest the car was off the ground before the hit
	var near := 1e9
	var near_info := ""
	var pp: Vector3 = prop["p"]
	var r := _radius(prop)
	while true:
		await physics_frame
		t += dt
		var lp: Vector3 = player.global_transform.affine_inverse() * pp
		var s := (player.global_position - start).dot(h)
		var up := player.global_transform.basis.y
		rec.append({"t": t, "v": player.linear_velocity.length(), "tilt": rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))})
		for b in player.get_colliding_bodies():
			if first_contact < 0.0:
				first_contact = t
			var key := "%s '%s' at (%.0f, %.0f)" % [b.get_class(), b.name, b.global_position.x, b.global_position.z]
			if not touched.has(key):
				touched[key] = "t=%.2f s, car doing %.1f m/s" % [t, player.linear_velocity.length()]
		if te < 0.0:
			air = maxf(air, player.airtime)
			if control:
				if absf(lp.x) < CAR_HALF_W + r and absf(lp.z) < CAR_HALF_L + r:
					te = t
			elif not prop["alive"]:
				te = t
		if absf(lp.z) < near:
			near = absf(lp.z)
			near_info = "closest at t=%.2f s: prop %.2f m beside the car's axis and %.2f m along it, car doing %.1f m/s, in the air %s" % [
				t, lp.x, lp.z, player.linear_velocity.length(), str(player.airtime > 0.0)]
		if (te >= 0.0 and t > te + AFTER) or s > float(strip["length"]) or t > 14.0 or (t > 1.0 and player.linear_velocity.length() < 0.2):
			break

	var out := {"ok": true, "why": "", "pre": false, "rec": rec, "te": te, "broke": not prop["alive"], "near_info": near_info, "touched": touched}
	# the fallen prop must not collide with the car; then it is put out of the way of the next run
	var found := 0
	var solid := 0
	for n in world.debris_root.get_children():
		var rb := n as RigidBody3D
		if rb != null and not known.has(rb.get_instance_id()) and absf(rb.mass - 60.0) < 0.01:
			found += 1
			if (rb.collision_layer & player.collision_mask) != 0 or (player.collision_layer & rb.collision_mask) != 0:
				solid += 1
			rb.freeze = true
			rb.collision_layer = 0
			rb.collision_mask = 0
			rb.visible = false
	out["found"] = found
	out["solid"] = solid
	# was the run spoilt by something other than the prop?
	var cutoff := te + (0.8 if control else 0.0)   # (the control must stay clear while it is measured)
	if player.dead or main.game_over:
		out["ok"] = false
		out["why"] = "the car was wrecked"
	elif first_contact >= 0.0 and (te < 0.0 or first_contact < cutoff):
		out["ok"] = false
		out["why"] = "the car touched something else on the way: %s" % str(touched)
	elif air > 0.15:
		out["ok"] = false
		out["why"] = "the car left the ground before the prop (%.2f s)" % air
	elif control and te < 0.0:
		out["ok"] = false
		out["why"] = "the car never reached the prop"
	return out


# ------------------------------------------------------------ judging a case

func _v_at(rec: Array, t: float) -> float:
	var best: Dictionary = rec[0]
	for x: Dictionary in rec:
		if absf(float(x["t"]) - t) < absf(float(best["t"]) - t):
			best = x
	return float(best["v"])


func _evaluate(c: Dictionary, ctl: Dictionary, real: Dictionary) -> void:
	var problems: Array[String] = []
	var notes: Array[String] = []
	var broke: bool = real["broke"]
	if broke != bool(c["breaks"]):
		problems.append("the prop %s but should %s" % ["was knocked down" if broke else "was not hit", "have been hit" if c["breaks"] else "not have been hit"])
	if broke:
		notes.append("knocked down")
		var te: float = real["te"]
		var rec: Array = real["rec"]
		if c.has("lo"):
			var v_real := _v_at(rec, te + 0.5)
			var v_ctl := _v_at(ctl["rec"], float(ctl["te"]) + 0.5)
			var ratio := v_real / maxf(v_ctl, 0.1)
			notes.append("kept %d%% of its speed 0.5 s later (%.1f of %.1f m/s)" % [int(round(ratio * 100.0)), v_real, v_ctl])
			if ratio < float(c["lo"]) or ratio > float(c["hi"]):
				problems.append("speed kept %d%%, wanted %d..%d%%" % [int(round(ratio * 100.0)), int(round(float(c["lo"]) * 100.0)), int(round(float(c["hi"]) * 100.0))])
		var tilt := 0.0
		for x: Dictionary in rec:
			if float(x["t"]) >= te - 0.05 and float(x["t"]) <= te + 0.9:
				tilt = maxf(tilt, float(x["tilt"]))
		if tilt > 25.0:
			problems.append("the car tilted %d degrees (flipped or launched)" % int(tilt))
		if int(real["found"]) == 0:
			problems.append("no fallen prop found to check")
		elif int(real["solid"]) > 0:
			problems.append("the fallen prop collides with the car (it stops the car dead)")
	if problems.is_empty():
		_pass(c["name"], ", ".join(notes) if not notes.is_empty() else "no hit")
	else:
		_fail(c["name"], "; ".join(problems) + " [" + str(real["near_info"]) + "] touched: " + str(real["touched"]))


func _pass(name: String, detail: String) -> void:
	passed += 1
	print("PASS  ", name, ": ", detail)


func _fail(name: String, why: String) -> void:
	failed += 1
	print("FAIL  ", name, ": ", why)


func _skip(name: String, why: String) -> void:
	skipped += 1
	print("SKIP  ", name, ": ", why)
