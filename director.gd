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

const TITLES := {"chase": "1 CAR vs 10 COPS", "destroy": "ONE CAR vs THE CITY", "survive": "SURVIVE 5 STARS",
	"stunt": "THE STUNT SHOW", "heli": "ONE CAR vs A HELICOPTER", "rush": "RUSH HOUR vs ONE CAR"}
# The stunt show runs these in order, moving on as soon as one is done (or cannot be placed).
const STUNT_ORDER := ["corridor", "mega", "tower", "ramp", "mega", "gas", "tower", "corridor"]
# Story lines shown in the middle of the screen when these events happen (once each).
const EVENT_CAPTIONS := {
	"roadblock": "THEY BLOCKED THE ROAD", "heli": "NOW A HELICOPTER?!", "swat": "THE SWAT TRUCK ARRIVES",
	"big_air": "SEND IT!", "mega_jump": "NO WAY...", "trap_set": "ONE LAST TRICK...", "trap": "BOOM.",
	"collapse": "TIMBER!", "gas": "GAS STATION = BOMB", "chain": "CHAIN REACTION!", "near_miss": "TOO CLOSE!",
	"broke_free": "STILL ALIVE!", "heli_down": "HELICOPTER DOWN!", "swat_down": "SWAT DOWN!",
}
const START_CAPTIONS := {
	"chase": "ONE CAR. NO BRAKES.", "survive": "5 STARS. NO ESCAPE.", "destroy": "HOW MUCH CAN IT BREAK?",
	"heli": "THEY SENT A HELICOPTER.", "rush": "RUSH HOUR. NO RULES.", "stunt": "NO RAMP IS TOO BIG.",
}
const PRIORITY := ["trap", "heli_down", "mega_jump", "collapse", "gas"]
const FINALE := 12.0      # seconds before the end when the protection lifts and the finale starts
const STARS_HEAT := [1.0, 12.0, 30.0, 55.0, 85.0]   # heat for 1..5 stars (main.LEVEL_HEAT)

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
var last_free := -9.0
var jam_t := 0.0
var jump_slowmo := false
var end_card := false
var finished := false
var trace := false        # --trace: print what the bot is doing once a second (CI logs)
var next_trace := 0.0
var ev_seen := 0
var last_cap := -9.0
var cap_kinds := {}
var mega_info := {}
var cam_jump := {}        # the jump the side-on stunt camera is waiting for: lip and heading
var mega_cam_t := 0.0
var pending_tower: Building = null
var tower_t := 0.0
var stunt_i := 0
var stunt_wait := 2.0
var next_cross := 3.0
var nm_min := {}          # car id -> closest approach while passing the bot
var last_nm := -9.0
var nm_count := 0
var jump := {}            # heli mode: the mega jump the helicopter waits above
var jump_stage := 0
var jump_t := 0.0
var pass_until := 0.0
var next_pass := 6.0
# Story lab: with --story the director stages nothing by itself. The story calls cue() when
# its script needs police, a jump, the helicopter... so the action supports the story.
var scripted := false
var heat_cap := 100.0
var calm_at := -1.0
var still := false        # the story has stopped the car on purpose (an ending): no breaking free


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
	scripted = cfg.has("story")
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
		"stunt":
			bot.cruise = 30.0
			start_heat = 14.0
		"heli":
			bot.cruise = 31.0
			start_heat = 32.0
		"rush":
			bot.cruise = 30.0
			start_heat = 40.0
		_:
			bot.cruise = 31.0
			start_heat = 14.0
	if scripted:
		bot.cruise = 24.0
		start_heat = 0.0
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
	if scripted:
		_start_scripted()
		return
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
		"stunt":
			main.spawn_gap = Vector2(3.5, 5.5)
			_opening_police(2)
		"heli":
			main.cap_bonus = 1
			main.spawn_gap = Vector2(2.0, 3.5)
			main.heli_forced = true
			main.heli.low = true
			_opening_police(3)
		"rush":
			main.cap_bonus = 1
			main.spawn_gap = Vector2(2.0, 3.5)
			main.traffic_cap = 30
			main.traffic_ahead = true
			_opening_police(2)
		_:
			main.spawn_gap = Vector2(2.5, 4.0)
	bot.plan_flee(_away_point())
	# the hook: open on the car racing at the camera with the police behind it
	main.cam_mode = "chase" if mode == "destroy" else "front"
	main.cam_cut = true
	shot_end = 3.0
	next_shot = 9.0
	main.log_event("start")


# Story lab: a quiet drive, no police until the story calls for them.
func _start_scripted() -> void:
	main.heat = 0.0
	main.level = 0
	heat_floor = 0.0
	heat_cap = 0.0
	main.protect = true
	main.player.dmg_scale = 0.35
	main.block_t = 1e9
	main.spawn_t = 1e9
	main.spawn_gap = Vector2(2.0, 3.5)
	main.traffic_cap = 8
	bot.drift_style = false
	bot.plan_flee(_away_point())
	main.cam_mode = "chase"
	main.cam_cut = true
	shot_end = 3.0
	next_shot = 9.0
	main.log_event("start")


# Story lab: the story asks for a piece of action. Returns false if it cannot happen right
# now (no ramp near, no straight road ...); the story tries again a moment later.
func cue(kind: String, arg: float = 0.0) -> bool:
	var t: float = main.clock
	match kind:
		"police":
			var lv := clampi(int(arg) if arg > 0.0 else 1, 1, 5)
			heat_floor = float(STARS_HEAT[lv - 1]) + 0.5
			heat_cap = float(STARS_HEAT[lv]) - 0.5 if lv < 5 else 100.0
			main.heat = maxf(main.heat, heat_floor)
			calm_at = -1.0
			main.spawn_t = 2.0
			main.cap_bonus = 0
			if main.alive_police() == 0:
				_opening_police(mini(lv, 3))
			for c in main.police:
				if is_instance_valid(c) and not c.dead:
					c.target = main.player
			bot.drift_style = true
			bot.cruise = 30.0
		"calm":
			# the police give up: they ease off now and are gone a few seconds later
			for c in main.police:
				if is_instance_valid(c) and not c.dead:
					c.target = null
			heat_floor = 0.0
			main.spawn_t = 1e9
			main.heli_forced = false
			calm_at = t + 3.5
			bot.drift_style = false
			bot.cruise = 24.0
		"heli":
			main.heli_forced = true
			main.heli.low = true
			if heat_floor < 1.0:
				cue("police", 1.0)
		"heli_off":
			main.heli_forced = false
		"jump":
			# arg: seconds the story has been waiting. A kicker on the straight ahead first;
			# after a while any ramp in reach (which can take longer to drive to).
			if bot.busy() or main.player.airtime > 0.0:
				return false
			if _plan_kicker():
				return true
			return arg > 5.0 and (_plan_mega() or _plan_ramp())
		"roadblock":
			if heat_floor < 1.0:
				cue("police", 2.0)
			done.erase("roadblock")
			_try_roadblock(t)
			return done.has("roadblock")
		"crossers":
			return not bot.busy() and _spawn_crossers()
		"boom":
			done.erase("trap")
			_try_trap(t)
			return done.has("trap")
		"swat":
			main.spawn_swat()
	return true


func _scripted_heat(t: float) -> void:
	if calm_at > 0.0 and t >= calm_at:
		calm_at = -1.0
		heat_cap = 0.0
	main.heat = clampf(main.heat, heat_floor, maxf(heat_cap, heat_floor))
	if heat_cap <= 0.0:
		main.spawn_t = 1e9


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
	if scripted:
		# story runs: the police come from behind, where the camera sees them follow
		return _spawn_behind(randf_range(45.0, 75.0))
	if mode == "destroy" or main.cam_mode in ["front", "anchor"]:
		return false
	# a mix of directions: out of side streets, head-on from ahead, from behind.
	# Returning false lets the game pick its own spot.
	var r := randf()
	var side_p := 0.35 if mode != "rush" else 0.4
	var ahead_p := 0.5 if mode != "rush" else 0.7       # rush hour: more of them head-on
	if r < side_p:
		return _spawn_side()
	if r < ahead_p:
		return _spawn_ahead()
	if r < 0.65:
		return false
	return _spawn_behind(randf_range(55.0, 80.0))


# Out of the next side street, timed to reach the road just behind the bot.
func _spawn_side() -> bool:
	var n := bot.node_ahead()
	if bot._blocked(n):
		return false
	var pl: Car = main.player
	var np: Vector3 = main.world.node_pos(n)
	var along := Vector3(np.x - pl.global_position.x, 0, np.z - pl.global_position.z).length()
	if along < 70.0 or along > 160.0:
		return false
	var h: Vector2i = bot._grid_dir()
	var sgn := 1.0 if randf() < 0.5 else -1.0
	var away := Vector3(h.y, 0, h.x) * sgn          # along the cross street, away from the crossing
	var eta := along / maxf(pl.speed, 15.0) + 0.9
	var pos := np + away * clampf(eta * 22.0, 35.0, 130.0)
	var f := -away
	pos += Vector3.UP.cross(f) * 3.5
	pos.y = 0.9
	var lim: float = World.HALF - 8.0
	if absf(pos.x) > lim or absf(pos.z) > lim or pos.distance_to(pl.global_position) < 50.0:
		return false
	main.spawn_police_at(pos, atan2(-f.x, -f.z), 20.0)
	return true


# Head-on down the road the bot is driving: it has to thread past.
func _spawn_ahead() -> bool:
	var dist := bot.straight_ahead()
	if dist < 170.0 or bot.busy():
		return false
	var pa: Dictionary = bot.point_ahead(minf(dist - 30.0, 190.0))
	var dirv: Vector3 = pa["dir"]
	var f := -dirv
	var pos: Vector3 = pa["pos"] + Vector3.UP.cross(f) * 3.5
	pos.y = 0.9
	main.spawn_police_at(pos, atan2(-f.x, -f.z), 22.0)
	return true


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
		main.hud.show_over(end_text("HELICOPTER DOWN" if main.stats["heli_down"] > 0 else "SURVIVED"))
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
		print(bot.debug_line(t), " cops=%d lvl=%d busted=%.2f hp=%d" % [main.alive_police(), main.level, main.busted, int(pl.hp)],
			(" heli=%s d=%.0f jump_stage=%d" % [main.heli.state, main.heli.global_position.distance_to(pl.global_position), jump_stage]) if mode == "heli" else "")
	if scripted:
		_scripted_heat(t)
	else:
		_heat(t)
		if t >= next_try:
			next_try = t + 0.5
			_beats(t)
	_update_traps(t)
	_near_miss(t)
	_heli_tick(t)
	_tower_tick(t)
	if not scripted:
		_story(t)
	_camera(t)
	_break_free(dt)
	_stunt_jam(dt)
	_jump_moment()
	if bot.replan_needed or bot.needs_plan():
		bot.plan_flee(_away_point())


func _cap(text: String, force: bool = false) -> void:
	if not force and main.clock - last_cap < 1.3:
		return
	last_cap = main.clock
	main.hud.caption(text)


# Story line on screen: a start line, then one for each big thing that happens.
func _story(t: float) -> void:
	if not done.has("cap_start") and t > 0.8:
		done["cap_start"] = t
		_cap(START_CAPTIONS.get(mode, "GO!"), true)
	if not done.has("cap_pack") and mode in ["chase", "survive", "rush"] and t > duration * 0.22:
		done["cap_pack"] = t
		_cap("%d COPS. AND COUNTING." % main.alive_police())
	while ev_seen < main.events.size():
		var kind: String = main.events[ev_seen]["type"]
		ev_seen += 1
		var text: String = EVENT_CAPTIONS.get(kind, "")
		if text == "":
			continue
		var gap := 4.0 if kind in ["near_miss", "collapse"] else 1e9
		if cap_kinds.has(kind) and t - float(cap_kinds[kind]) < gap:
			continue
		cap_kinds[kind] = t
		_cap(text, kind in PRIORITY)


# The wanted level climbs on a schedule so every clip escalates.
func _heat(t: float) -> void:
	var f := t / duration
	match mode:
		"chase":
			heat_floor = 14.0 if f < 0.18 else (32.0 if f < 0.45 else (58.0 if f < 0.68 else 88.0))
		"destroy":
			heat_floor = 2.0 if f < 0.3 else (14.0 if f < 0.6 else 32.0)
		"stunt":
			heat_floor = 14.0 if f < 0.5 else 32.0
		"heli":
			heat_floor = 32.0 if f < 0.5 else 45.0
		"rush":
			heat_floor = 40.0 if f < 0.5 else 62.0
		_:
			heat_floor = 90.0


func _beats(t: float) -> void:
	var f := t / duration
	if mode == "stunt":
		_stunt_show(t)
		return
	if mode == "heli":
		_heli_show(t)
		return
	if mode == "rush" and t >= next_cross and not bot.busy():
		next_cross = t + (randf_range(3.0, 4.5) if _spawn_crossers() else 0.6)
	if mode == "destroy":
		# a smash whenever the road ahead allows one; the tallest towers for the finale
		if bot.busy() or pending_tower != null:
			return
		if f > 0.2 and not done.has("tower1") and _plan_tower(8):
			done["tower1"] = t
		elif f > 0.4 and not done.has("corridor") and _plan_corridor():
			done["corridor"] = t
		elif t >= climax_t - 8.0 and not done.has("tower2") and _plan_tower(8):
			done["tower2"] = t
		elif t >= climax_t - 6.0 and not done.has("tower") and bot.plan_smash(9):
			done["tower"] = t
		elif f > 0.3 and not done.has("gas") and bot.plan_gas(240.0):
			done["gas"] = t
		else:
			bot.plan_smash(3)
		return
	if f > 0.12 and f < 0.4 and not done.has("ramp1") and not bot.busy() and _plan_ramp():
		done["ramp1"] = t
	if f > 0.3 and f < 0.62 and not done.has("roadblock"):
		_try_roadblock(t)
	if mode == "chase" and f > 0.35 and f < 0.75 and not done.has("smash") and not bot.busy() and bot.plan_smash(5):
		done["smash"] = t
	if f > 0.2 and f < 0.5 and not done.has("corridor") and not bot.busy() and _plan_corridor():
		done["corridor"] = t
	if f > 0.28 and f < 0.8 and not done.has("tower") and pending_tower == null and not bot.busy() and _plan_tower(7):
		done["tower"] = t
	if f > 0.5 and f < 0.8 and not done.has("mega") and not bot.busy() and _plan_mega():
		done["mega"] = t
	if f > 0.62 and t < climax_t - 1.0 and not done.has("ramp2") and not done.has("mega") and not bot.busy() and _plan_ramp():
		done["ramp2"] = t
	if t >= climax_t - 3.0 and not done.has("backup"):
		done["backup"] = t
		for i in 3:
			_spawn_behind(50.0 + i * 12.0)
	if t >= climax_t and not done.has("trap"):
		_try_trap(t)


# ------------------------------------------------------------ stunt set pieces

func _plan_mega() -> bool:
	var ax: Dictionary = bot.stunt_axis(Stunts.MEGA_LEN + 50.0, 70.0 if main.player.speed < 22.0 else 50.0)
	if ax.is_empty():
		return false
	mega_info = main.stunts.build_mega(ax["origin"], ax["dir"])
	mega_cam_t = 0.0
	cam_jump = {"lip": mega_info["lip"], "dir": mega_info["dir"]}
	bot.set_plan(mega_info["pts"], mega_info["kinds"], "mega")
	return true


# Story lab: a kicker ramp built on the road just ahead.
func _plan_kicker() -> bool:
	var ahead := clampf(main.player.speed * 1.7, 38.0, 60.0)
	if bot.straight_ahead() < ahead + 75.0:
		return false
	var pa: Dictionary = bot.point_ahead(ahead)
	var origin: Vector3 = pa["pos"]
	origin.y = 0.0
	var info: Dictionary = main.stunts.build_kicker(origin, pa["dir"])
	cam_jump = {"lip": info["lip"], "dir": info["dir"]}
	mega_cam_t = 0.0
	bot.set_plan(info["pts"], info["kinds"], "kicker")
	return true


# An ordinary ramp jump; the stunt camera films it too.
func _plan_ramp() -> bool:
	if not bot.plan_ramp():
		return false
	var lip: Vector3 = bot.last_ramp["lip"]
	cam_jump = {"lip": Vector3(lip.x, 0.0, lip.z), "dir": bot.last_ramp["dir"]}
	mega_cam_t = 0.0
	return true


func _plan_corridor() -> bool:
	var ax: Dictionary = bot.stunt_axis(7 * 9.0 + 70.0, 45.0)
	if ax.is_empty():
		return false
	var info: Dictionary = main.stunts.build_corridor(ax["origin"], ax["dir"], 7)
	bot.set_plan(info["pts"], info["kinds"], "corridor")
	return true


# Picks a tall building beside the road; it is brought down as the bot passes.
func _plan_tower(min_h: int) -> bool:
	var v: Vector3 = main.player.linear_velocity
	v.y = 0.0
	if v.length() < 8.0:
		return false
	var found: Dictionary = main.stunts.pick_tower(main.player.global_position, v.normalized(), min_h)
	if found.is_empty():
		return false
	pending_tower = found["building"]
	tower_t = main.clock
	return true


func _tower_tick(t: float) -> void:
	if pending_tower == null:
		return
	var b := pending_tower
	if b.collapsing or not b.loaded or t - tower_t > 9.0:
		pending_tower = null
		return
	var pl: Vector3 = main.player.global_position
	var v: Vector3 = main.player.linear_velocity
	v.y = 0.0
	var along := (b.center() - pl).dot(v.normalized())
	if along < 40.0:
		main.stunts.demolish(b)
		pending_tower = null


# Two cars cross the road ahead, one timed to pass just in front of the bot and one just
# behind it: the bot goes through the gap between them.
func _spawn_crossers() -> bool:
	var n := bot.node_ahead()
	if bot._blocked(n) or not bot._inside(n):
		return false
	var pl: Car = main.player
	var h: Vector2i = bot._grid_dir()
	var hv := Vector3(h.x, 0, h.y)
	var np: Vector3 = main.world.node_pos(n)
	var along := Vector3(np.x - pl.global_position.x, 0, np.z - pl.global_position.z).dot(hv)
	if along < 60.0 or along > 115.0 or pl.speed < 14.0:
		return false
	var vb := maxf(pl.speed, 18.0)
	var tb := along / vb
	var perp := Vector3(-hv.z, 0, hv.x)
	for k in 2:
		var cd := perp * (1.0 if k == 0 else -1.0)
		var left := Vector3.UP.cross(cd)
		var off := left.dot(hv) * 3.5              # where this car's lane crosses the bot's path
		var delta := -0.65 if k == 0 else 0.65     # just ahead of the car / just behind it
		var cc := CivCar.new()
		main.add_child(cc)
		cc.build(main, CivCar.palette(randi()), true)
		cc.cruise = 15.0
		cc.straight_only = true
		var d0 := clampf(15.0 * (tb + off / vb + delta), 14.0, 58.0)
		cc.start_route(np - cd * d0, cd)
		main.civs.append(cc)
	return true


# A car that passes close at speed without touching is a near miss.
func _near_miss(t: float) -> void:
	var pl: Car = main.player
	var pv := Vector3(pl.linear_velocity.x, 0, pl.linear_velocity.z)
	if pv.length() < 12.0 or pl.airtime > 0.1:
		return
	var cars: Array = []
	cars.append_array(main.civs)
	cars.append_array(main.police)
	for c in cars:
		if not is_instance_valid(c) or c.dead:
			continue
		var id: int = c.get_instance_id()
		var rel: Vector3 = c.global_position - pl.global_position
		rel.y = 0.0
		var d := rel.length()
		if d < 8.0:
			nm_min[id] = minf(float(nm_min.get(id, 99.0)), d)
		elif nm_min.has(id):
			var m: float = nm_min[id]
			nm_min.erase(id)
			var cv: Vector3 = c.linear_velocity
			if c is CivCar and c.moving:
				cv = c.dir * c.cruise
			# touching cars are about 1.9 m apart centre to centre
			if m > 2.05 and m < 5.5 and (cv - pv).length() > 14.0 and t - last_nm > 0.8:
				last_nm = t
				nm_count += 1
				main.stats["near_miss"] += 1
				main.bonus += 100
				main.log_event("near_miss")
				main.hud.banner("NEAR MISS x%d" % nm_count)
				if m < 3.2:
					main.slowmo(0.8, 0.45)


# Helicopter mode: the chase, some ramps and barrels on the way, and as the finale a jump
# off the tower top into the helicopter that has been following the car at street level.
func _heli_show(t: float) -> void:
	var f := t / duration
	if bot.busy() or not jump.is_empty():
		return
	if f > 0.45 and t < duration - 9.0 and not done.has("jump") and _plan_mega():
		done["jump"] = t
		jump = {"lip": mega_info["lip"], "dir": mega_info["dir"], "lip_h": Stunts.RAMP_H + Stunts.KICK_H, "hover_d": 30.0, "hover_up": 3.0}
		jump_stage = 0
		jump_t = t
	elif f > 0.6 and t < duration - 9.0 and not done.has("jump") and _plan_ramp():
		# no long straight for the tower jump: the helicopter waits above an ordinary ramp
		done["jump"] = t
		jump = {"lip": cam_jump["lip"], "dir": cam_jump["dir"], "lip_h": 2.3, "hover_d": 22.0, "hover_up": 2.6}
		jump_stage = 0
		jump_t = t
	elif f > 0.1 and f < 0.4 and not done.has("ramp1") and _plan_ramp():
		done["ramp1"] = t
	elif f > 0.2 and f < 0.45 and not done.has("corridor") and _plan_corridor():
		done["corridor"] = t
	elif f > 0.28 and f < 0.45 and not done.has("roadblock"):
		_try_roadblock(t)


# Waits for the bot to near the ramp, parks the helicopter where the jump will pass, then
# aims it at the point the car will really reach once it has left the roof.
func _heli_tick(t: float) -> void:
	if mode != "heli" or jump.is_empty():
		return
	var heli: Heli = main.heli
	if heli.down or heli.state in ["crash", "wreck"]:
		if heli.state == "wreck" or heli.down:
			jump = {}
		return
	var pl: Car = main.player
	var lip: Vector3 = jump["lip"]
	var dirv: Vector3 = jump["dir"]
	var flat := Vector3(pl.global_position.x, 0.0, pl.global_position.z)
	var along := (flat - Vector3(lip.x, 0.0, lip.z)).dot(dirv)
	# the finale did not work out (car stuck, helicopter timed out): try another jump
	if jump_stage >= 1 and heli.state == "chase" and t - jump_t > 3.0:
		jump = {}
		jump_stage = 0
		done.erase("jump")
		return
	match jump_stage:
		0:
			if along > 25.0:
				# the car went over the ramp before the helicopter was in place: plan another
				jump = {}
				done.erase("jump")
				return
			if along < -8.0 and pl.speed > 10.0:
				var hover := Vector3(lip.x, 0.0, lip.z) + dirv * float(jump["hover_d"]) + Vector3(0, float(jump["lip_h"]) + float(jump["hover_up"]), 0)
				heli.start_intercept(hover, -dirv, 9.0)
				jump_stage = 1
				jump_t = t
		1:
			if pl.airtime > 0.15 and along > -14.0:
				var th := 0.62
				var pt := pl.global_position + pl.linear_velocity * th + Vector3(0, -0.5 * 9.8 * th * th, 0)
				heli.retune_intercept(pt + Vector3(0, 1.1, 0), th + 1.0)
				jump_stage = 2
		2:
			if heli.state == "chase" and not heli.down:
				jump = {}      # it missed: back to the chase, and try another jump
				jump_stage = 0
				done.erase("jump")


# The stunt show: one set piece after another, so every second has something in it.
func _stunt_show(t: float) -> void:
	if bot.busy() or pending_tower != null or t < stunt_wait:
		return
	var kind: String = STUNT_ORDER[stunt_i % STUNT_ORDER.size()]
	var ok := false
	match kind:
		"mega":
			ok = _plan_mega()
		"corridor":
			ok = _plan_corridor()
		"tower":
			ok = _plan_tower(7)
		"ramp":
			ok = _plan_ramp()
		"gas":
			ok = bot.plan_gas(240.0)
	if ok:
		stunt_i += 1
		stunt_wait = t + (3.0 if kind == "tower" else 0.5)
		done[kind + str(stunt_i)] = t
	elif t - stunt_wait > 7.0:
		stunt_i += 1      # could not place this one here: move on to the next
		stunt_wait = t


# A side-on camera for the mega jump: the car flies across the frame.
func _mega_camera(t: float) -> bool:
	if cam_jump.is_empty():
		return false
	var pl: Car = main.player
	var lip: Vector3 = cam_jump["lip"]
	var dirv: Vector3 = cam_jump["dir"]
	var along := (pl.global_position - lip).dot(dirv)
	if mega_cam_t == 0.0:
		if along > -70.0 and along < -15.0:
			mega_cam_t = t
			main.cam_anchor = lip + dirv * 26.0 + dirv.cross(Vector3.UP) * 26.0 + Vector3(0, 4.5, 0)
			main.cam_mode = "anchor"
			main.cam_cut = true
			return true
		return false
	if along > 78.0 or t - mega_cam_t > 8.0:
		main.cam_mode = "chase"
		main.cam_cut = true
		cam_jump = {}
		mega_cam_t = 0.0
		next_shot = t + 3.0
		return false
	return true


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
	if _mega_camera(t):
		return
	if main.cam_mode == "anchor":
		if t < pass_until:
			return
		main.cam_mode = "chase"
		main.cam_cut = true
		main.cam_focus_heli = false
		next_shot = t + 3.0
		return
	# helicopter mode: from the road ahead, looking up as the helicopter chases overhead
	if mode == "heli" and jump.is_empty() and main.heli.visible and main.heli.state == "chase" and t >= next_pass and bot.straight_ahead() > 90.0 and not bot.busy():
		next_pass = t + randf_range(7.0, 10.0)
		var v: Vector3 = main.player.linear_velocity
		v.y = 0.0
		v = v.normalized()
		var base: Vector3 = main.player.global_position + v * 50.0 + Vector3(0, 1.1, 0)
		var spot := Vector3.ZERO
		for sgn in [1.0, -1.0]:
			var cand: Vector3 = base + v.cross(Vector3.UP) * 7.0 * sgn
			var rq := PhysicsRayQueryParameters3D.create(base, cand, 1)
			if main.get_world_3d().direct_space_state.intersect_ray(rq).is_empty():
				spot = cand
				break
		if spot == Vector3.ZERO:
			return
		main.cam_anchor = spot
		main.cam_focus_heli = true
		main.cam_mode = "anchor"
		main.cam_cut = true
		pass_until = t + 2.8
		return
	if main.cam_mode != "chase":
		main.cam_mode = "chase"
		main.cam_cut = true
		next_shot = t + randf_range(3.5, 5.5)
		return
	if t < next_shot or bot.busy() or main.player.airtime > 0.0:
		return
	next_shot = t + 1.0
	if _police_behind(50.0) >= 1 and bot.straight_ahead() > 80.0:
		main.cam_mode = "front"
		main.cam_cut = true
		shot_end = t + 3.2
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
# Stuck for a few seconds next to one of our own stunt structures: take it down.
func _stunt_jam(dt: float) -> void:
	var pl: Car = main.player
	if pl.speed < 2.0 and pl.airtime == 0.0:
		jam_t += dt
	else:
		jam_t = maxf(0.0, jam_t - dt * 2.0)
	if jam_t > 3.0:
		jam_t = 0.0
		if main.stunts.dismantle_near(pl.global_position, 24.0):
			bot.replan_needed = true


# Boxed in by a pile of cars (police, roadblocks, traffic): after a moment the car shoves
# them all away and gets a full nitro, so a clip never stalls in a jam. Only video runs
# do this; in the real game, getting out of a pile-up is up to the player.
func _break_free(dt: float) -> void:
	if still:
		return
	var pl: Car = main.player
	var crowd := 0
	for c in main.cars_near(pl.global_position, 9.0):
		if not c.is_player:
			crowd += 1
	for c in main.civs:
		if is_instance_valid(c) and not c.dead and c.global_position.distance_to(pl.global_position) < 9.0:
			crowd += 1
	if pl.speed < 2.5 and crowd >= 2:
		break_t += dt
	else:
		break_t = maxf(0.0, break_t - dt * 2.0)
	if (break_t < 1.3 and main.busted < 0.85) or main.clock - last_free < 3.0:
		return
	break_t = 0.0
	last_free = main.clock
	for c in main.cars_near(pl.global_position, 12.0):
		if c.is_player:
			continue
		var dirv: Vector3 = c.global_position - pl.global_position
		dirv.y = 0.0
		c.apply_central_impulse((dirv.normalized() * 9.0 + Vector3(0, 3.0, 0)) * c.mass)
	for c in main.civs:
		if is_instance_valid(c) and not c.dead and c.global_position.distance_to(pl.global_position) < 12.0:
			var dv: Vector3 = c.global_position - pl.global_position
			dv.y = 0.0
			c.knock(Vector3.ZERO)
			c.apply_central_impulse((dv.normalized() * 8.0 + Vector3(0, 3.0, 0)) * c.mass)
	pl.nitro = 100.0
	main.busted = 0.35
	main.hud.banner("BROKE FREE!")
	main.log_event("broke_free")
	main.shake_cam(0.6)


# ------------------------------------------------------------ text and results

func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _destroyed_pct() -> float:
	return 100.0 * main.cells_down / maxf(main.world.total_cells, 1.0)


func overlay_line() -> String:
	var t := minf(main.clock, duration)
	var clock_s := "%d:%02d" % [floori(t / 60.0), floori(t) % 60]
	var cops: int = main.alive_police()
	match mode:
		"destroy":
			return "CUBES SMASHED %s   BUILDINGS DOWN %d" % [_thousands(main.cells_down), main.stats["collapses"]]
		"survive":
			return "SURVIVED %s   COPS %d" % [clock_s, cops]
		"heli":
			return "HELICOPTER CHASE %s   COPS %d" % [clock_s, cops]
		"rush":
			return "NEAR MISSES %d   COPS %d" % [nm_count, cops]
		"stunt":
			return "JUMPS %d   BOOMS %d   COPS %d" % [main.stats["big_air"], main.stats["chains"] + main.stats["gas"] + main.stats["collapses"], cops]
	return "COPS %d   %s   %d KM/H" % [cops, clock_s, int(absf(main.player.fwd_speed) * 3.6)]


func end_text(kind: String) -> String:
	var lines := PackedStringArray([kind + ("!" if kind in ["SURVIVED", "HELICOPTER DOWN"] else ""), ""])
	lines.append("COPS WRECKED  %d" % main.wrecked)
	if mode == "destroy":
		lines.append("CUBES SMASHED  %s" % _thousands(main.cells_down))
		lines.append("BUILDINGS DOWN  %d" % main.stats["collapses"])
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
		"mega_jump": st["mega_jump"],
		"near_miss": st["near_miss"],
		"heli_down": st["heli_down"],
		"busted_peak": snappedf(main.busted_peak, 0.01),
		"stuck": bot.stuck_count,
		"avg_kmh": int(bot.dist_sum / maxf(bot.time_sum, 0.1) * 3.6),
		"destroyed_pct": snappedf(_destroyed_pct(), 0.01),
		"cubes": main.cells_down,
		"beats": done,
		"events": main.events,
	}
	var e: float = 4.0 * main.wrecked + 8.0 * st["collapses"] + 5.0 * st["chains"] + 6.0 * st["gas"]
	e += 4.0 * st["big_air"] + 1.5 * st["drifts"] + 1.5 * st["smash"] + 0.5 * st["max_cops"]
	e += 7.0 * st["mega_jump"] + 2.0 * st["near_miss"] + 12.0 * st["heli_down"]
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
	if DisplayServer.get_name() == "headless":
		# test runs: stop all sound and give the audio thread a moment to let go of it,
		# or Godot reports the loaded sound files as leaked at exit
		main.process_mode = Node.PROCESS_MODE_DISABLED
		main.fx.silence()
		get_tree().create_timer(0.5, true, false, true).timeout.connect(get_tree().quit)
	else:
		get_tree().quit()
	var js := JSON.stringify(summary())
	print("SUMMARY ", js)
	if summary_path != "":
		var fa := FileAccess.open(summary_path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(js)
			fa.close()
