class_name Swarm
extends RefCounted
# The swarm show (director mode "swarm"): 30 to 40 police cars on one car, from behind, out of the
# side streets, head-on and across the road ahead, while the normal traffic goes about its business.
# The Oracle (oracle.gd) watches every car and steers the bot's car through; this class decides who
# turns up when, and how wild the clip is.
#
#   intensity 0 .. 1   (from the seed, or --intensity=0.7) how wild this clip is: how many head-on and
#                      crossing cars, how many police cars press the car at once, how much a small hit is
#                      minded, and how many hit windows there are. A hit window is a "hitter" (a slow police
#                      car ahead on the car's own road) and a few seconds in which the oracle lets the car
#                      run into it, for the drama. A calm clip has none, a wild one has up to three.
#   the pack           grows from 8 to `peak` (30..40) cars. They come up behind the car in blocks of up to
#                      8 and one by one (any lane, the car's speed), out of side streets behind it and out of
#                      side streets ahead, and chase. One that falls too far behind is cleared away and a new
#                      one comes up close, so the pack stays where the camera can see it. Their engines are
#                      stronger than in the other modes, or they never catch a car that keeps going.
#   jousters           police cars that come head-on down the road and drive straight on, so they can be
#                      seen coming and passed (Car.line_until); after they have passed they turn and chase.
#   crossers           the same, down a side street, timed to reach the road a little before or after the car.

const OPENING := 6
const JOUST_SPEED := 22.0
const CROSS_SPEED := 20.0
const MAX_ALIVE := 48
const WAVE_MAX := 8             # police cars that come up together, in a block, behind the car
const NEAR_R := 105.0            # the pack is the police cars within this many metres of the car ...
const LEASH := 120.0             # ... a car that has fallen farther behind than this is cleared away and a new one comes up close
const HITTER_SPEED := 9.0        # the slow car ahead that the car is meant to run into
const HIT_LEAD := 1.0            # s after the hitter turns up that the oracle starts to want the hit ...
const HIT_LEN := 6.0             # ... and for how long

var dir                          # the Director
var main
var bot: Bot
var oracle: Oracle
var intensity := 0.5
var peak := 36
var duration := 55.0
var windows: Array[Vector2] = []          # when a hitter is due (x), and when its window is open (set once it is out)
var hitter_at := -1.0
var hitters := 0
var next_pack := 1.0
var next_joust := 7.0
var next_cross := 10.0
var acc := 0.0
var jousts := 0
var crossers := 0
var rears := 0
var sides := 0
var window_hits := 0
var debug := false
var base_attackers := 2
var recycled := 0
var waves := 0
var next_wave := 4.0
var recycle_t := 0.0
var near_t := 0.0                # how close the pack is, for the summary: the police cars within 30 and 60 m, averaged
var near_n := 0
var near30 := 0.0
var near60 := 0.0
var behind60 := 0.0


func setup(d, cfg: Dictionary) -> void:
	dir = d
	main = d.main
	bot = d.bot
	duration = d.duration
	if str(cfg.get("intensity", "")) != "":
		intensity = clampf(float(cfg["intensity"]), 0.0, 1.0)
	else:
		intensity = clampf(randf(), 0.05, 0.95)
	peak = 30 + randi() % 11
	oracle = Oracle.new()
	oracle.setup(main, bot)
	oracle.risk = intensity * 0.9
	base_attackers = 1 + int(round(1.0 * intensity))           # 1 calm .. 2 wild (one more in a hit window)
	main.max_attackers = base_attackers
	debug = cfg.has("swarm_debug")                 # --swarm_debug: print what the oracle sees and does (a lot of lines)
	oracle.debug = debug
	oracle.enabled = not cfg.has("no_oracle")      # --no_oracle: the same show with the bot's own rays only (to see what the oracle is worth)
	bot.oracle = oracle
	# hit windows: a few seconds in which a small hit is wanted, spread over the middle of the clip
	var n := int(round(intensity * 3.4))
	for i in n:
		var f := lerpf(0.22, 0.8, (float(i) + randf() * 0.6) / float(maxi(n, 1)))
		var at := f * duration
		windows.append(Vector2(at, -1.0))
	print("SWARM intensity=%.2f peak=%d windows=%s" % [intensity, peak, str(windows)])


func start() -> void:
	main.cap_bonus = 45
	main.wreck_time = 10.0       # a few dozen wrecks would block every road
	main.band_gain = 0.28
	main.band_max = 16.0
	main.police_power = 1.6      # a police car's engine gives it 1.3 m/s2 at 30 m/s: it never catches a car that keeps going
	main.traffic_cap = 14
	main.spawn_gap = Vector2(1.0, 2.0)
	dir._opening_police(OPENING)


# How hard the car is hit: a calm clip barely scratches it, a wild one shows it.
func dmg_scale(_t: float) -> float:
	return lerpf(0.5, 1.4, intensity)


func _in_window(t: float) -> bool:
	return hitter_at >= 0.0 and t >= hitter_at + HIT_LEAD and t <= hitter_at + HIT_LEAD + HIT_LEN


func target(t: float) -> int:
	var f := t / maxf(duration, 1.0)
	var ramp := smoothstep(0.03, 0.55, f)
	return int(lerpf(8.0, float(peak + 4), ramp))      # (a few always die or fall behind: the count seen at the peak is `peak`)


func tick(t: float, dt: float) -> void:
	# two stars, always: no SWAT truck, no helicopter, no roadblocks; and main does not spawn, we do
	main.spawn_t = 1e9
	main.swat_t = 1e9
	main.heat_cap = 28.0
	main.heat = clampf(main.heat, 14.0, 28.0)
	for i in windows.size():
		var w := windows[i]
		if w.y < 0.0 and t >= w.x and t < duration - 10.0:
			if _hitter():
				hitter_at = t
				windows[i] = Vector2(w.x, t)
				hitters += 1
			elif t > w.x + 8.0:
				windows[i] = Vector2(w.x, -2.0)      # no straight road came: this one is dropped
	var win := _in_window(t)
	if win and not oracle.hit_window:
		window_hits += 1
	oracle.hit_window = win
	main.max_attackers = base_attackers + (1 if win else 0)
	acc += dt
	if acc >= 0.11:
		acc = 0.0
		oracle.tick()
	if t >= near_t and t > 8.0:
		near_t = t + 0.5
		_count_near()
	if t >= recycle_t:
		recycle_t = t + 1.0
		_recycle()
	if t >= next_pack:
		next_pack = t + 0.6
		_pack(t)
	if t >= next_joust and t > 5.0:
		if _joust():
			jousts += 1
			next_joust = t + lerpf(7.0, 3.0, intensity) + randf() * 2.0
		else:
			next_joust = t + 0.6
	if t >= next_cross and t > 8.0:
		if _cross():
			crossers += 1
			next_cross = t + lerpf(9.0, 4.5, intensity) + randf() * 2.0
		else:
			next_cross = t + 0.6


func _count_near() -> void:
	var pl: Car = main.player
	var f := -pl.global_transform.basis.z
	var a := 0
	var b := 0
	var back := 0
	for c in main.police:
		if is_instance_valid(c) and not c.dead:
			var d: Vector3 = c.global_position - pl.global_position
			d.y = 0.0
			var l := d.length()
			if l < 30.0:
				a += 1
			if l < 60.0:
				b += 1
				if d.dot(f) < 0.0:
					back += 1
	if debug and int(main.clock) % 5 == 0 and absf(main.clock - roundf(main.clock)) < 0.3:
		var bins := [0, 0, 0, 0, 0]
		for c in main.police:
			if is_instance_valid(c) and not c.dead:
				var l2: float = (c.global_position - pl.global_position).length()
				bins[0 if l2 < 30.0 else (1 if l2 < 60.0 else (2 if l2 < 100.0 else (3 if l2 < 200.0 else 4)))] += 1
		print("SWARMPOS t=%.0f alive=%d  <30:%d  <60:%d  <100:%d  <200:%d  >=200:%d  wrecks=%d" % [main.clock, main.alive_police(), bins[0], bins[1], bins[2], bins[3], bins[4], main.wrecks.size()])
		var rows := ""
		var k := 0
		for c in main.police:
			if is_instance_valid(c) and not c.dead and k < 6:
				var dd: Vector3 = c.global_position - pl.global_position
				dd.y = 0.0
				if dd.length() > 40.0 and dd.length() < 130.0 and dd.dot(f) < 0.0:
					k += 1
					rows += " [%.0fm: cop %.0f vs car %.0f m/s top=%.0f hold=%s st=%.2f gas=%.2f stuck=%.1f]" % [dd.length(), c.linear_velocity.length(), pl.linear_velocity.length(), c.top_speed, str(c.hold), c.input_steer, c.input_gas, c.stuck_t]
		if rows != "":
			print("   COPS", rows)
	near_n += 1
	near30 += float(a)
	near60 += float(b)
	behind60 += float(back)


# ------------------------------------------------------------ who turns up

# The number of police cars that count as the pack: close enough to be seen and to matter.
func _near_count() -> int:
	var pp: Vector3 = main.player.global_position
	var n := 0
	for c in main.police:
		if is_instance_valid(c) and not c.dead and c.global_position.distance_to(pp) < NEAR_R:
			n += 1
	return n


# A police car that has been left far behind is no use to the clip: it goes, and a new one comes up close.
func _recycle() -> void:
	var pp: Vector3 = main.player.global_position
	for c in main.police.duplicate():
		if is_instance_valid(c) and not c.dead and c.line_until <= main.clock and c.global_position.distance_to(pp) > LEASH:
			main.police.erase(c)
			c.queue_free()
			recycled += 1


func _pack(t: float) -> void:
	var alive := _near_count()
	var want := target(t)
	if alive >= want or main.alive_police() >= MAX_ALIVE:
		return
	if want - alive >= 5 and t >= next_wave:
		next_wave = t + 2.2
		var made := _wave(mini(WAVE_MAX, want - alive))
		if made > 0:
			rears += made
			waves += 1
			return
	for i in mini(3, want - alive):
		var r := randf()
		if r < 0.6:
			if _rear(randf_range(40.0, 95.0)):
				rears += 1
		elif r < 0.85:
			if _side_behind():
				sides += 1
		elif dir._spawn_side():
			sides += 1


# A block of police cars on the road behind the car, three abreast, a few metres apart, doing the car's speed
# or a little more: what the front camera sees is a pack, not a few cars.
func _wave(n: int) -> int:
	var pl: Car = main.player
	var back := randf_range(46.0, 70.0)
	var made := 0
	var lanes: Array[float] = [-4.0, 0.0, 4.0]
	for i in n:
		var row := i / 3
		var tp: Dictionary = bot.trail_point(back + float(row) * 9.5)
		if tp.is_empty():
			break
		var d: Vector3 = tp["dir"]
		var pos: Vector3 = tp["pos"] + Vector3.UP.cross(d) * (lanes[i % 3] + randf_range(-0.8, 0.8))
		pos.y = 0.9
		if pos.distance_to(pl.global_position) < 30.0:
			continue
		var clear := true
		for c in main.police:
			if is_instance_valid(c) and c.global_position.distance_to(pos) < 6.5:
				clear = false
				break
		if clear:
			main.spawn_police_at(pos, atan2(-d.x, -d.z), maxf(24.0, pl.speed) + 1.0)
			made += 1
	return made


# On the road behind the car, in any lane, already doing the car's speed (a police car that starts at 24 m/s
# never catches a car doing 30).
func _rear(back: float) -> bool:
	var tp: Dictionary = bot.trail_point(back)
	if tp.is_empty():
		return false
	var pl: Car = main.player
	var d: Vector3 = tp["dir"]
	var pos: Vector3 = tp["pos"] + Vector3.UP.cross(d) * randf_range(-4.0, 4.0)
	pos.y = 0.9
	if pos.distance_to(pl.global_position) < 28.0:
		return false
	for c in main.police:
		if is_instance_valid(c) and c.global_position.distance_to(pos) < 8.0:
			return false
	main.spawn_police_at(pos, atan2(-d.x, -d.z), maxf(24.0, pl.speed))
	return true


# Out of the side street at a crossing the car has already driven through, joining the chase.
func _side_behind() -> bool:
	var tp: Dictionary = bot.trail_point(randf_range(40.0, 110.0))
	if tp.is_empty():
		return false
	var pos: Vector3 = tp["pos"]
	var dv: Vector3 = tp["dir"]
	var h := Vector2i(roundi(dv.x), roundi(dv.z))
	if h == Vector2i.ZERO or (h.x != 0 and h.y != 0):
		return false
	# the crossing nearest to that point
	var i := clampi(roundi((pos.x + World.HALF) / World.PITCH), 0, World.N)
	var j := clampi(roundi((pos.z + World.HALF) / World.PITCH), 0, World.N)
	var node: Vector3 = main.world.node_pos(Vector2i(i, j))
	var away := Vector3(h.y, 0, h.x) * (1.0 if randf() < 0.5 else -1.0)
	var spot := node + away * randf_range(35.0, 90.0)
	var f := -away
	spot += Vector3.UP.cross(f) * 3.5
	spot.y = 0.9
	var lim: float = World.HALF - 8.0
	if absf(spot.x) > lim or absf(spot.z) > lim or spot.distance_to(main.player.global_position) < 40.0:
		return false
	for c in main.police:
		if is_instance_valid(c) and c.global_position.distance_to(spot) < 8.0:
			return false
	main.spawn_police_at(spot, atan2(-f.x, -f.z), 22.0)
	return true


# A police car that has to be driven through, not chased by: it drives straight on down its line.
func _launch(pos: Vector3, f: Vector3, speed: float, secs: float) -> Car:
	var c: Car = main.spawn_police_at(pos, atan2(-f.x, -f.z), speed)
	c.line_p = pos
	c.line_dir = f
	c.line_until = main.clock + secs
	c.joust_speed = speed
	c.banded = false
	return c


# Head-on down the road the car is driving, in the lane of its choice (or straight at the car).
func _joust() -> bool:
	var dist := bot.straight_ahead()
	if dist < 150.0 or bot.busy() or main.alive_police() >= MAX_ALIVE:
		return false
	var pa: Dictionary = bot.point_ahead(minf(dist - 25.0, 190.0))
	var dirv: Vector3 = pa["dir"]
	var f := -dirv
	var offsets: Array[float] = [-3.5, 0.0, 3.5, -2.0, 2.0, 0.0]
	var pos: Vector3 = pa["pos"] + Vector3.UP.cross(f) * offsets[randi() % offsets.size()]
	pos.y = 0.9
	var lim: float = World.HALF - 8.0
	if absf(pos.x) > lim or absf(pos.z) > lim:
		return false
	_launch(pos, f, JOUST_SPEED, 25.0)
	return true


# A slow police car ahead on the car's own road, going the same way: the car catches up with it at about
# 20 m/s. Outside a hit window the oracle goes round it; inside one it lets the car run into it.
func _hitter() -> bool:
	var dist := bot.straight_ahead()
	if dist < 150.0 or bot.busy():
		return false
	var d := minf(dist - 20.0, 125.0)
	var pa: Dictionary = bot.point_ahead(d)
	var dirv: Vector3 = pa["dir"]
	var pos: Vector3 = pa["pos"] + Vector3.UP.cross(dirv) * randf_range(-1.2, 1.2)
	pos.y = 0.9
	var c := _launch(pos, dirv, HITTER_SPEED, 30.0)
	c.line_passes = false
	return true


# Down a side street, timed to reach the road a little before or after the car.
func _cross() -> bool:
	var n := bot.node_ahead()
	if bot._blocked(n) or not bot._inside(n) or main.alive_police() >= MAX_ALIVE:
		return false
	var pl: Car = main.player
	var h: Vector2i = bot._grid_dir()
	var hv := Vector3(h.x, 0, h.y)
	var np: Vector3 = main.world.node_pos(n)
	var along := Vector3(np.x - pl.global_position.x, 0, np.z - pl.global_position.z).dot(hv)
	if along < 70.0 or along > 150.0 or pl.speed < 12.0:
		return false
	var away := Vector3(h.y, 0, h.x) * (1.0 if randf() < 0.5 else -1.0)
	var eta := along / maxf(pl.speed, 15.0)
	var off_t := randf_range(-0.9, 1.3)
	var d := clampf((eta + off_t) * CROSS_SPEED, 30.0, 140.0)
	var f := -away
	var pos := np + away * d + Vector3.UP.cross(f) * 3.5
	pos.y = 0.9
	var lim: float = World.HALF - 8.0
	if absf(pos.x) > lim or absf(pos.z) > lim:
		return false
	_launch(pos, f, CROSS_SPEED, 25.0)
	return true


func summary() -> Dictionary:
	return {
		"intensity": snappedf(intensity, 0.01),
		"peak": peak,
		"windows": windows.size(),
		"hitters": hitters,
		"jousts": jousts,
		"crossers": crossers,
		"rears": rears,
		"recycled": recycled,
		"waves": waves,
		"sides": sides,
		"saves": oracle.saves,
		"evasions": oracle.evasions,
		"near30": snappedf(near30 / maxf(near_n, 1), 0.1),
		"near60": snappedf(near60 / maxf(near_n, 1), 0.1),
		"behind60": snappedf(behind60 / maxf(near_n, 1), 0.1),
		"relevant_peak": oracle.relevant_peak,
		"seen_peak": oracle.seen_peak,
	}
