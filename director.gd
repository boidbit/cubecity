class_name Director
extends Node
# Stages a bot run for a recorded video, like a film director: picks the start,
# schedules the beats (ramp jumps, a roadblock, a smash, the finale), raises the
# wanted level on cue, cuts between cameras and ends the clip on time. The bot
# really drives with the normal controls and physics; the director only decides
# where things happen. Until the finale the run cannot end (no wreck, no bust),
# so a clip never stops early.
#
# Modes:
#   chase    1 car vs a growing pack of police; finale is a barrel trap for them
#   destroy  smash as much of the city as possible; finale is a tall tower
#   survive  5 stars from the first second; just stay alive

const TITLES := {"chase": "1 CAR vs 10 COPS", "destroy": "BOT vs THE CITY", "survive": "SURVIVE 5 STARS"}
const FINALE := 12.0      # seconds before the end when the protection lifts and the finale starts

var main
var bot: Bot
var mode := "chase"
var duration := 55.0
var title := ""
var summary_path := ""
var heat_floor := 0.0
var auto_roadblocks := false
var start_heat := 14.0
var climax_t := 43.0
var done := {}
var traps: Array = []
var trap_t := 0.0
var next_try := 0.0
var shot_end := 3.0
var next_shot := 9.0
var break_t := 0.0
var jump_slowmo := false
var end_card := false
var finished := false
var trace := false        # --trace: print what the bot is doing once a second (CI logs)
var next_trace := 0.0


func setup(main_node, cfg: Dictionary) -> void:
	main = main_node
	bot = main.bot
	mode = cfg.get("bot", "chase")
	if not TITLES.has(mode):
		mode = "chase"
	duration = maxf(12.0, float(cfg.get("duration", "55")))
	title = str(cfg.get("title", "")).strip_edges()
	if title == "":
		title = TITLES[mode]
	summary_path = cfg.get("summary", "")
	trace = cfg.has("trace")
	bot.trace = trace
	climax_t = duration - FINALE
	main.tod_rate = 0.0
	match mode:
		"destroy":
			bot.cruise = 27.0
			start_heat = 2.0
		"survive":
			bot.cruise = 33.0
			start_heat = 90.0
		_:
			bot.cruise = 31.0
			start_heat = 14.0
	_place_start()


# Mid-block on a road near the edge of the city, heading in, with a long straight ahead.
func _place_start() -> void:
	var n := World.N
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var h := Vector2i.ZERO
	var node := Vector2i.ZERO
	for attempt in 40:
		h = dirs[randi() % 4]
		var k := randi_range(4, n - 4)
		var edge := 5 if mode == "destroy" else 3
		var j0 := n - edge if (h.x < 0 or h.y < 0) else edge
		node = Vector2i(k, j0) if h.x == 0 else Vector2i(j0, k)
		# keep clear of the flyovers for the first stretch
		var clear := true
		for i in 7:
			if bot._blocked(node + h * i):
				clear = false
		if clear:
			break
	var f := Vector3(h.x, 0, h.y)
	var p: Vector3 = main.world.node_pos(node) + f * 36.0
	var pl: Car = main.player
	pl.global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), p)
	pl.linear_velocity = f * (12.0 if mode == "destroy" else 20.0)
	main.cam_dir = f


func start() -> void:
	main.heat = start_heat
	main.level = main.level_for(start_heat)
	heat_floor = start_heat
	main.protect = true
	main.player.dmg_scale = 0.35
	main.block_t = 1e9   # roadblocks come from the director
	main.spawn_t = 4.0
	match mode:
		"chase":
			main.cap_bonus = 2
			main.spawn_gap = Vector2(1.4, 2.4)
			_opening_police(3)
		"survive":
			main.cap_bonus = 3
			main.spawn_gap = Vector2(1.0, 2.0)
			main.swat_t = 8.0
			_opening_police(4)
		_:
			main.spawn_gap = Vector2(2.5, 4.0)
	bot.plan_flee(_away_point())
	# the hook: open on the car racing at the camera with the police behind it
	main.cam_mode = "chase" if mode == "destroy" else "front"
	main.cam_cut = true
	shot_end = 3.0
	next_shot = 9.0
	main.log_event("start")


func _opening_police(n: int) -> void:
	var pl: Car = main.player
	var f := -pl.global_transform.basis.z
	var side := f.cross(Vector3.UP)
	for i in n:
		var pos := pl.global_position - f * (20.0 + i * 11.0) + side * (2.5 if i % 2 == 0 else -2.5)
		pos.y = 0.9
		main.spawn_police_at(pos, atan2(-f.x, -f.z), 22.0)


# Called by main when a police car is due. Spawning on the road the car just drove
# down puts the pack behind it, where the camera can see the chase.
func spawn_police() -> bool:
	if mode == "destroy" or main.cam_mode == "front" or randf() < 0.35:
		return false
	return _spawn_behind(randf_range(55.0, 80.0))


func _spawn_behind(back: float) -> bool:
	var tp: Dictionary = bot.trail_point(back)
	if tp.is_empty():
		return false
	var pos: Vector3 = tp["pos"]
	if pos.distance_to(main.player.global_position) < 40.0:
		return false
	for c in main.police:
		if is_instance_valid(c) and c.global_position.distance_to(pos) < 8.0:
			return false
	var dirv: Vector3 = tp["dir"]
	main.spawn_police_at(pos, atan2(-dirv.x, -dirv.z), 24.0)
	return true


func _away_point() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for c in main.police:
		if is_instance_valid(c) and not c.dead:
			sum += c.global_position
			n += 1
	if n > 0:
		return sum / n
	return main.player.global_position + main.player.global_transform.basis.z * 60.0


# ------------------------------------------------------------ per frame

func tick(dt: float) -> void:
	var t: float = main.clock
	if t >= duration:
		_finish()
		return
	if t >= duration - 2.5 and not end_card and not main.game_over:
		end_card = true
		main.hud.show_over(end_text("SURVIVED"))
		main.log_event("survived")
	if main.game_over:
		return
	var pl: Car = main.player
	# a clip must not end early: no wreck, no bust
	main.protect = true
	pl.dmg_scale = 0.35 if t < climax_t else 0.6
	if main.protect and pl.hp < 15.0:
		pl.hp = 15.0
	if trace and t >= next_trace:
		next_trace = t + 1.0
		print(bot.debug_line(t), " cops=%d lvl=%d busted=%.2f hp=%d" % [main.alive_police(), main.level, main.busted, int(pl.hp)])
	_heat(t)
	if t >= next_try:
		next_try = t + 0.5
		_beats(t)
	_update_traps(t)
	_camera(t)
	_break_free(dt)
	_jump_moment()
	if bot.replan_needed or bot.needs_plan():
		bot.plan_flee(_away_point())


# The wanted level climbs on a schedule so every clip escalates.
func _heat(t: float) -> void:
	var f := t / duration
	match mode:
		"chase":
			heat_floor = 14.0 if f < 0.18 else (32.0 if f < 0.45 else (58.0 if f < 0.68 else 88.0))
		"destroy":
			heat_floor = 2.0 if f < 0.3 else (14.0 if f < 0.6 else 32.0)
		_:
			heat_floor = 90.0


func _beats(t: float) -> void:
	var f := t / duration
	if mode == "destroy":
		# a smash whenever the road ahead allows one; the tallest towers for the finale
		if bot.busy():
			return
		if t >= climax_t - 6.0 and not done.has("tower") and bot.plan_smash(9):
			done["tower"] = t
		elif f > 0.3 and not done.has("gas") and bot.plan_gas(240.0):
			done["gas"] = t
		else:
			bot.plan_smash(3)
		return
	if f > 0.12 and f < 0.4 and not done.has("ramp1") and not bot.busy() and bot.plan_ramp():
		done["ramp1"] = t
	if f > 0.3 and f < 0.62 and not done.has("roadblock"):
		_try_roadblock(t)
	if mode == "chase" and f > 0.35 and f < 0.75 and not done.has("smash") and not bot.busy() and bot.plan_smash(5):
		done["smash"] = t
	if f > 0.62 and t < climax_t - 1.0 and not done.has("ramp2") and not bot.busy() and bot.plan_ramp():
		done["ramp2"] = t
	if t >= climax_t - 3.0 and not done.has("backup"):
		done["backup"] = t
		for i in 3:
			_spawn_behind(50.0 + i * 12.0)
	if t >= climax_t and not done.has("trap"):
		_try_trap(t)


func _try_roadblock(t: float) -> void:
	if bot.busy() or bot.straight_ahead() < 140.0:
		return
	var pa: Dictionary = bot.point_ahead(110.0)
	var dirv: Vector3 = pa["dir"]
	var c: Vector3 = pa["pos"]
	c.y = 0.9
	main.spawn_roadblock_at(c, atan2(-dirv.x, -dirv.z))
	main.hud.banner("ROADBLOCK AHEAD!")
	main.log_event("roadblock")
	done["roadblock"] = t


# Finale: barrels on the road ahead. The bot swerves past them; when the police
# behind reach them, they go up.
func _try_trap(t: float) -> void:
	var late := t > climax_t + 4.0
	var dist := bot.straight_ahead()
	if not late and (bot.busy() or dist < 80.0):
		return
	var at := clampf(dist - 25.0, 30.0, 50.0)
	var pa: Dictionary = bot.point_ahead(at)
	var dirv: Vector3 = pa["dir"]
	var c: Vector3 = pa["pos"]
	var right := dirv.cross(Vector3.UP)
	for i in 3:
		var p := c + dirv * (i * 7.0) + right * (1.5 if i % 2 == 0 else 0.5)
		var d: Dictionary = main.world.props.spawn_barrels(p)
		d["trap"] = true
		traps.append(d)
	bot.dodge(c + dirv * 14.0, dirv, 3.6)   # pass on the left of them
	trap_t = t
	done["trap"] = t
	main.log_event("trap_set")


func _update_traps(t: float) -> void:
	if traps.is_empty():
		return
	var pl: Vector3 = main.player.global_position
	for d: Dictionary in traps.duplicate():
		if not d["alive"]:
			traps.erase(d)
			continue
		var p: Vector3 = d["p"]
		var near := false
		for c in main.police:
			if is_instance_valid(c) and not c.dead and c.global_position.distance_to(p) < 7.0:
				near = true
				break
		if (near and pl.distance_to(p) > 14.0) or t - trap_t > 10.0:
			traps.erase(d)
			main.world.props.detonate(d)
			if not done.has("trap_boom"):
				done["trap_boom"] = t
				main.hud.banner("TRAP!")
				main.log_event("trap")
				main.slowmo(1.8, 0.3)
				main.cinematic(p, 6.0)


# Cuts between the chase camera, the front camera (car racing at you, police behind)
# and the helicopter view (the whole pack).
func _camera(t: float) -> void:
	if main.cine_t > 0.0 or t < shot_end:
		return
	if main.cam_mode != "chase":
		main.cam_mode = "chase"
		main.cam_cut = true
		next_shot = t + randf_range(5.0, 8.0)
		return
	if t < next_shot or bot.busy() or main.player.airtime > 0.0:
		return
	next_shot = t + 1.0
	if _police_behind(50.0) >= 1 and bot.straight_ahead() > 80.0:
		main.cam_mode = "front"
		main.cam_cut = true
		shot_end = t + 2.4
	elif main.alive_police() >= 4:
		main.cam_mode = "heli"
		main.cam_cut = true
		shot_end = t + 2.2


func _police_behind(r: float) -> int:
	var pl: Car = main.player
	var f := -pl.global_transform.basis.z
	var n := 0
	for c in main.police:
		if is_instance_valid(c) and not c.dead:
			var d: Vector3 = c.global_position - pl.global_position
			if d.length() < r and d.dot(f) < 0.0:
				n += 1
	return n


# Slow motion as the car leaves a ramp.
func _jump_moment() -> void:
	var air: float = main.player.airtime
	if air > 0.25 and not jump_slowmo:
		jump_slowmo = true
		main.slowmo(1.1, 0.4)
	elif air == 0.0:
		jump_slowmo = false


# Before the finale the run cannot be busted: when the meter gets close, the car
# shoves the police off and gets a full nitro. Good drama, and the clip goes on.
func _break_free(dt: float) -> void:
	if not main.protect or main.busted < 0.85:
		break_t = 0.0
		return
	break_t += dt
	if break_t < 1.0:
		return
	break_t = 0.0
	var pl: Car = main.player
	for c in main.cars_near(pl.global_position, 10.0):
		if c.is_player:
			continue
		var dirv: Vector3 = c.global_position - pl.global_position
		dirv.y = 0.0
		c.apply_central_impulse((dirv.normalized() * 6.0 + Vector3(0, 2.5, 0)) * c.mass)
	pl.nitro = 100.0
	main.busted = 0.35
	main.hud.banner("BROKE FREE!")
	main.log_event("broke_free")
	main.shake_cam(0.6)


# ------------------------------------------------------------ text and results

func _destroyed_pct() -> float:
	return 100.0 * main.cells_down / maxf(main.world.total_cells, 1.0)


func overlay_line() -> String:
	var t := minf(main.clock, duration)
	var clock_s := "%d:%02d" % [floori(t / 60.0), floori(t) % 60]
	var cops: int = main.alive_police()
	match mode:
		"destroy":
			return "CITY DESTROYED %.2f%%   COPS %d" % [_destroyed_pct(), cops]
		"survive":
			return "SURVIVED %s   COPS %d" % [clock_s, cops]
	return "COPS %d   %s   %d KM/H" % [cops, clock_s, int(absf(main.player.fwd_speed) * 3.6)]


func end_text(kind: String) -> String:
	var lines := PackedStringArray([kind + ("!" if kind == "SURVIVED" else ""), ""])
	lines.append("COPS WRECKED  %d" % main.wrecked)
	if mode == "destroy":
		lines.append("CITY DESTROYED  %.2f%%" % _destroyed_pct())
	lines.append("SCORE  %d" % main.score)
	return "\n".join(lines)


func summary() -> Dictionary:
	var st: Dictionary = main.stats
	var s := {
		"mode": mode,
		"orientation": "vertical" if main.vertical else "horizontal",
		"title": title,
		"duration": duration,
		"end": main.end_title.to_lower() if main.game_over else "survived",
		"end_time": snappedf(main.over_time, 0.01),
		"score": main.score,
		"cops_wrecked": main.wrecked,
		"max_cops": st["max_cops"],
		"cops_spawned": st["cops_spawned"],
		"collapses": st["collapses"],
		"chains": st["chains"],
		"gas": st["gas"],
		"big_air": st["big_air"],
		"drifts": st["drifts"],
		"smash": st["smash"],
		"busted_peak": snappedf(main.busted_peak, 0.01),
		"stuck": bot.stuck_count,
		"avg_kmh": int(bot.dist_sum / maxf(bot.time_sum, 0.1) * 3.6),
		"destroyed_pct": snappedf(_destroyed_pct(), 0.01),
		"beats": done,
		"events": main.events,
	}
	var e: float = 4.0 * main.wrecked + 8.0 * st["collapses"] + 5.0 * st["chains"] + 6.0 * st["gas"]
	e += 4.0 * st["big_air"] + 1.5 * st["drifts"] + 1.5 * st["smash"] + 0.5 * st["max_cops"]
	if main.busted_peak > 0.6:
		e += 4.0
	if done.has("trap_boom"):
		e += 6.0
	e -= 2.0 * bot.stuck_count
	if main.game_over and main.over_time < duration - FINALE - 2.0:
		e -= 15.0
	s["excitement"] = snappedf(e, 0.1)
	return s


func _finish() -> void:
	if finished:
		return
	finished = true
	# quit first: it takes effect after this frame, so the clip ends on time even
	# if something below goes wrong
	get_tree().quit()
	var js := JSON.stringify(summary())
	print("SUMMARY ", js)
	if summary_path != "":
		var fa := FileAccess.open(summary_path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(js)
			fa.close()
