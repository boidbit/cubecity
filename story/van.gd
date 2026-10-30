extends Node3D
# Story lab: a car the story drives itself (the villains' van). Not a physics car: it follows
# a list of road points at the speed the story wants, turns smoothly, slows for corners,
# follows the ground (so it flies off a ramp like everybody else) and drops its trail of
# positions for the chasing car to follow. A box collider on the traffic layer makes the
# other cars treat it as a car.
#
# Orders: arrive_at(p, dirv) drives in from behind and stops at p, flee() drives off through
# the city (picking a new route when it runs out), stop_here() brakes to a halt.

const LANE := 2.6            # drives this far right of the road's centre line
const TOP_SPEED := 24.0
const CORNER := 11.0         # speed through a 90 degree turn
const ACCEL := 9.0
const BRAKE := 11.0

var main
var world
var body: StaticBody3D
var path: Array[Vector3] = []
var speed := 0.0
var want := 0.0
var mode := "parked"          # parked, arrive, flee, stop
var yaw := 0.0
var vy := 0.0
var airborne := false
var trail: Array[Vector3] = []
var wheels: Array[Node3D] = []
var seats := {}               # who -> true while inside
var stop_point := Vector3.INF
var spin := 0.0               # a skid when it is cornered
var top := TOP_SPEED          # the story eases it off or speeds it up during a chase
var route_end := Vector2i.ZERO
var route_dir := Vector2i.ZERO


func setup(main_node, color: Color) -> void:
	main = main_node
	world = main.world
	_build(color)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	add_child(mi)
	return mi


func _build(color: Color) -> void:
	# a boxy van, facing -z: body, dark windows, a sliding door line, lights and wheels
	var glass := Color(0.08, 0.1, 0.13)
	_box(Vector3(2.2, 1.9, 5.2), Vector3(0, 1.45, 0), color)
	_box(Vector3(2.24, 0.62, 1.2), Vector3(0, 1.85, -1.95), glass)          # windscreen and front side windows
	_box(Vector3(2.24, 0.5, 2.6), Vector3(0, 1.95, 0.6), glass)             # rear side windows
	_box(Vector3(2.0, 0.6, 0.06), Vector3(0, 1.9, -2.62), glass)
	_box(Vector3(2.26, 0.06, 1.6), Vector3(0, 1.3, 0.1), color.darkened(0.35))  # door rail
	_box(Vector3(2.3, 0.3, 5.3), Vector3(0, 0.55, 0), Color(0.1, 0.1, 0.1))     # bumpers and skirt
	for s in [-0.75, 0.75]:
		_box(Vector3(0.36, 0.2, 0.06), Vector3(s, 0.95, -2.62), Color(1.0, 0.95, 0.7))
		_box(Vector3(0.3, 0.2, 0.06), Vector3(s, 0.95, 2.62), Color(0.9, 0.1, 0.1))
	for x in [-1.05, 1.05]:
		for z in [-1.7, 1.7]:
			var w := Node3D.new()
			w.position = Vector3(x, 0.45, z)
			add_child(w)
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45
			cm.bottom_radius = 0.45
			cm.height = 0.3
			mi.mesh = cm
			mi.rotation.z = PI * 0.5
			mi.material_override = _mat(Color(0.06, 0.06, 0.06))
			w.add_child(mi)
			wheels.append(w)
	body = StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.0, 5.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)
	add_child(body)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


# Where people get in and out: beside the sliding door, on the given side (+1 right).
func door(side: float) -> Vector3:
	var right := forward().cross(Vector3.UP)
	return global_position + right * side * 1.9 + forward() * -0.2


func place(p: Vector3, dirv: Vector3) -> void:
	yaw = atan2(-dirv.x, -dirv.z)
	global_position = Vector3(p.x, 0.0, p.z)
	rotation = Vector3(0, yaw, 0)
	trail = [global_position]


# Drives in along the road from `back` metres behind and stops at p.
func arrive_at(p: Vector3, dirv: Vector3, back := 70.0) -> void:
	place(p - dirv * back, dirv)
	path = [p]
	stop_point = p
	mode = "arrive"
	speed = 16.0
	visible = true


func stop_here() -> void:
	mode = "stop"


func stopped() -> bool:
	return speed < 0.3 and mode in ["parked", "stop"]


# Off through the city: a few blocks on, turning at random, and on again when the route ends.
func flee() -> void:
	mode = "flee"
	path.clear()
	_extend()


func _extend() -> void:
	var h := _grid_dir()
	var p := global_position
	var gx := (p.x + World.HALF) / World.PITCH
	var gz := (p.z + World.HALF) / World.PITCH
	var n := Vector2i(roundi(gx), roundi(gz))
	if path.is_empty():
		# the next intersection ahead
		if h.x != 0:
			n.x = int(ceil(gx + 0.2)) if h.x > 0 else int(floor(gx - 0.2))
		else:
			n.y = int(ceil(gz + 0.2)) if h.y > 0 else int(floor(gz - 0.2))
	var dir := h
	if path.size() > 0:
		n = route_end
		dir = route_dir
	for i in 6:
		# mostly straight on, sometimes a turn; never back the way it came, never off the map
		var opts: Array[Vector2i] = [dir, dir, Vector2i(dir.y, -dir.x), Vector2i(-dir.y, dir.x)]
		opts.shuffle()
		var picked := false
		for o: Vector2i in opts:
			var m := n + o
			if m.x >= 1 and m.y >= 1 and m.x <= World.N - 1 and m.y <= World.N - 1 and not _flyover(m):
				_add_corner(n, dir, o)
				n = m
				dir = o
				picked = true
				break
		if not picked:
			break
	route_end = n
	route_dir = dir


func _flyover(n: Vector2i) -> bool:
	for f in world.flyovers:
		if n.x == f.x and absi(n.y - f.y) <= 1:
			return true
	return false


# A point in the right-hand lane at intersection n, coming in along `from_dir`, leaving along `to_dir`.
func _add_corner(n: Vector2i, from_dir: Vector2i, to_dir: Vector2i) -> void:
	var c: Vector3 = world.node_pos(n)
	c.y = 0.0
	var a := Vector3(from_dir.x, 0, from_dir.y)
	var b := Vector3(to_dir.x, 0, to_dir.y)
	var off := (a.cross(Vector3.UP) + b.cross(Vector3.UP)).normalized() * LANE if a != -b else a.cross(Vector3.UP) * LANE
	path.append(c + off)


func _grid_dir() -> Vector2i:
	var f := forward()
	if absf(f.x) > absf(f.z):
		return Vector2i(1 if f.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if f.z > 0.0 else -1)


func _process(dt: float) -> void:
	if main == null or not visible:
		return
	var p := Vector3(global_position.x, 0.0, global_position.z)
	match mode:
		"arrive":
			if path.size() > 1 and p.distance_to(path[0]) < 4.0:
				path.pop_front()
			var d := stop_point - p
			var dist := d.length()
			want = minf(16.0, sqrt(2.0 * BRAKE * 0.7 * maxf(dist - 0.3, 0.0)))
			if dist < 0.6 or (path.size() == 1 and d.dot(forward()) < 0.0):
				want = 0.0
				if speed < 0.5:
					speed = 0.0
					mode = "parked"
		"flee":
			if path.size() < 3:
				_extend()
			want = top
			# slow for the corner coming up
			if path.size() >= 2:
				var dc: float = p.distance_to(path[0])
				var turn := absf(_dir_to(path[0], p).signed_angle_to(_dir_to(path[1], path[0]), Vector3.UP))
				if turn > 0.6:
					want = minf(want, sqrt(CORNER * CORNER + 2.0 * BRAKE * 0.6 * maxf(dc - 6.0, 0.0)))
			if p.distance_to(path[0]) < 7.0:
				path.pop_front()
		"stop", "parked":
			want = 0.0
	# speed
	if airborne:
		pass
	elif speed < want:
		speed = minf(want, speed + ACCEL * dt)
	else:
		speed = maxf(want, speed - BRAKE * dt)
	# steering: aim at a point a little ahead on the path
	if not path.is_empty() and speed > 0.2 and mode in ["arrive", "flee"]:
		var tgt: Vector3 = path[0]
		var to := tgt - p
		to.y = 0.0
		if to.length() > 0.5:
			var want_yaw := atan2(-to.x, -to.z)
			var rate := 1.9 * clampf(speed / 8.0, 0.3, 1.0)
			yaw = rotate_toward(yaw, want_yaw, rate * dt)
	if spin > 0.0:
		spin -= dt
		yaw += dt * 2.2 * spin
	var np := p + forward() * speed * dt
	# the ground under the van: road, ramp or the air after a ramp
	var ground := _ground(np)
	var y := global_position.y
	if airborne:
		vy -= 22.0 * dt
		y += vy * dt
		if y <= ground:
			y = ground
			airborne = false
			vy = 0.0
			main.shake_cam(0.25)
	else:
		if ground < y - 0.35:
			airborne = true
			y += vy * dt
		else:
			vy = (ground - y) / maxf(dt, 0.001)
			y = ground
	global_position = Vector3(np.x, y, np.z)
	var pitch := clampf(atan2(vy, maxf(speed, 1.0)), -0.5, 0.5) if speed > 1.0 else 0.0
	rotation = Vector3(pitch, yaw, 0)
	for w in wheels:
		w.rotation.x -= speed * dt / 0.45
	if trail.is_empty() or (trail.back() as Vector3).distance_to(global_position) > 3.0:
		trail.append(global_position)
		if trail.size() > 400:
			trail.remove_at(0)


func _dir_to(a: Vector3, b: Vector3) -> Vector3:
	var d := a - b
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else forward()


func _ground(p: Vector3) -> float:
	var from := Vector3(p.x, global_position.y + 3.0, p.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8.0, 0), 1, [body.get_rid()])
	var r: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or (r["normal"] as Vector3).y < 0.5:
		return maxf(global_position.y - 0.5, 0.0) if airborne else 0.0
	return (r["position"] as Vector3).y
