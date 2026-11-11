extends SceneTree
# Headless physics test: what a street lamp or a tree does to the player's car.
# Run it with tools/test_props.sh <godot binary> (CI does). It exits 1 if anything fails.
#
# The car is put on the road next to a strip of pavement with nothing behind the prop (no
# building to run into), given a speed and left to coast into one lamp or tree. Every case with
# a speed check is run twice on the same strip: first as a "control" with the prop switched off,
# which shows what the car does anyway, then for real. The ratio of the two speeds half a second
# after the hit is the share of its speed the car kept. The test checks that:
#   - a lamp or a tree hit head-on at 15, 25 and 35 m/s is knocked down, the car keeps most of its
#     speed (lamp 70..97 %, tree 60..95 %: it is slowed a bit, never stopped) and is not flipped;
#   - the fallen prop is on a collision layer the car does not touch (as a solid 60 kg box inside
#     the car's nose it used to stop a car doing 25 m/s dead);
#   - driving past a lamp with a metre of air between them hits nothing, brushing it does;
#   - a car crawling at 3.5 m/s that runs into a lamp or a tree hits it (they are not ghosts).
# Only strips beside a park (no buildings) are used, so the speed is never the building's doing.

const RUN_UP := 13.0      # metres from the start to the prop (the start is on the road)
const BEHIND := 40.0      # clear metres wanted behind the prop
const SETTLE := 40        # frames the car stands still while the blocks around it stream in
const AFTER := 3.0        # seconds recorded after the hit
const CAR_HALF_W := 0.91  # the car's footprint, as in Car.build (kept apart from the game's constants
const CAR_HALF_L := 2.05  # on purpose: the test must say what is right, not repeat what the game says)

var main
var world: World
var props: Props
var player: Car
var frames := 0
var runs: Array[Dictionary] = []
var ri := -1
var cur: Dictionary = {}          # the run being recorded
var prop: Dictionary = {}         # the prop of the case (its control run and its real run share it)
var geo: Dictionary = {}
var phase := "boot"
var settle := 0
var control: Dictionary = {}      # the control run's result, for the real run that follows
var debris_known := {}            # the debris nodes that existed before the run (older ones are freed after 8 s)
var passed := 0
var failed := 0
var expected := 0                 # cases (a case is one real run); every one must pass or fail


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)      # its _ready runs when the tree starts, so world and player are fetched in _process
	for ty in ["lamp", "tree"]:
		for v in [15.0, 25.0, 35.0]:
			_add_case({"name": "%s head-on at %d m/s" % [ty, int(v)], "type": ty, "v0": v, "breaks": true,
				"lo": 0.70 if ty == "lamp" else 0.60, "hi": 0.97 if ty == "lamp" else 0.95})
	_add_case({"name": "lamp passed with a metre of air (centre 1.9 m)", "type": "lamp", "v0": 20.0, "graze": 1.9, "breaks": false})
	_add_case({"name": "lamp brushed by the side of the car (centre 0.7 m)", "type": "lamp", "v0": 20.0, "graze": 0.7, "breaks": true,
		"lo": 0.80, "hi": 0.99})
	for ty in ["lamp", "tree"]:
		# a short run-up: a coasting car loses speed, and it must still be doing more than 2 m/s on arrival
		_add_case({"name": "%s at 3.5 m/s is not a ghost" % ty, "type": ty, "v0": 3.5, "breaks": true, "slow": true, "run_up": 4.0})


func _add_case(c: Dictionary) -> void:
	expected += 1
	if c.has("lo"):
		var ctl := c.duplicate()
		ctl["control"] = true
		ctl["reuse"] = false
		runs.append(ctl)
	var real := c.duplicate()
	real["control"] = false
	real["reuse"] = c.has("lo")      # a real run that follows its control uses the same prop
	runs.append(real)


# ------------------------------------------------------------ finding a clean strip

func _seg_dist(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(pt.x, pt.z)
	var pa := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - pa
	var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(pa + ab * t)


# The way the car drives at this prop. {} if the strip is not clean.
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
	if c.has("graze"):
		heading = along
		start = pos - perp * float(c["graze"]) - along * run_up
		end = pos + along * 14.0
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
	return {"heading": heading, "start": start, "off": off}


func _pick(c: Dictionary) -> Array:
	for key in props.block_props:
		for d: Dictionary in props.block_props[key]:
			if d["t"] != c["type"] or not d["alive"] or d.get("used", false):
				continue
			var g := _geo(key, d, c)
			if g.is_empty():
				continue
			d["used"] = true
			return [d, g]
	return []


func _radius(d: Dictionary) -> float:
	return 0.24 * float(d["s"]) if d["t"] == "tree" else 0.12


# ------------------------------------------------------------ running a case

func _place(h: Vector3, at: Vector3, v: Vector3) -> void:
	player.global_transform = Transform3D(Basis(Vector3.UP, atan2(-h.x, -h.z)), at)
	player.linear_velocity = v
	player.angular_velocity = Vector3.ZERO
	player.steering = 0.0
	player.steer_smooth = 0.0


func _setup(run: Dictionary) -> bool:
	cur = run
	if not run["reuse"]:
		var r := _pick(run)
		if r.is_empty():
			_fail(run["name"], "no clean strip of pavement found to test on")
			return false
		prop = r[0]
		geo = r[1]
	for o: Dictionary in geo["off"]:
		o["alive"] = false
	prop["alive"] = not run["control"]
	for c in main.civs.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	main.civs.clear()
	for c in main.police.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	main.police.clear()
	main.heat = 0.0
	main.level = 0
	player.dead = false
	main.game_over = false
	player.hp = 100.0
	player.last_hurt = main.clock
	main.hud.in_gas = 0.0
	main.hud.in_steer = 0.0
	debris_known.clear()
	for n in world.debris_root.get_children():
		debris_known[n.get_instance_id()] = true
	_place(geo["heading"], geo["start"], Vector3.ZERO)
	world.load_around(geo["start"], true)
	cur["t"] = 0.0
	cur["rec"] = []
	cur["t_ev"] = -1.0
	settle = SETTLE
	return true


func _process(_delta: float) -> bool:
	frames += 1
	if phase == "boot":
		if frames < 25 or main.world == null:
			return false
		world = main.world
		props = world.props
		player = main.player
		main.traffic_cap = 0
		phase = "next"
	if phase == "next":
		ri += 1
		if ri >= runs.size():
			var never := expected - passed - failed
			if never > 0:
				print("FAIL  %d case(s) never ran to the end (see the script errors)" % never)
				failed += never
			print("RESULT: %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
			return true
		if not _setup(runs[ri]):
			phase = "next"      # (the case is already marked failed; its real run would fail the same way)
			return false
		phase = "settle"
		return false
	if phase == "settle":
		settle -= 1
		_place(geo["heading"], geo["start"], Vector3.ZERO)
		if settle <= 0:
			var h: Vector3 = geo["heading"]
			_place(h, geo["start"], h * float(cur["v0"]))
			cur["t"] = 0.0
			phase = "run"
	return false


func _physics_process(delta: float) -> bool:
	if phase != "run":
		return false
	cur["t"] = float(cur["t"]) + delta
	var t: float = cur["t"]
	var pp: Vector3 = prop["p"]
	var inv := player.global_transform.affine_inverse()
	var lp: Vector3 = inv * pp
	var r := _radius(prop)
	var s := (player.global_position - (geo["start"] as Vector3)).dot(geo["heading"] as Vector3)
	var up := player.global_transform.basis.y
	(cur["rec"] as Array).append({"t": t, "v": player.linear_velocity.length(),
		"tilt": rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))})
	if float(cur["t_ev"]) < 0.0:
		if cur["control"]:
			if absf(lp.x) < CAR_HALF_W + r and absf(lp.z) < CAR_HALF_L + r:
				cur["t_ev"] = t           # where the car would have hit it
		elif not prop["alive"]:
			cur["t_ev"] = t               # the moment the prop was knocked down
	var done := t > 14.0 or (t > 1.0 and player.linear_velocity.length() < 0.2)
	if float(cur["t_ev"]) >= 0.0 and t > float(cur["t_ev"]) + AFTER:
		done = true
	if cur.get("slow", false) and float(cur["t_ev"]) >= 0.0 and t > float(cur["t_ev"]) + 1.0:
		done = true
	if cur.has("graze") and s > RUN_UP + 14.0:
		done = true
	if done:
		_finish()
	return false


func _v_at(rec: Array, t: float) -> float:
	var best: Dictionary = rec[0]
	for x: Dictionary in rec:
		if absf(float(x["t"]) - t) < absf(float(best["t"]) - t):
			best = x
	return float(best["v"])


func _finish() -> void:
	phase = "next"
	var rec: Array = cur["rec"]
	var te: float = cur["t_ev"]
	if cur["control"]:
		control = {"rec": rec, "te": te}
		if te < 0.0:
			_fail(cur["name"], "control run never reached the prop (test setup problem)")
		return
	var broke: bool = not prop["alive"]
	var problems: Array[String] = []
	var notes: Array[String] = []
	if broke != bool(cur["breaks"]):
		problems.append("the prop %s but should %s" % ["was knocked down" if broke else "was not hit", "have been hit" if cur["breaks"] else "not have been hit"])
	if broke:
		notes.append("knocked down")
		if cur.has("lo") and not control.is_empty() and float(control["te"]) >= 0.0:
			var v_real := _v_at(rec, te + 0.5)
			var v_ctl := _v_at(control["rec"], float(control["te"]) + 0.5)
			var ratio := v_real / maxf(v_ctl, 0.1)
			notes.append("kept %d%% of its speed 0.5 s later (%.1f of %.1f m/s)" % [int(round(ratio * 100.0)), v_real, v_ctl])
			if ratio < float(cur["lo"]) or ratio > float(cur["hi"]):
				problems.append("speed kept %d%%, wanted %d..%d%%" % [int(round(ratio * 100.0)), int(round(float(cur["lo"]) * 100.0)), int(round(float(cur["hi"]) * 100.0))])
		var tilt := 0.0
		for x: Dictionary in rec:
			if float(x["t"]) >= te - 0.05:
				tilt = maxf(tilt, float(x["tilt"]))
		if tilt > 25.0:
			problems.append("the car tilted %d degrees (flipped or launched)" % int(tilt))
		# the fallen prop must not collide with the car
		var found := 0
		var solid := 0
		for n in world.debris_root.get_children():
			var rb := n as RigidBody3D
			if rb != null and not debris_known.has(rb.get_instance_id()) and absf(rb.mass - 60.0) < 0.01:
				found += 1
				if (rb.collision_layer & player.collision_mask) != 0 or (player.collision_layer & rb.collision_mask) != 0:
					solid += 1
				rb.freeze = true             # out of the way of the next case
				rb.collision_layer = 0
				rb.collision_mask = 0
				rb.visible = false
		if found == 0:
			problems.append("no fallen prop found to check")
		elif solid > 0:
			problems.append("the fallen prop collides with the car (it stops the car dead)")
	if problems.is_empty():
		_pass(cur["name"], ", ".join(notes) if not notes.is_empty() else "no hit")
	else:
		_fail(cur["name"], "; ".join(problems))


func _pass(name: String, detail: String) -> void:
	passed += 1
	print("PASS  ", name, ": ", detail)


func _fail(name: String, why: String) -> void:
	failed += 1
	print("FAIL  ", name, ": ", why)
