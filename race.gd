class_name Race
extends RefCounted
# Car versus train: a real race along a purpose-built strip beside the railway.
#
# The course (World._make_race_course): the buildings in the railway's block row are gone, a
# paved strip runs beside the track from one edge of the city to the other, and a start line
# and a finish line (with a gantry each) cross both. The car stands on the strip, the train
# stands on the track, nose to nose behind the start line. Lights count down 3, 2, 1 and on GO
# the car drives off the line and the train pulls away, heavy and slow at first, faster later.
#
# Nothing is scripted to decide the winner. Each seed gets its own train (top speed, how hard
# it accelerates, a surge of speed at some point), its own car set-up, its own jump ramp and
# nitro pads, and the two simply race. Whoever's nose crosses the finish line first wins; the
# times are interpolated to the millisecond, so a photo finish is a real one.
#
# The cameras (shots below) are chosen so that both racers stay in frame, and every frame is
# checked: the summary reports how much of the race had both in view.

const LANE := 16.0               # the strip's centre line, metres south of the track
const HALF_COURSE := 480.0       # start line and finish line are this far from the middle
const GRID_T := 6.0              # seconds from the first frame to GO (the title hook is gone by 3)
const NOSE := 2.1                # car centre to its front bumper

var main
var dir                          # Director
var bot: Bot
var rail: Rail
var world: World
var plan: Dictionary
var dirx := 1.0
var zt := 0.0                    # the track
var zs := 0.0                    # the strip
var zm := 0.0                    # between them
var length := 2.0 * HALF_COURSE

var phase := "grid"              # grid -> race -> result
var t0 := 0.0                    # clock at GO
var cd_said := {}
var said := {}
var lead := ""
var lead_changes := 0
var lead_t := -9.0
var car_t := -1.0                # race time at which each nose crossed the line
var train_t := -1.0
var first := ""
var winner := ""
var margin := -1.0
var result_t := -1.0
var surge_t := -1.0
var last_nitro := 40.0
var prev_t := 0.0
var prev_car := 0.0
var prev_train := 0.0
var nose_gap := 0.0
var top_car := 0.0
var air_said := false

# cameras
var cam_pos := Vector3.ZERO
var cam_focus := Vector3.ZERO
var cam_fov := 56.0
var shot := ""
var shot_until := 0.0
var shot_n := 0
var hold_shot := ""
var hold_until := 0.0
var bad_t := 0.0                 # how long the racers have both been out of frame
var vis_n := 0
var tot_n := 0
var shot_vis := {}


# What the world has to build, and what the director then races: decided by the seed only, so
# the world (made first) and the race (made after) agree.
static func plan_for(cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var s := str(cfg.get("seed", ""))
	if s == "":
		rng.randomize()
	else:
		rng.seed = s.to_int() * 7919 + 13
	var d := 1.0 if rng.randf() < 0.5 else -1.0
	var sx := -d * HALF_COURSE
	var ramp_at := rng.randf_range(250.0, 520.0)
	return {
		"dirx": d,
		"start_x": sx,
		"finish_x": d * HALF_COURSE,
		"ramp_x": sx + d * ramp_at,
		"pads_x": [sx + d * rng.randf_range(90.0, 190.0), sx + d * rng.randf_range(600.0, 780.0)],
		# the train: top speed, how hard it pulls away, and a surge of speed part-way
		"train_top": rng.randf_range(32.8, 37.8),
		"train_accel": rng.randf_range(3.8, 6.2),
		"surge_at": rng.randf_range(11.0, 24.0),
		"surge_dv": rng.randf_range(4.0, 8.0),
		# the car: how hard the bot drives
		"car_cruise": rng.randf_range(34.0, 40.0),
	}


func setup(director, main_node) -> void:
	dir = director
	main = main_node
	bot = main.bot
	rail = main.rail
	world = main.world
	plan = world.race_plan
	dirx = plan["dirx"]
	zt = world.rail_z()
	zs = zt + LANE
	zm = (zt + zs) * 0.5
	bot.cruise = plan["car_cruise"]
	var sx: float = plan["start_x"]
	var f := Vector3(dirx, 0.0, 0.0)
	main.player.global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), Vector3(sx - dirx * 5.0, 0.9, zs))
	main.player.linear_velocity = Vector3.ZERO
	main.cam_dir = f
	# the train stands on the track with its nose level with the car's
	rail.start_standing(sx - dirx * 2.9, dirx, plan["train_accel"])
	prev_car = sx - dirx * 2.9
	prev_train = sx - dirx * 2.9


# Called when the run starts: plan the car's route, hold both on the line.
func start() -> void:
	_plan_route(main.player.global_position)
	bot.halt = true
	cam_pos = Vector3(float(plan["start_x"]) + dirx * 12.0, 2.2, zs + 12.0)
	cam_focus = Vector3(float(plan["start_x"]) - dirx * 8.0, 1.6, zm)
	shot = "grid"
	main.cam_mode = "race"
	main.cam_cut = true
	main.log_event("race_camera_grid")


# Waypoints down the strip, over the ramp, and on to a stop beyond the finish line.
func _plan_route(from: Vector3) -> void:
	var points: Array = []
	var kinds: Array = []
	var sx: float = plan["start_x"]
	var fx: float = plan["finish_x"]
	var rx: float = plan["ramp_x"]
	var rl := 15.0
	var x := from.x
	var step := 50.0
	var ahead := func(px: float) -> bool: return (px - x) * dirx > 6.0
	var px := sx
	while (px - fx) * dirx < 60.0:
		var near_ramp: bool = absf(px - rx) < 70.0 or (px - rx) * dirx > 0.0 and (px - rx) * dirx < rl + 60.0
		if not near_ramp and ahead.call(px):
			points.append(Vector3(px, 0.0, zs))
			kinds.append("road")
		px += dirx * step
	# the ramp: line up well before it, then flat out over it
	var seq: Array = [[-40.0, "road"], [-12.0, "road"], [0.0, "ramp"], [rl, "ramp"], [rl + 30.0, "air"], [rl + 62.0, "road"]]
	var ramp_pts: Array = []
	for e in seq:
		ramp_pts.append([Vector3(rx + dirx * float(e[0]), 0.0, zs), e[1]])
	# merge in route order
	var all: Array = []
	for i in points.size():
		all.append([points[i], kinds[i]])
	for e in ramp_pts:
		all.append(e)
	all = all.filter(func(e): return (e[0].x - x) * dirx > 6.0)
	all.sort_custom(func(a, b): return (a[0].x - b[0].x) * dirx < 0.0)
	points.clear()
	kinds.clear()
	for e in all:
		points.append(e[0])
		kinds.append(e[1])
	points.append(Vector3(fx + dirx * 95.0, 0.0, zs))
	kinds.append("road")
	bot.set_plan(points, kinds, "race")


# A collision knocked the car off its route: plan again from where it is.
func replan() -> void:
	if car_t >= 0.0:
		bot.replan_needed = false
		return
	_plan_route(main.player.global_position)
	bot.replan_needed = false


func _say(text: String, secs: float = 1.5, col: Color = Color(1, 1, 1)) -> void:
	main.hud.race.say(text, secs, col)


func _car_front() -> float:
	return main.player.global_position.x + dirx * NOSE


func _progress(front_x: float) -> float:
	return clampf((front_x - float(plan["start_x"])) * dirx / length, 0.0, 1.0)


func tick(t: float, dt: float) -> void:
	var fx: float = plan["finish_x"]
	var car: Car = main.player
	if phase == "grid":
		_countdown(t)
		_camera(t)
		_hud_update()
		return
	var rt := t - t0
	var cf := _car_front()
	var tf := rail.front
	top_car = maxf(top_car, car.speed)
	# the train's surge: it finds a little extra
	if surge_t < 0.0 and rt >= float(plan["surge_at"]) and train_t < 0.0:
		surge_t = rt
		rail.after_speed = float(plan["train_top"]) + float(plan["surge_dv"])
		rail.horn.play()
		_say("THE TRAIN FLOORS IT!", 1.6, Color(0.5, 0.75, 1.0))
		main.log_event("race_train_surge")
	elif surge_t >= 0.0 and rt >= surge_t + 4.5 and rail.after_speed > float(plan["train_top"]):
		rail.after_speed = float(plan["train_top"])
	# nitro pads and big air
	if car.nitro - last_nitro > 30.0:
		_say("NITRO!", 1.1, Color(1.0, 0.6, 0.2))
		main.log_event("race_nitro")
	last_nitro = car.nitro
	if car.airtime > 0.35 and not air_said:
		air_said = true
		_say("BIG AIR!", 1.2, Color(1.0, 0.9, 0.3))
		main.log_event("race_jump")
	# finish line: interpolate the crossing time inside the frame
	var tt := t - dt
	if car_t < 0.0 and (cf - fx) * dirx >= 0.0:
		var span := maxf((cf - prev_car) * dirx, 0.001)
		car_t = (tt + dt * clampf((fx - prev_car) * dirx / span, 0.0, 1.0)) - t0
		bot.halt = true
		main.log_event("race_car_finish")
		_crossed("car")
	if train_t < 0.0 and rail.running and (tf - fx) * dirx >= 0.0:
		var span2 := maxf((tf - prev_train) * dirx, 0.001)
		train_t = (tt + dt * clampf((fx - prev_train) * dirx / span2, 0.0, 1.0)) - t0
		main.log_event("race_train_finish")
		_crossed("train")
	prev_car = cf
	prev_train = tf
	prev_t = t
	_commentary(rt, cf, tf)
	# both across: the result
	if phase == "race" and car_t >= 0.0 and train_t >= 0.0:
		winner = "car" if car_t <= train_t else "train"
		margin = absf(car_t - train_t)
		_result(t)
	# one has crossed and the other is far behind (or the clip is about to end): call it
	elif phase == "race" and first != "" and (t - t0 > _first_time() + 14.0 or t >= dir.duration - 3.0):
		winner = first
		margin = -1.0
		_result(t)
	elif phase == "race" and first == "" and t >= dir.duration - 3.0:
		var left_car := maxf((fx - cf) * dirx, 0.0) / maxf(car.speed, 1.0)
		var left_train := maxf((fx - tf) * dirx, 0.0) / maxf(rail.speed, 1.0)
		winner = "car" if left_car <= left_train else "train"
		margin = -1.0
		_result(t)
	_camera(t)
	_hud_update()


func _first_time() -> float:
	return car_t if first == "car" else train_t


func _countdown(t: float) -> void:
	var lights: Array = world.race_lights
	for n in [3, 2, 1]:
		var at: float = GRID_T - float(n)
		if t >= at and not cd_said.has(n):
			cd_said[n] = true
			_say(str(n), 0.9, Color(1.0, 0.35, 0.3))
			var li: int = 3 - int(n)
			if li < lights.size():
				(lights[li] as StandardMaterial3D).emission_energy_multiplier = 5.0
	if t >= GRID_T:
		phase = "race"
		t0 = t
		bot.halt = false
		rail.after_speed = plan["train_top"]
		for m: StandardMaterial3D in lights:
			m.albedo_color = Color(0.1, 1.0, 0.3)
			m.emission = Color(0.1, 1.0, 0.3)
			m.emission_energy_multiplier = 6.0
		_say("GO!", 1.1, Color(0.3, 1.0, 0.4))
		main.log_event("race_go")
		main.cam_cut = true


func _crossed(who: String) -> void:
	if first == "":
		first = who
		main.slowmo(1.7, 0.3)
		_say("%s CROSSES THE LINE!" % who.to_upper(), 1.4, Color(1, 1, 1))


func _result(t: float) -> void:
	phase = "result"
	result_t = t
	var lines: Array = []
	var title := "%s WINS!" % winner.to_upper()
	if margin >= 0.0:
		var sub := "by %.2f s" % margin
		if margin < 0.6:
			sub = "PHOTO FINISH! by %.2f s" % margin
			main.log_event("race_photo_finish")
		lines.append(sub)
	lines.append("CAR     %s" % ("%.2f s" % car_t if car_t >= 0.0 else "--"))
	lines.append("TRAIN   %s" % ("%.2f s" % train_t if train_t >= 0.0 else "--"))
	if lead_changes > 0:
		lines.append("LEAD CHANGES  %d" % lead_changes)
	main.log_event("race_winner_" + winner)
	main.hud.race.show_result(title, lines, Color(1.0, 0.85, 0.25) if winner == "car" else Color(0.5, 0.75, 1.0))
	# a few seconds of the result, then the clip ends
	dir.duration = minf(dir.duration, main.clock + 8.0)
	dir.climax_t = minf(dir.climax_t, dir.duration)


# Who leads, how far ahead, and what to say about it.
func _commentary(rt: float, cf: float, tf: float) -> void:
	var gap := (cf - tf) * dirx            # metres the car's nose is ahead of the train's
	nose_gap = gap
	if first != "":
		return          # somebody has crossed the line: the lead no longer changes
	var now := "car" if gap > 0.0 else "train"
	if lead == "":
		if rt > 1.5 and absf(gap) > 3.0:
			lead = now
			lead_t = rt
	elif now != lead and absf(gap) > 4.0 and rt - lead_t > 1.5:
		lead = now
		lead_t = rt
		lead_changes += 1
		_say("%s TAKES THE LEAD!" % lead.to_upper(), 1.5, Color(1.0, 0.85, 0.25) if lead == "car" else Color(0.5, 0.75, 1.0))
		main.log_event("race_lead_change")
		hold_shot = "front" if main.vertical else "side_s"
		hold_until = main.clock + 4.0
	var prog := maxf(_progress(cf), _progress(tf))
	if prog > 0.5 and not said.has("half"):
		said["half"] = true
		_say("HALFWAY", 1.2)
	if prog > 0.82 and not said.has("final"):
		said["final"] = true
		_say("FINAL STRETCH!", 1.3, Color(1.0, 0.5, 0.3))


func _hud_update() -> void:
	var cf := _car_front()
	var tf := rail.front
	var gap := (cf - tf) * dirx
	main.hud.race.update(_progress(cf), _progress(tf), absf(gap), "car" if gap > 0.0 else "train", phase != "grid")


# ------------------------------------------------------------ cameras

# Each shot is a position, a point to look at and a field of view. They are all placed where
# the buildings are gone (the cleared block row, the strip, the track), and the choice follows
# the race: the line-up, the ramp, a change of lead, the finish.
func _camera(t: float) -> void:
	var sx: float = plan["start_x"]
	var fx: float = plan["finish_x"]
	var rx: float = plan["ramp_x"]
	var cf := _car_front()
	var tf := rail.front - dirx * 4.0
	var lead_x := cf if (cf - tf) * dirx > 0.0 else tf
	var trail_x := tf if lead_x == cf else cf
	var mid_x := (cf + tf) * 0.5
	var gap := absf(cf - tf)
	var want := shot
	if phase == "grid":
		want = "grid"
	elif phase == "result":
		want = "finish" if t - result_t < 2.5 else "winner"
	else:
		var ramp_d := (cf - rx) * dirx
		var fin_d := (fx - lead_x) * dirx
		if first != "" or fin_d < 90.0:
			want = "finish"
		elif ramp_d > -75.0 and ramp_d < 40.0 and car_t < 0.0:
			want = "ramp"
		elif hold_shot != "" and main.clock < hold_until:
			want = hold_shot
		elif bad_t > 0.6:
			want = "top"
			hold_shot = "top"
			hold_until = main.clock + 3.0
			bad_t = 0.0
		elif t >= shot_until or shot in ["grid", "ramp", "finish"]:
			var rot: Array = ["front", "top", "rear", "high_front"] if main.vertical else ["side_s", "front", "top", "rear", "high_front"]
			want = rot[shot_n % rot.size()]
			shot_n += 1
			# a side-on shot only holds both racers when they are close together; a shot from
			# behind needs the car at the back (a train is 58 m long: the camera would be inside it)
			if want == "side_s" and gap > 30.0:
				want = "top"
			if want == "rear" and (cf - tf) * dirx > 0.0:
				want = "high_front"
	if want != shot:
		shot = want
		shot_until = t + 5.0
		main.cam_cut = true
		main.log_event("race_camera_" + shot)
	match shot:
		"grid":
			# a three-quarter view of the two noses on the line, creeping in during the countdown
			var d := 14.0 - clampf(t / GRID_T, 0.0, 1.0) * 5.0
			cam_pos = Vector3(sx + dirx * d, 2.2, zs + 12.0)
			cam_focus = Vector3(sx - dirx * 8.0, 1.6, zm)
			cam_fov = 62.0
		"front":
			# head-on: both racers come at the camera side by side, whatever the gap
			cam_pos = Vector3(lead_x + dirx * (30.0 + gap * 0.25), 2.6, zm)
			cam_focus = Vector3(mid_x, 2.0, zm)
			cam_fov = 58.0
		"rear":
			cam_pos = Vector3(cf - dirx * (22.0 + gap * 0.15), 6.0, zm)
			cam_focus = Vector3(mid_x + dirx * 12.0, 1.8, zm)
			cam_fov = 58.0
		"high_front":
			cam_pos = Vector3(lead_x + dirx * (34.0 + gap * 0.25), 9.0, zm)
			cam_focus = Vector3(mid_x, 1.5, zm)
			cam_fov = 58.0
		"side_s":
			cam_pos = Vector3(mid_x - dirx * 12.0, 6.5 + gap * 0.1, zs + 12.0 + minf(gap * 0.08, 6.0))
			cam_focus = Vector3(mid_x + dirx * 4.0, 1.8, zm)
			cam_fov = 62.0
		"top":
			var h := clampf(30.0 + gap * 0.7, 32.0, 85.0)
			if main.vertical:
				cam_pos = Vector3(mid_x - dirx * h * 0.5, h, zm)
				cam_focus = Vector3(mid_x + dirx * gap * 0.1, 0.0, zm)
			else:
				cam_pos = Vector3(mid_x, h, zm + h * 0.55)
				cam_focus = Vector3(mid_x, 0.0, zm)
			cam_fov = 58.0
		"ramp":
			# from the road beyond the strip, looking along the take-off so the car crosses the frame
			cam_pos = Vector3(rx + dirx * 8.0, 2.6, zs + 24.0)
			cam_focus = Vector3(rx + dirx * 14.0, 2.8, zs)
			cam_fov = 54.0
		"finish":
			# beyond the line, between track and strip: the racers come at the lens and whoosh past
			cam_pos = Vector3(fx + dirx * 72.0, 3.2, zm)
			cam_focus = Vector3(fx - dirx * 10.0, 2.0, zm)
			cam_fov = 56.0
		"winner":
			var ang := (t - result_t) * 0.35
			var c := Vector3(fx + dirx * 14.0, 0.0, zm)
			cam_pos = c + Vector3(cos(ang) * 44.0, 26.0, sin(ang) * 44.0)
			cam_focus = c + Vector3(0, 3.0, 0)
			cam_fov = 56.0
	# the numbers that decide whether the shot works
	if phase == "race" and not (car_t >= 0.0 and train_t >= 0.0):
		tot_n += 1
		var both := _both_visible()
		var sv: Array = shot_vis.get(shot, [0, 0])
		sv[1] += 1
		if both:
			vis_n += 1
			sv[0] += 1
			bad_t = 0.0
		elif shot not in ["ramp", "finish"]:
			bad_t += 1.0 / 60.0
		shot_vis[shot] = sv


# Both racers inside the camera's view and not hidden behind a building.
func _both_visible() -> bool:
	var c: Camera3D = main.cam
	var pts: Array = [main.player.global_position + Vector3(0, 1.0, 0)]
	if shot == "ramp":
		pass            # the jump shot is about the car alone
	elif rail.running:
		pts.append(Vector3(rail.front - dirx * 8.0, 2.2, zt))
	else:
		return false
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for pt: Vector3 in pts:
		if c.is_position_behind(pt) or not c.is_position_in_frustum(pt):
			return false
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c.global_position, pt, 1))
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(pt) > 9.0:
			return false
	return true


func visible_pct() -> float:
	return 100.0 * float(vis_n) / maxf(float(tot_n), 1.0)


func summary_into(s: Dictionary) -> void:
	s["race_winner"] = winner
	s["race_first"] = first
	s["race_car_time"] = snappedf(car_t, 0.001)
	s["race_train_time"] = snappedf(train_t, 0.001)
	s["race_margin"] = snappedf(margin, 0.001)
	s["race_lead_changes"] = lead_changes
	s["race_visible_pct"] = snappedf(visible_pct(), 0.1)
	s["race_train_top"] = snappedf(float(plan["train_top"]), 0.1)
	s["race_dir"] = dirx
	var per := {}
	for k in shot_vis:
		var v: Array = shot_vis[k]
		per[k] = snappedf(100.0 * float(v[0]) / maxf(float(v[1]), 1.0), 0.1)
	s["race_shot_visible"] = per
