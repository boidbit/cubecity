class_name Rail
extends Node3D
# The railway: one track east-west through the middle of the city (World.RAIL_ROW), a level
# crossing with flashing lights and barrier arms on every road it crosses, and a train that
# comes out of a tunnel in one edge wall and goes into the other. The gates come down a few
# seconds before the train. A car on the crossing when it arrives is thrown off the track
# (police cars are wrecked); a car that goes through a lowered arm snaps it off.
# The director can time a train to reach a crossing just after the bot has gone over it,
# so the police behind meet the train.

const CRUISE := 30.0          # m/s
const CARS := 4
const CAR_LEN := 13.5
const GAP := 1.3
const WIDTH := 3.3
const HEIGHT := 4.3
const WARN := 5.5             # seconds of warning before the train reaches a crossing
const ARM_LEN := 6.6
const ARM_Z := 3.7            # the arms stand this far either side of the track
const OUT := World.HALF + 95.0   # a train this far out is fully inside the tunnel

var main
var world
var z := 0.0
var crossings: Array[Dictionary] = []
var train: AnimatableBody3D
var running := false
var front := 0.0              # x of the front of the train
var dirx := 1.0
var speed := CRUISE
var after_speed := CRUISE     # speed once a timed crossing is passed
var next_t := 22.0
var enabled := true
var auto := true              # trains on their own timetable (normal play)
var timed := {}               # director: {"x": crossing x, "t": clock time the front should get there}
var hit_ids := {}
var horn_t := -9.0
var length := 0.0
var bell: AudioStreamPlayer3D
var horn: AudioStreamPlayer3D
var rumble: AudioStreamPlayer3D
var vc_mat: StandardMaterial3D
var lamp_on: StandardMaterial3D
var lamp_off: StandardMaterial3D
var trains_run := 0


func setup(main_node) -> void:
	main = main_node
	world = main.world
	z = world.rail_z()
	vc_mat = StandardMaterial3D.new()
	vc_mat.vertex_color_use_as_albedo = true
	vc_mat.roughness = 0.8
	lamp_on = _glow(Color(1.0, 0.12, 0.08), 6.0)
	lamp_off = _glow(Color(0.25, 0.04, 0.03), 0.2)
	_build_track()
	for k in World.N + 1:
		crossings.append(_build_crossing(world.line(k)))
	_build_portals()
	_build_train()
	bell = _player("bell", 18.0, true)
	horn = _player("horn", 60.0, false)
	rumble = _player("train", 30.0, true)
	horn.max_distance = 600.0
	rumble.max_distance = 260.0
	train.add_child(rumble)
	train.add_child(horn)
	add_child(bell)


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _player(sound: String, unit: float, loop: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = main.fx.sounds.get(sound)
	p.unit_size = unit
	p.max_distance = 220.0
	p.volume_db = -2.0
	if loop and p.stream is AudioStreamWAV:
		(p.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return p


func _mesh(st: SurfaceTool, parent: Node3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat if mat != null else vc_mat
	parent.add_child(mi)
	return mi


func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# ------------------------------------------------------------ building

func _build_track() -> void:
	var st := _st()
	var gravel := Color(0.4, 0.37, 0.34)
	var wood := Color(0.3, 0.22, 0.16)
	for k in World.N:
		var a: float = world.line(k) + 7.5
		var b: float = world.line(k + 1) - 7.5
		World.add_box(st, Vector3((a + b) * 0.5, 0.05, z), Vector3(b - a, 0.1, 4.6), Vector3.ONE, gravel)
		var x := a + 0.5
		while x < b - 0.4:
			World.add_box(st, Vector3(x, 0.13, z), Vector3(0.26, 0.08, 2.7), Vector3.ONE, wood)
			x += 0.9
	_mesh(st, self)
	var rails := _st()
	var len := (World.HALF + 14.0) * 2.0
	for s in [-0.75, 0.75]:
		World.add_box(rails, Vector3(0, 0.22, z + s), Vector3(len, 0.12, 0.12), Vector3.ONE, Color(0.6, 0.6, 0.64))
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.metallic = 0.8
	rm.roughness = 0.3
	_mesh(rails, self, rm)


func _build_crossing(x: float) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(x, 0.0, z)
	add_child(root)
	var st := _st()
	var yellow := Color(0.95, 0.78, 0.1)
	var white := Color(0.92, 0.92, 0.9)
	var dark := Color(0.12, 0.12, 0.13)
	var red := Color(0.8, 0.1, 0.08)
	# yellow lines on the road either side of the track
	for s in [-1.0, 1.0]:
		World.add_box(st, Vector3(0, 0.02, s * 5.4), Vector3(13.6, 0.02, 0.35), Vector3.ONE, yellow)
	var arms: Array = []
	var lamps: Array = []
	for s in [-1.0, 1.0]:
		# a post on the sidewalk; its arm reaches over the lane that drives toward the track
		var pp := Vector3(s * 8.3, 0.0, -s * ARM_Z)
		World.add_box(st, pp + Vector3(0, 1.7, 0), Vector3(0.24, 3.4, 0.24), Vector3.ONE, white)
		World.add_box(st, pp + Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.6), Vector3.ONE, dark)
		World.add_box(st, pp + Vector3(0, 2.45, 0), Vector3(1.3, 0.42, 0.22), Vector3.ONE, dark)
		# crossbuck: the X sign on top
		var bk := Basis(Vector3(0, 0, 1), deg_to_rad(40.0))
		var bk2 := Basis(Vector3(0, 0, 1), deg_to_rad(-40.0))
		_tilted(st, pp + Vector3(0, 3.35, 0), Vector3(1.9, 0.26, 0.06), bk, white)
		_tilted(st, pp + Vector3(0, 3.35, 0), Vector3(1.9, 0.26, 0.06), bk2, white)
		for lx in [-0.36, 0.36]:
			var lm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.32, 0.32, 0.26)
			lm.mesh = bm
			lm.position = pp + Vector3(lx, 2.45, 0)
			lm.material_override = lamp_off
			root.add_child(lm)
			lamps.append(lm)
		var pivot := Node3D.new()
		pivot.position = pp + Vector3(0, 1.15, 0)
		root.add_child(pivot)
		var ast := _st()
		var n := 6
		for i in n:
			var cx: float = -s * (0.35 + (i + 0.5) * ARM_LEN / n)
			World.add_box(ast, Vector3(cx, 0, 0), Vector3(ARM_LEN / n, 0.16, 0.12), Vector3.ONE, red if i % 2 == 0 else white)
		_mesh(ast, pivot)
		pivot.rotation.z = -s * deg_to_rad(84.0)
		arms.append({"pivot": pivot, "s": s, "broken": false, "z": z - s * ARM_Z})
	_mesh(st, root)
	return {"x": x, "root": root, "arms": arms, "lamps": lamps, "down": 0.0, "want": false}


func _tilted(st: SurfaceTool, c: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var tmp := _st()
	World.add_box(tmp, Vector3.ZERO, size, Vector3.ONE, col)
	var arr := tmp.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		st.set_normal(b * norms[i])
		st.set_color(col)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(c + b * verts[i])


# Dark tunnel mouths in the east and west walls, where the train comes and goes.
func _build_portals() -> void:
	var st := _st()
	var conc := Color(0.5, 0.5, 0.52)
	for s in [-1.0, 1.0]:
		var x: float = s * (World.HALF + 10.85)
		World.add_box(st, Vector3(x, 2.7, z), Vector3(0.12, 5.4, 5.2), Vector3.ONE, Color(0.02, 0.02, 0.03))
		World.add_box(st, Vector3(x - s * 0.2, 5.75, z), Vector3(0.6, 0.9, 7.2), Vector3.ONE, conc)
		for side in [-1.0, 1.0]:
			World.add_box(st, Vector3(x - s * 0.2, 2.9, z + side * 3.2), Vector3(0.6, 5.8, 0.8), Vector3.ONE, conc)
	_mesh(st, self)


func _build_train() -> void:
	train = AnimatableBody3D.new()
	train.sync_to_physics = true
	train.collision_layer = 0
	train.collision_mask = 0
	length = CARS * CAR_LEN + (CARS - 1) * GAP
	var under := Color(0.14, 0.14, 0.15)
	var win := Color(0.1, 0.13, 0.18)
	for i in CARS:
		var cx := -(i * (CAR_LEN + GAP) + CAR_LEN * 0.5)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(CAR_LEN, HEIGHT - 0.5, WIDTH)
		cs.shape = bs
		cs.position = Vector3(cx, 0.5 + (HEIGHT - 0.5) * 0.5, 0)
		train.add_child(cs)
		var st := _st()
		var body := Color(0.86, 0.2, 0.12) if i == 0 else Color(0.32, 0.42, 0.55)
		World.add_box(st, Vector3(cx, 0.75, 0), Vector3(CAR_LEN - 0.4, 0.5, WIDTH - 0.5), Vector3.ONE, under)
		World.add_box(st, Vector3(cx, 2.55, 0), Vector3(CAR_LEN, 3.1, WIDTH), Vector3.ONE, body)
		World.add_box(st, Vector3(cx, 4.15, 0), Vector3(CAR_LEN - 0.6, 0.2, WIDTH - 0.6), Vector3.ONE, body.darkened(0.25))
		if i == 0:
			# locomotive: yellow nose, cab windows, a dark stripe
			World.add_box(st, Vector3(-0.15, 2.2, 0), Vector3(0.5, 2.4, WIDTH - 0.2), Vector3.ONE, Color(0.98, 0.78, 0.12))
			World.add_box(st, Vector3(-0.9, 3.35, 0), Vector3(1.2, 0.9, WIDTH + 0.02), Vector3.ONE, win)
			World.add_box(st, Vector3(cx, 1.6, 0), Vector3(CAR_LEN + 0.02, 0.3, WIDTH + 0.02), Vector3.ONE, Color(0.98, 0.78, 0.12))
		else:
			for wi in 6:
				var wx := cx - CAR_LEN * 0.5 + 1.3 + wi * 2.15
				World.add_box(st, Vector3(wx, 2.95, 0), Vector3(1.5, 0.9, WIDTH + 0.02), Vector3.ONE, win)
		for bx in [cx - CAR_LEN * 0.32, cx + CAR_LEN * 0.32]:
			for sz in [-1.0, 1.0]:
				World.add_box(st, Vector3(bx, 0.45, sz * (WIDTH * 0.5 - 0.15)), Vector3(2.4, 0.7, 0.2), Vector3.ONE, Color(0.08, 0.08, 0.08))
		_mesh(st, train)
	var hl := SpotLight3D.new()
	hl.position = Vector3(0.4, 2.2, 0)
	hl.rotation.y = -PI * 0.5
	hl.spot_range = 70.0
	hl.spot_angle = 24.0
	hl.light_energy = 6.0
	train.add_child(hl)
	for sz in [-0.9, 0.9]:
		var lm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.32, 0.42)
		lm.mesh = bm
		lm.position = Vector3(0.12, 1.25, sz)
		lm.material_override = _glow(Color(1.0, 0.95, 0.75), 4.0)
		train.add_child(lm)
	train.visible = false
	add_child(train)
	train.global_position = Vector3(0, -60, z)


# ------------------------------------------------------------ running

func start_train(d: float, spd: float) -> void:
	running = true
	dirx = d
	front = -d * OUT
	speed = spd
	after_speed = CRUISE
	hit_ids.clear()
	trains_run += 1
	train.visible = true
	train.collision_layer = 1
	train.global_transform = Transform3D(Basis(Vector3.UP, 0.0 if d > 0.0 else PI), Vector3(front, 0.0, z))
	rumble.play()
	main.log_event("train")


func _stop_train() -> void:
	running = false
	timed = {}
	train.visible = false
	train.collision_layer = 0
	train.global_position = Vector3(0, -60, z)
	rumble.stop()
	next_t = main.clock + randf_range(28.0, 48.0)


func tail() -> float:
	return front - dirx * length


# Seconds until the front of the train reaches x (INF if it is not heading there).
func eta(x: float) -> float:
	if not running:
		return INF
	var rem := (x - front) * dirx
	if rem < 0.0:
		return INF
	return rem / maxf(speed, 1.0)


# True while the train is on the crossing at x (or just about to be).
func occupied(x: float, margin: float = 2.0) -> bool:
	if not running:
		return false
	var a := minf(front, tail()) - margin
	var b := maxf(front, tail()) + margin
	return x > a and x < b


# Director: get a train to the crossing at x at clock time `at_t`. A train already on its
# way there is retimed; otherwise one is sent from whichever tunnel suits the timing.
func call_train(x: float, at_t: float) -> bool:
	if not enabled:
		return false
	var left: float = at_t - main.clock
	if left < 1.0:
		return false
	if running:
		if (x - front) * dirx < 60.0:
			return false
		timed = {"x": x, "t": at_t}
		return true
	var best_d := 0.0
	var best_v := 0.0
	var best_s := INF
	for d in [1.0, -1.0]:
		var need: float = (x + d * OUT) / left * d   # (x - (-d*OUT)) * d / left
		if need < 14.0 or need > 55.0:
			continue
		var sc := absf(need - CRUISE)
		if sc < best_s:
			best_s = sc
			best_d = d
			best_v = need
	if best_d == 0.0:
		return false
	start_train(best_d, best_v)
	timed = {"x": x, "t": at_t}
	return true


func retime(at_t: float) -> void:
	if not timed.is_empty():
		timed["t"] = at_t


func _physics_process(dt: float) -> void:
	if main.player == null:
		return
	var now: float = main.clock
	if not running:
		if enabled and auto and now >= next_t and not main.game_over:
			start_train(1.0 if randf() < 0.5 else -1.0, CRUISE)
		_gates(dt)
		return
	# speed: on schedule for a timed crossing, then on at cruise (or faster)
	var want := after_speed
	if not timed.is_empty():
		var rem: float = (float(timed["x"]) - front) * dirx
		var left: float = float(timed["t"]) - now
		if rem <= 0.0:
			timed = {}
		elif left > 0.2:
			want = clampf(rem / left, 8.0, 55.0)
		else:
			want = 45.0
	speed = move_toward(speed, want, (18.0 if want > speed else 14.0) * dt)
	front += dirx * speed * dt
	train.global_transform = Transform3D(Basis(Vector3.UP, 0.0 if dirx > 0.0 else PI), Vector3(front, 0.0, z))
	rumble.pitch_scale = clampf(0.6 + speed / 60.0, 0.6, 1.4)
	_hits()
	_horn(now)
	_gates(dt)
	if tail() * dirx > OUT:
		_stop_train()


# A car (or a parked or traffic car) on the track where the train is: thrown clear.
func _hits() -> void:
	var a := minf(front, tail()) - 0.8
	var b := maxf(front, tail()) + 0.8
	var cars: Array = []
	cars.append_array(main._all_cars())
	cars.append_array(main.civs)
	for c in cars:
		if not is_instance_valid(c) or c.dead:
			continue
		var p: Vector3 = c.global_position
		# on the track, or nose-first into the side of the train
		var reach := WIDTH * 0.5 + 1.4
		var vz: float = (c as RigidBody3D).linear_velocity.z
		if vz * (z - p.z) > 0.0 and absf(vz) > 4.0:
			reach = WIDTH * 0.5 + 2.6
		if p.x < a or p.x > b or absf(p.z - z) > reach or p.y > HEIGHT + 1.0:
			continue
		var id: int = c.get_instance_id()
		if hit_ids.has(id):
			continue
		hit_ids[id] = true
		var side := signf(p.z - z) if absf(p.z - z) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
		var v := Vector3(dirx * speed * 0.8, 7.0 + speed * 0.12, side * 5.0)
		(c as RigidBody3D).linear_velocity = v
		(c as RigidBody3D).angular_velocity = Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
		main.fx.crash(p, 30.0)
		main.fx.sparks(p + Vector3(0, 1, 0), 30)
		main.shake_cam(0.9)
		if c is CivCar:
			(c as CivCar).knock(v)
			if c.has_method("hurt"):
				c.hurt(200.0)
		elif c.is_player:
			c.hurt(70.0)
			main.log_event("train_hit_player")
		else:
			c.hurt(999.0)
			main.stats["train_hits"] = int(main.stats.get("train_hits", 0)) + 1
			main.log_event("train_hit")
			if main.gadgets != null:
				main.gadgets.add_combo(300, "TRAIN HIT")
			if main.director != null:
				main.slowmo(1.6, 0.3)


# The horn: once as the train nears a crossing close to the player.
func _horn(now: float) -> void:
	if now - horn_t < 5.0:
		return
	var pp: Vector3 = main.player.global_position
	if absf(pp.z - z) > 160.0:
		return
	for c in crossings:
		var t := eta(c["x"])
		if t < 4.5 and absf(float(c["x"]) - pp.x) < 140.0:
			horn_t = now
			horn.play()
			main.log_event("train_horn")
			return


func _gates(dt: float) -> void:
	var now: float = main.clock
	var pp: Vector3 = main.player.global_position
	var flash := fmod(now * 1.6, 1.0) < 0.5
	var near_active := -1
	var near_d := 1e9
	for i in crossings.size():
		var c: Dictionary = crossings[i]
		var x: float = c["x"]
		var want := false
		if running:
			var ahead := (x - front) * dirx
			var behind := (x - tail()) * dirx
			want = (ahead > 0.0 and ahead < WARN * maxf(speed, 12.0)) or (ahead <= 0.0 and behind > -speed * 1.2)
		var was: bool = c["want"]
		c["want"] = want
		if want and not was and absf(x - pp.x) < 150.0 and absf(pp.z - z) < 150.0:
			main.log_event("gates_down")
		var dn: float = c["down"]
		dn = move_toward(dn, 1.0 if want else 0.0, dt / (1.3 if want else 1.8))
		c["down"] = dn
		var lamps: Array = c["lamps"]
		for li in lamps.size():
			var lit: bool = (want or dn > 0.05) and ((li % 2 == 0) == flash)
			(lamps[li] as MeshInstance3D).material_override = lamp_on if lit else lamp_off
		var ease_dn := dn * dn * (3.0 - 2.0 * dn)
		for arm: Dictionary in c["arms"]:
			var pivot: Node3D = arm["pivot"]
			var s: float = arm["s"]
			pivot.rotation.z = -s * deg_to_rad(84.0) * (1.0 - ease_dn)
			if arm["broken"] and dn <= 0.0:
				arm["broken"] = false
				pivot.visible = true
			elif not arm["broken"] and dn > 0.55:
				_smash_check(c, arm)
		if (want or dn > 0.05):
			var d := Vector2(x - pp.x, z - pp.z).length()
			if d < near_d:
				near_d = d
				near_active = i
	if near_active >= 0 and near_d < 180.0:
		bell.global_position = Vector3(crossings[near_active]["x"], 2.5, z)
		if not bell.playing:
			bell.play()
	elif bell.playing:
		bell.stop()


# A car driving through a lowered arm snaps it off.
func _smash_check(c: Dictionary, arm: Dictionary) -> void:
	var x: float = c["x"]
	var s: float = arm["s"]
	var az: float = arm["z"]
	var x0 := x + s * 0.4
	var x1 := x + s * (0.4 + ARM_LEN)
	var lo := minf(x0, x1)
	var hi := maxf(x0, x1)
	for car in main._all_cars():
		if car.dead or car.speed < 5.0:
			continue
		var p: Vector3 = car.global_position
		if absf(p.z - az) < 1.8 and p.x > lo - 0.6 and p.x < hi + 0.6:
			arm["broken"] = true
			var pivot: Node3D = arm["pivot"]
			pivot.visible = false
			_flying_arm(pivot, s, car.linear_velocity)
			main.fx.sparks(p + Vector3(0, 1.0, 0), 16)
			main.fx.play("crash", p, -4.0)
			if car.is_player:
				main.log_event("gate_smash")
				if main.gadgets != null:
					main.gadgets.add_combo(150, "GATE SMASH")
			return


func _flying_arm(pivot: Node3D, s: float, vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 30.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(ARM_LEN, 0.16, 0.12)
	cs.shape = bs
	cs.position = Vector3(-s * (0.35 + ARM_LEN * 0.5), 0, 0)
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = (pivot.get_child(0) as MeshInstance3D).mesh
	mi.material_override = vc_mat
	rb.add_child(mi)
	world.debris_root.add_child(rb)
	rb.global_transform = pivot.global_transform
	rb.linear_velocity = vel * 0.7 + Vector3(0, 5, 0)
	rb.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-8, 8), randf_range(-5, 5))
	main.get_tree().create_timer(8.0).timeout.connect(rb.queue_free)


# ------------------------------------------------------------ queries

# The crossing on the N-S road at grid line k.
func crossing_x(k: int) -> float:
	return world.line(k)
