class_name Bot
extends RefCounted
# Drives the player car for recorded videos. It presses the same controls a person
# would (gas, arrows, drift, nitro) and follows waypoints planned on the road grid.
# Each waypoint says what the stretch leading to it is:
#   road   normal driving, slows for corners, dodges cars
#   ramp   lined up on a jump ramp: full speed and nitro, no dodging
#   air    after take-off: hands off until the wheels touch down
#   smash  straight through a block, ploughing any building in the way
#   hit    straight at a target (gas pump)
# The director (director.gd) decides which kind of leg comes next.

const LOOK_MIN := 10.0          # pure-pursuit look-ahead (m)
const LOOK_MAX := 26.0
const BRAKE_DECEL := 7.0        # m/s² the planner assumes when slowing for a corner
const CORNER_SPEED := 15.0      # m/s through a 90 degree turn
const SPECIAL := ["ramp", "air", "smash", "hit"]

var main
var car: Car
var world: World
var pts: Array[Vector3] = []
var kinds: Array[String] = []
var idx := 0
var start := Vector3.ZERO
var cruise := 31.0
var drift_style := true
var lane := 0.0                 # sideways offset from the path (m, + is left)
var lane_until := Vector3.ZERO
var lane_dir := Vector3.ZERO
var reverse_t := 0.0
var rev_steer := 0.0
var stuck_t := 0.0
var drift_on := false
var drift_t := 0.0
var drift_node := -1
var replan_needed := false
var trace := false
var plan_name := ""
var last_ramp := {}      # lip (top end of the ramp) and heading of the latest ramp plan
var trail: Array[Vector3] = []
var stuck_count := 0
var stuck_times: Array[float] = []
var dist_sum := 0.0
var time_sum := 0.0


func setup(main_node) -> void:
	main = main_node
	car = main.player
	world = main.world


# ------------------------------------------------------------ driving

func drive(dt: float) -> void:
	time_sum += dt
	dist_sum += car.speed * dt
	_record_trail()
	if pts.is_empty():
		_apply(0.0, 0.0, 0.0, false)
		return
	if reverse_t > 0.0:
		reverse_t -= dt
		_apply(-1.0, rev_steer, 0.0, false)
		return
	if car.airtime > 0.05:
		# airborne: gas or steer would tip the car (air control), so let it fly
		_apply(0.0, 0.0, 0.0, false)
		return
	_advance()
	if idx >= pts.size():
		replan_needed = true
		_apply(0.4, 0.0, 0.0, false)
		return
	var kind: String = kinds[idx]
	var p := _flat(car.global_position)
	var f := -car.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	if _off_route(p) > 28.0:
		replan_needed = true

	# steering: pure pursuit on the look-ahead point, turned into an arrow press
	var look := clampf(LOOK_MIN + car.speed * 0.5, LOOK_MIN, LOOK_MAX)
	var tp := _lookahead(look)
	if lane != 0.0:
		if (p - lane_until).dot(lane_dir) > 8.0:
			lane = 0.0
		else:
			tp += Vector3.UP.cross(lane_dir) * lane
	var d := tp - p
	var alpha := wrapf(atan2(-d.x, -d.z) - atan2(-f.x, -f.z), -PI, PI)
	var v := maxf(absf(car.fwd_speed), 2.0)
	var omega := 2.0 * v * sin(alpha) / maxf(d.length(), 1.0)
	var st := clampf(omega / maxf(car.yaw_gain(v), 0.3), -1.0, 1.0)

	# speed: cruise, slower for corners ahead, flat out on ramps and smashes
	var want := cruise
	var full: bool = kind in ["ramp", "smash", "hit"]
	if full:
		want = 60.0
	else:
		want = minf(want, _corner_limit(p))
	if absf(alpha) > 0.9:
		want = minf(want, 12.0)
	if kind == "road":
		var av: Array = _avoid(f, st, want)
		st = av[0]
		want = av[1]
	var gas := clampf((want - car.fwd_speed) * 0.4, -1.0, 1.0)
	if full:
		gas = 1.0

	var hb := 0.0
	if drift_style and kind == "road":
		hb = _drift(dt, p, alpha)
		if hb > 0.0:
			gas = 0.7
	var nitro := false
	if car.nitro > 8.0:
		if kind in ["ramp", "smash", "hit"]:
			nitro = true
		elif car.nitro > 35.0 and absf(alpha) < 0.12 and want > car.fwd_speed + 3.0 and _straight(p) > 90.0:
			nitro = true

	# stuck against something: reverse with the wheel turned the other way, so the
	# nose swings toward where we want to go
	if gas > 0.3 and absf(car.fwd_speed) < 1.5:
		stuck_t += dt
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	if stuck_t > 0.8:
		stuck_t = 0.0
		stuck_count += 1
		# against a wall mid-smash: back up further for a run-up (ploughing needs 9 m/s)
		reverse_t = randf_range(1.8, 2.2) if kind in ["smash", "hit"] else randf_range(1.2, 1.6)
		rev_steer = -signf(st) if absf(st) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
		stuck_times.append(main.clock)
		while stuck_times.size() > 0 and main.clock - stuck_times[0] > 10.0:
			stuck_times.remove_at(0)
		if stuck_times.size() >= 3:
			replan_needed = true
			stuck_times.clear()
	_apply(gas, st, hb, nitro)


func _apply(gas: float, st: float, hb: float, nitro: bool) -> void:
	car.input_gas = gas
	car.input_steer = st
	car.input_hb = hb
	car.input_nitro = nitro


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _prev(i: int) -> Vector3:
	return _flat(pts[i - 1]) if i > 0 else _flat(start)


# Move past waypoints the car has reached, or driven beyond.
func _advance() -> void:
	var p := _flat(car.global_position)
	while idx < pts.size():
		var target := _flat(pts[idx])
		var seg := target - _prev(idx)
		var to := target - p
		var reach := 4.0 if kinds[idx] in ["ramp", "hit"] else 7.0
		if to.length() < reach or (seg.length() > 0.1 and to.dot(seg) < 0.0):
			idx += 1
		else:
			break


func _off_route(p: Vector3) -> float:
	if idx >= pts.size():
		return 0.0
	var a := _prev(idx)
	var b := _flat(pts[idx])
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _lookahead(dist: float) -> Vector3:
	var cur := _flat(car.global_position)
	var left := dist
	var i := idx
	var last_dir := Vector3.ZERO
	while i < pts.size():
		var nxt := _flat(pts[i])
		var seg := nxt - cur
		var l := seg.length()
		if l > 0.01:
			last_dir = seg / l
			if l >= left:
				return cur + last_dir * left
		left -= l
		cur = nxt
		i += 1
	return cur + last_dir * left


# Highest speed that still lets the car brake down for each corner ahead.
func _corner_limit(p: Vector3) -> float:
	var lim := 99.0
	var dist := p.distance_to(_flat(pts[idx]))
	for i in range(idx, mini(idx + 5, pts.size())):
		var ang := 1.57   # the end of the plan counts as a sharp corner
		if i + 1 < pts.size():
			var a := _flat(pts[i]) - _prev(i)
			var b := _flat(pts[i + 1]) - _flat(pts[i])
			if a.length() < 0.5 or b.length() < 0.5:
				ang = 0.0
			else:
				ang = a.angle_to(b)
		if ang > 0.3:
			var vc := lerpf(28.0, CORNER_SPEED, clampf((ang - 0.3) / 1.27, 0.0, 1.0))
			lim = minf(lim, sqrt(vc * vc + 2.0 * BRAKE_DECEL * dist))
		if i + 1 < pts.size():
			dist += _flat(pts[i]).distance_to(_flat(pts[i + 1]))
		if dist > 160.0:
			break
	return lim


# Distance along the plan before the next real turn.
func _straight(p: Vector3) -> float:
	if idx >= pts.size():
		return 0.0
	var dist := p.distance_to(_flat(pts[idx]))
	for i in range(idx, pts.size() - 1):
		var a := _flat(pts[i]) - _prev(i)
		var b := _flat(pts[i + 1]) - _flat(pts[i])
		if a.length() > 0.5 and b.length() > 0.5 and a.angle_to(b) > 0.3:
			return dist
		dist += b.length()
	return dist


# Rays fanned ahead: steer away from cars and walls, brake for what is dead ahead.
func _avoid(f: Vector3, st: float, want: float) -> Array:
	var space := car.get_world_3d().direct_space_state
	var o := car.global_position + Vector3(0, 0.8, 0)
	var reach := clampf(6.0 + car.speed * 0.9, 8.0, 38.0)
	var ex: Array[RID] = [car.get_rid()]
	var free_l := reach
	var free_r := reach
	var ahead := reach
	for a: float in [-0.45, -0.2, 0.0, 0.2, 0.45]:
		var dirv := f.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(o, o + dirv * reach, 1 | 2 | 4, ex)
		var r := space.intersect_ray(q)
		if r.is_empty() or (r["normal"] as Vector3).y > 0.5:
			continue
		var col: Object = r["collider"]
		# loose debris and parts are not worth swerving for
		if col is RigidBody3D and not (col is VehicleBody3D) and not (col is CivCar) and not (col as RigidBody3D).freeze:
			continue
		var hd := o.distance_to(r["position"])
		var close := 1.0 - hd / reach
		var k := 0.6 if (col is StaticBody3D and col.has_meta("bld")) else 1.2
		if a > 0.0:
			free_l = minf(free_l, hd)
			st -= close * k
		elif a < 0.0:
			free_r = minf(free_r, hd)
			st += close * k
		else:
			ahead = hd
	if ahead < reach:
		want = minf(want, sqrt(2.0 * BRAKE_DECEL * maxf(ahead - 6.0, 0.0)) + 4.0)
		st += 0.6 if free_l > free_r else -0.6
	return [clampf(st, -1.0, 1.0), want]


# Handbrake through sharp corners taken fast: smoke, skid marks and a drift bonus.
func _drift(dt: float, p: Vector3, alpha: float) -> float:
	if drift_on:
		drift_t += dt
		if absf(alpha) < 0.25 or drift_t > 1.3 or car.speed < 9.0:
			drift_on = false
			return 0.0
		return 1.0
	if idx + 1 >= pts.size() or drift_node == idx or car.speed < 14.0:
		return 0.0
	var a := _flat(pts[idx]) - _prev(idx)
	var b := _flat(pts[idx + 1]) - _flat(pts[idx])
	if a.length() < 0.5 or b.length() < 0.5 or a.angle_to(b) < 1.2 or kinds[idx + 1] != "road":
		return 0.0
	if p.distance_to(_flat(pts[idx])) < 6.0 + car.speed * 0.35:
		drift_on = true
		drift_t = 0.0
		drift_node = idx
		return 1.0
	return 0.0


func _record_trail() -> void:
	var p := car.global_position
	if trail.is_empty() or trail[trail.size() - 1].distance_to(p) > 4.0:
		trail.append(p)
		if trail.size() > 60:
			trail.remove_at(0)


# ------------------------------------------------------------ queries for the director

func debug_line(t: float) -> String:
	var p := car.global_position
	var kind := kinds[idx] if idx < kinds.size() else "-"
	return "TRACE t=%5.1f plan=%s kind=%s wp=%d/%d v=%d pos=(%d,%d) stuck=%d rev=%.1f air=%.1f" % [
		t, plan_name, kind, idx, pts.size(), int(car.speed * 3.6), int(p.x), int(p.z), stuck_count, reverse_t, car.airtime]


func needs_plan() -> bool:
	return pts.size() - idx < 2


# True while a ramp, smash or target is still ahead in the current plan.
func busy() -> bool:
	for i in range(idx, pts.size()):
		if kinds[i] in SPECIAL:
			return true
	return false


func straight_ahead() -> float:
	return _straight(_flat(car.global_position))


# Point `dist` metres ahead along the plan, and the direction there.
func point_ahead(dist: float) -> Dictionary:
	var cur := _flat(car.global_position)
	var left := dist
	var dirv := -car.global_transform.basis.z
	dirv.y = 0.0
	dirv = dirv.normalized()
	for i in range(idx, pts.size()):
		var nxt := _flat(pts[i])
		var seg := nxt - cur
		var l := seg.length()
		if l > 0.01:
			dirv = seg / l
			if l >= left:
				return {"pos": cur + dirv * left, "dir": dirv}
		left -= l
		cur = nxt
	return {"pos": cur + dirv * left, "dir": dirv}


# Where the car was `back` metres ago, facing the way it drove (for police spawns).
func trail_point(back: float) -> Dictionary:
	var acc := 0.0
	for i in range(trail.size() - 1, 0, -1):
		acc += trail[i].distance_to(trail[i - 1])
		if acc >= back:
			var dirv := _flat(trail[i] - trail[i - 1]).normalized()
			return {"pos": Vector3(trail[i - 1].x, 0.9, trail[i - 1].z), "dir": dirv}
	return {}


# Keep `side` metres left (+) or right (-) of the path until `at` is passed.
func dodge(at: Vector3, dirv: Vector3, side: float) -> void:
	lane = side
	lane_until = _flat(at)
	lane_dir = _flat(dirv).normalized()


# ------------------------------------------------------------ planning on the road grid

func _inside(n: Vector2i) -> bool:
	return n.x >= 1 and n.y >= 1 and n.x <= World.N - 1 and n.y <= World.N - 1


func _grid_dir() -> Vector2i:
	var f := -car.global_transform.basis.z
	if car.speed > 4.0:
		f = car.linear_velocity
	if absf(f.x) > absf(f.z):
		return Vector2i(1 if f.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if f.z > 0.0 else -1)


# The next intersection along the car's heading.
func node_ahead() -> Vector2i:
	var p := car.global_position
	var h := _grid_dir()
	var gx := (p.x + World.HALF) / World.PITCH
	var gz := (p.z + World.HALF) / World.PITCH
	var n := Vector2i(clampi(roundi(gx), 0, World.N), clampi(roundi(gz), 0, World.N))
	if h.x != 0:
		n.x = clampi(int(ceil(gx + 0.15)) if h.x > 0 else int(floor(gx - 0.15)), 0, World.N)
	else:
		n.y = clampi(int(ceil(gz + 0.15)) if h.y > 0 else int(floor(gz - 0.15)), 0, World.N)
	return n


# L-shaped route on the grid (at most one turn). Empty if it would start with a U-turn.
func _route(a: Vector2i, b: Vector2i, h: Vector2i, x_first: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var c := a
	for pass_i in 2:
		var on_x := x_first == (pass_i == 0)
		while (c.x != b.x) if on_x else (c.y != b.y):
			var step := Vector2i(signi(b.x - c.x), 0) if on_x else Vector2i(0, signi(b.y - c.y))
			if out.size() == 1 and step == -h:
				return []
			c += step
			if _blocked(c):
				return []
			out.append(c)
	return out


# Intersections next to a flyover: its ramps block the cross street there, and the
# road under the deck runs into the underside of the ramp.
func _blocked(n: Vector2i) -> bool:
	for f in world.flyovers:
		if n.x == f.x and absi(n.y - f.y) <= 1:
			return true
	# a stunt set piece standing on the road: keep routes off it
	var np := _flat(world.node_pos(n))
	for z in world.stunt_zones:
		var a: Vector3 = _flat(z[0])
		var ab: Vector3 = _flat(z[1]) - a
		var t := clampf((np - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if np.distance_to(a + ab * t) < 16.0:
			return true
	return false


# A free straight stretch ahead for a stunt set piece: the point where it starts (just
# past an intersection, at least `approach` m from the car), the heading, and the grid
# node it follows. Empty if the road ahead is not free for `length` m.
func stunt_axis(length: float, approach: float = 50.0) -> Dictionary:
	var h := _grid_dir()
	var dirv := Vector3(h.x, 0, h.y)
	var p := _flat(car.global_position)
	var node := node_ahead()
	for k in 3:
		var origin := _flat(world.node_pos(node)) + dirv * 18.0
		if (origin - p).dot(dirv) >= approach:
			var end := origin + dirv * length
			var ok := absf(end.x) < World.HALF - 25.0 and absf(end.z) < World.HALF - 25.0
			var cnt := int(ceil(length / World.PITCH)) + 1
			for i in range(-1, cnt + 1):
				var m := node + h * i
				if not _inside(m) or _blocked(m):
					ok = false
			if ok:
				return {"origin": origin, "dir": dirv, "node": node}
		node += h
	return {}


# Follow a ready-made list of waypoints (stunts build their own).
func set_plan(points: Array, kinds_in: Array, name: String) -> void:
	var none: Array[Vector2i] = []
	_commit(none, points, kinds_in, name)


# Prefer carrying straight on, then turning; fall back to the other order.
func _best_route(a: Vector2i, b: Vector2i, h: Vector2i) -> Array[Vector2i]:
	var straight_first := (h.x != 0 and signi(b.x - a.x) == h.x) or (h.y != 0 and signi(b.y - a.y) == h.y)
	var x_first := straight_first == (h.x != 0)
	var r := _route(a, b, h, x_first)
	if r.is_empty():
		r = _route(a, b, h, not x_first)
	return r


func _commit(nodes: Array[Vector2i], extra_p: Array = [], extra_k: Array = [], name: String = "flee") -> void:
	plan_name = name
	if trace:
		print("PLAN %s t=%.1f nodes=%s extra=%s" % [name, main.clock, str(nodes), str(extra_k)])
	start = car.global_position
	pts.clear()
	kinds.clear()
	idx = 0
	drift_node = -1
	for n in nodes:
		pts.append(world.node_pos(n))
		kinds.append("road")
	for i in extra_p.size():
		pts.append(extra_p[i])
		kinds.append(extra_k[i])
	replan_needed = false


# A few blocks on, away from `away` (usually the police), with long straights.
func plan_flee(away: Vector3) -> void:
	var a := node_ahead()
	var h := _grid_dir()
	var best: Array[Vector2i] = []
	var best_s := -1e9
	for k in 30:
		var b := Vector2i(randi_range(1, World.N - 1), randi_range(1, World.N - 1))
		var dv := b - a
		var man := absi(dv.x) + absi(dv.y)
		if man < 3 or man > 8:
			continue
		var r := _best_route(a, b, h)
		if r.is_empty():
			continue
		var s := float(dv.x * h.x + dv.y * h.y) * 0.4 + world.node_pos(b).distance_to(away) / World.PITCH + randf() * 1.5
		if dv.x == 0 or dv.y == 0:
			s += 1.0
		if s > best_s:
			best_s = s
			best = r
	if best.is_empty():
		# boxed in by the city edge: just take the next turn inward
		var b2 := Vector2i(clampi(a.x + h.y * 3, 1, World.N - 1), clampi(a.y + h.x * 3, 1, World.N - 1))
		best = _route(a, b2, h, h.x == 0)
		if best.is_empty():
			best = [a]
	_commit(best)


# Line up on a jump ramp: arrive straight along its road, shift into its lane, launch.
func plan_ramp() -> bool:
	var a := node_ahead()
	var h := _grid_dir()
	var best := {}
	var best_d := 1e9
	for r in world.ramps:
		var k: int = r["k"]
		var m: int = r["m"]
		var s: int = 1 if float(r["sgn"]) > 0.0 else -1
		var step := Vector2i(0, s) if r["along_z"] else Vector2i(s, 0)
		var before := Vector2i(k, m if s > 0 else m + 1) if r["along_z"] else Vector2i(m if s > 0 else m + 1, k)
		var pre := before - step
		var after := before + step * 2
		if not _inside(pre) or not _inside(after) or not _inside(before) or _blocked(before) or _blocked(after):
			continue
		var man := absi(pre.x - a.x) + absi(pre.y - a.y)
		if man > 6:
			continue
		var route: Array[Vector2i] = []
		for xf in [true, false]:
			var rr := _route(a, pre, h, xf)
			if rr.is_empty():
				continue
			# must not reach `pre` coming back from `before`
			if rr.size() > 1 and rr[rr.size() - 1] - rr[rr.size() - 2] == -step:
				continue
			if rr.size() == 1 and h == -step:
				continue
			route = rr
			break
		if route.is_empty():
			continue
		var dd := float(man) + randf() * 0.7
		if dd < best_d:
			best_d = dd
			route.append(before)
			best = {"route": route, "r": r, "after": after}
	if best.is_empty():
		return false
	var rr2: Dictionary = best["r"]
	var p0: Vector3 = rr2["p0"]
	var p1: Vector3 = rr2["p1"]
	var dirv := _flat(p1 - p0).normalized()
	var extra := [Vector3(p0.x, 0.9, p0.z) - dirv * 18.0, p0, p1, p1 + dirv * 40.0, world.node_pos(best["after"])]
	last_ramp = {"lip": p1, "dir": dirv}
	_commit(best["route"], extra, ["road", "ramp", "ramp", "air", "road"], "ramp")
	return true


# Swerve off the straight ahead into a building beside the road, plough through it
# at full speed and come back onto the road. Ploughing needs speed (each bite of
# building slows the car), so this beats turning into a block from a standstill.
func plan_smash(min_h: int) -> bool:
	var straight := straight_ahead()
	if straight < 150.0:
		return false
	var p := _flat(car.global_position)
	var dirv: Vector3 = point_ahead(0.0)["dir"]
	var left := Vector3.UP.cross(dirv)
	var best: Building = null
	var best_s := -1e9
	var bk: Vector2i = world.block_of(car.global_position)
	for di in range(-3, 4):
		for dj in range(-3, 4):
			var key := Vector2i(bk.x + di, bk.y + dj)
			if not world.block_buildings.has(key):
				continue
			for b: Building in world.block_buildings[key]:
				if b.ny < min_h or b.collapsing or b.total_alive() < b.nx * b.nz * b.ny * 0.4:
					continue
				var rel := _flat(b.center()) - p
				var along := rel.dot(dirv)
				var lat := absf(rel.dot(left))
				if along < 75.0 or along > straight - 50.0 or lat < 12.0 or lat > 32.0:
					continue
				var sc := float(b.ny) * 0.5 - along / 80.0 + randf()
				if sc > best_s:
					best_s = sc
					best = b
	if best == null:
		return false
	return _swipe(best.center(), "smash", "smash")


# Same swerve, aimed at a gas station's pumps beside the road: the biggest bang in the city.
func plan_gas(r: float) -> bool:
	var straight := straight_ahead()
	if straight < 150.0:
		return false
	var p := _flat(car.global_position)
	var dirv: Vector3 = point_ahead(0.0)["dir"]
	var left := Vector3.UP.cross(dirv)
	for g: Dictionary in world.props.gas_stations_near(car.global_position, r):
		var rel := _flat(g["p"]) - p
		var along := rel.dot(dirv)
		var lat := absf(rel.dot(left))
		if along >= 75.0 and along <= straight - 50.0 and lat >= 12.0 and lat <= 32.0:
			return _swipe(g["p"], "hit", "gas")
	return false


# Replace the stretch of the current straight around `target` with a detour through it.
func _swipe(target: Vector3, kind: String, name: String) -> bool:
	var p := _flat(car.global_position)
	var dirv: Vector3 = point_ahead(0.0)["dir"]
	var along := (_flat(target) - p).dot(dirv)
	var keep_p: Array = []
	var keep_k: Array = []
	var cur := p
	var acc := 0.0
	for i in range(idx, pts.size()):
		acc += cur.distance_to(_flat(pts[i]))
		cur = _flat(pts[i])
		if acc > along + 45.0:
			keep_p.append(pts[i])
			keep_k.append(kinds[i])
	if keep_p.is_empty():
		return false
	var sp: Vector3 = point_ahead(along - 40.0)["pos"]
	var rp: Vector3 = point_ahead(along + 40.0)["pos"]
	var none: Array[Vector2i] = []
	_commit(none, [sp, Vector3(target.x, 0.9, target.z), rp] + keep_p, ["smash", kind, "smash"] + keep_k, name)
	return true
