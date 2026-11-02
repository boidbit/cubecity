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
#   escape   the escape kit: cash, a spike strip, the train, EMP, a shield through a
#            roadblock, an oil slick, a spray shop, and a safehouse garage as the finale

const TITLES := {"chase": "1 CAR vs 10 COPS", "destroy": "ONE CAR vs THE CITY", "survive": "SURVIVE 5 STARS",
	"stunt": "THE STUNT SHOW", "heli": "ONE CAR vs A HELICOPTER", "rush": "RUSH HOUR vs ONE CAR",
	"escape": "CAN HE ESCAPE?"}
# The escape show tries these in order, moving on when one cannot be placed from here.
const ESCAPE_ORDER := ["spikes", "cash", "train", "emp", "spray", "oil", "shield", "cash", "train", "emp", "oil"]
# The stunt show runs these in order, moving on as soon as one is done (or cannot be placed).
const STUNT_ORDER := ["corridor", "mega", "tower", "ramp", "mega", "gas", "tower", "corridor"]
# Story lines shown in the middle of the screen when these events happen (once each).
const EVENT_CAPTIONS := {
	"roadblock": "THEY BLOCKED THE ROAD", "heli": "NOW A HELICOPTER?!", "swat": "THE SWAT TRUCK ARRIVES",
	"big_air": "SEND IT!", "mega_jump": "NO WAY...", "trap_set": "ONE LAST TRICK...", "trap": "BOOM.",
	"collapse": "TIMBER!", "gas": "GAS STATION = BOMB", "chain": "CHAIN REACTION!", "near_miss": "TOO CLOSE!",
	"broke_free": "STILL ALIVE!", "heli_down": "HELICOPTER DOWN!", "swat_down": "SWAT DOWN!",
	"train_hit": "THE TRAIN DIDN'T STOP", "emp": "LIGHTS OUT.", "spray": "NEW CAR. WHO DIS?", "safehouse": "SAFE.",
	"spike_cop": "OWN SPIKES!", "oil_spin": "SLIPPERY!", "gate_smash": "NO TIME TO WAIT", "shield": "UNTOUCHABLE",
}
const START_CAPTIONS := {
	"chase": "ONE CAR. NO BRAKES.", "survive": "5 STARS. NO ESCAPE.", "destroy": "HOW MUCH CAN IT BREAK?",
	"heli": "THEY SENT A HELICOPTER.", "rush": "RUSH HOUR. NO RULES.", "stunt": "NO RAMP IS TOO BIG.",
	"escape": "ESCAPE THE CITY.",
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
# escape show
var esc_i := 0
var esc_wait := 1.2
var esc_tries := 0.0
var esc_low := -1.0       # heat floor after the spray shop
var route_beat := ""      # "train", "spray" or "house" while the bot drives a route for it
var route_t := 0.0
var train_x := 0.0
var train_dirz := 1.0
var train_called := false
var train_passed := -1.0
var train_cam := false
var train_victim := false
var train_hold := false   # stopped short of the crossing to let the train by
var booth := {}
var spray_dirz := 1.0
var spray_lane := false
var spray_cam := false
var spray_t := -1.0
var house := {}
var house_cam := false
var house_t := -1.0
var tool_after := 0.0
var tool_due := ""         # a tool pickup put on the road for the bot ...
var tool_due_t := 0.0      # ... which it gets anyway by then
var ram := {}             # the roadblock the shielded car drives through: c, dir
var ram_cam := false
var spikes := {}


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
		"escape":
			bot.cruise = 30.0
			start_heat = 14.0
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
		"escape":
			# fewer cars than a chase: a pack that swarms the car at every corner leaves no room
			# for the set pieces (the train, the spray shop, the safehouse)
			main.cap_bonus = 0
			main.spawn_gap = Vector2(2.4, 3.8)
			_opening_police(3)
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
		return _spawn_behind(randf_range(45.0, 75.0)) != null
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
	return _spawn_behind(randf_range(55.0, 80.0)) != null


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


func _spawn_behind(back: float, min_d: float = 40.0) -> Car:
	var tp: Dictionary = bot.trail_point(back)
	if tp.is_empty():
		return null
	var pos: Vector3 = tp["pos"]
	if pos.distance_to(main.player.global_position) < min_d:
		return null
	for c in main.police:
		if is_instance_valid(c) and c.global_position.distance_to(pos) < 8.0:
			return null
	var dirv: Vector3 = tp["dir"]
	return main.spawn_police_at(pos, atan2(-dirv.x, -dirv.z), 24.0)


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
		var head := "HELICOPTER DOWN" if main.stats["heli_down"] > 0 else "SURVIVED"
		if main.stats["safehouse"] > 0:
			head = "ESCAPED"
		main.hud.show_over(end_text(head))
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
		var extra := ""
		if mode == "heli":
			extra = " heli=%s d=%.0f jump_stage=%d" % [main.heli.state, main.heli.global_position.distance_to(pl.global_position), jump_stage]
		elif mode == "escape":
			var r: Rail = main.rail
			extra = " beat=%s esc=%d train=%s front=%.0f v=%.0f eta=%.1f tool=%s" % [route_beat, esc_i, str(r.running), r.front, r.speed,
				r.eta(train_x) if route_beat == "train" else -1.0, main.gadgets.tool]
		print(bot.debug_line(t), " cops=%d lvl=%d busted=%.2f hp=%d" % [main.alive_police(), main.level, main.busted, int(pl.hp)], extra)
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
	_use_tools(t)
	if mode == "escape":
		_train_tick(t)
		_spray_tick(t)
		_ram_tick(t)
		_spike_tick(t)
		_house_tick(t)
	_camera(t)
	_break_free(dt)
	_stunt_jam(dt)
	_rescue(t)
	_unwedge(dt)
	_jump_moment()
	if (bot.replan_needed or bot.needs_plan()) and not bot.external:
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
		"escape":
			heat_floor = esc_low if esc_low >= 0.0 else (14.0 if f < 0.45 else 32.0)
		_:
			heat_floor = 90.0


func _beats(t: float) -> void:
	var f := t / duration
	if mode == "escape":
		_escape_show(t)
		return
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
	var origin := Vector3.ZERO
	var dirv := Vector3.ZERO
	if bot.straight_ahead() >= ahead + 75.0:
		var pa: Dictionary = bot.point_ahead(ahead)
		origin = pa["pos"]
		dirv = pa["dir"]
	else:
		# the route turns soon: go straight on instead, if the road ahead allows it
		var ax: Dictionary = bot.stunt_axis(105.0, 38.0)
		if ax.is_empty():
			return false
		origin = ax["origin"]
		dirv = ax["dir"]
	origin.y = 0.0
	var info: Dictionary = main.stunts.build_kicker(origin, dirv)
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
		main.cam_look_w = 0.0
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
		"escape":
			return "CASH %d   COPS %d   COMBO x%d" % [main.gadgets.cash, cops, main.gadgets.combo]
	return "COPS %d   %s   %d KM/H" % [cops, clock_s, int(absf(main.player.fwd_speed) * 3.6)]


func end_text(kind: String) -> String:
	var lines := PackedStringArray([kind + ("!" if kind in ["SURVIVED", "HELICOPTER DOWN", "ESCAPED"] else ""), ""])
	lines.append("COPS WRECKED  %d" % main.wrecked)
	if mode == "escape":
		lines.append("CASH  %d" % main.gadgets.cash)
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
		"train_hits": st["train_hits"],
		"emp_hits": st["emp_hits"],
		"oil_spins": st["oil_spins"],
		"spike_cops": st["spike_cops"],
		"cash": st["cash"],
		"sprays": st["sprays"],
		"safehouse": st["safehouse"],
		"combo_best": main.gadgets.combo_best,
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
	e += 10.0 * st["train_hits"] + 3.0 * st["emp_hits"] + 4.0 * st["oil_spins"] + 4.0 * st["spike_cops"]
	e += 1.0 * st["cash"] + 6.0 * st["sprays"] + 15.0 * st["safehouse"]
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


# ------------------------------------------------------------ the escape show

# One beat after another: cash, a spike strip, the train, the EMP, a shield through a
# roadblock, an oil slick, the spray shop; and in time for the end of the clip, the safehouse.
func _escape_show(t: float) -> void:
	if house_t >= 0.0:
		return
	var committed := (route_beat == "train" and train_passed < 0.0) or (route_beat == "spray" and spray_t < 0.0)
	if route_beat != "house" and not committed and t > duration * 0.45:
		# head for the safehouse in time; a train or spray run under way finishes first
		var est := _house_eta()
		var late := 0.0 if route_beat in ["train", "spray"] else 6.0
		if est > 0.0 and t + est >= duration - late and _plan_house():
			return
	if route_beat == "house":
		# on the way there the smaller beats go on, until the door is near
		if (house["door"] as Vector3).distance_to(main.player.global_position) < 160.0:
			return
	elif route_beat != "":
		if t - route_t > 28.0:
			route_beat = ""
		return
	if t < esc_wait:
		return
	var kind: String = ESCAPE_ORDER[esc_i % ESCAPE_ORDER.size()]
	if route_beat == "house" and kind in ["train", "spray"]:
		esc_i += 1
		return
	if esc_tries == 0.0:
		esc_tries = t
	var ok := false
	match kind:
		"cash":
			ok = _cash_line()
		"spikes":
			ok = _escape_spikes()
		"train":
			ok = _plan_train()
		"emp", "oil":
			ok = _hand_tool(kind)
		"shield":
			ok = _shield_block()
		"spray":
			ok = _plan_spray()
	if ok:
		done[kind + str(esc_i)] = t
		esc_i += 1
		esc_tries = 0.0
		esc_wait = t + 4.0
	elif t - esc_tries > 7.0:
		esc_i += 1      # cannot be placed from here: on to the next one
		esc_tries = 0.0
		esc_wait = t + 0.5


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# A line of cash down the middle of the road ahead.
func _cash_line() -> bool:
	if bot.busy() or bot.straight_ahead() < 140.0:
		return false
	for i in 5:
		var pa: Dictionary = bot.point_ahead(45.0 + i * 14.0)
		main.world.props.add_pickup(_flat(pa["pos"]), "cash", true)
	return true


# A spike strip across most of the road ahead. The car goes through the gap; once it is past,
# the strip is pulled right across, into the path of the police behind it.
func _escape_spikes() -> bool:
	if bot.busy() or bot.straight_ahead() < 180.0:
		return false
	var pa: Dictionary = bot.point_ahead(120.0)
	var c: Vector3 = pa["pos"]
	var dirv: Vector3 = pa["dir"]
	var gap_left := randf() < 0.5
	var d: Dictionary = main.gadgets.drop_spikes(c, dirv, 9.5, 2.25 if gap_left else -2.25)
	d["road_c"] = _flat(c)
	bot.dodge(c + dirv * 10.0, dirv, 4.75 if gap_left else -4.75)
	spikes = d
	_spawn_behind(28.0, 20.0)
	return true


func _spike_tick(t: float) -> void:
	if spikes.is_empty():
		return
	if not main.gadgets.strips.has(spikes):
		spikes = {}
		return
	var rel: Vector3 = main.player.global_position - (spikes["p"] as Vector3)
	var along: float = rel.dot(spikes["dir"])
	if along > -60.0 and along < 4.0:
		bot.steady_until = t + 0.3     # hold the gap: no swerving back into the strip for traffic
	if along > 4.0:
		main.gadgets.widen_strip(spikes)
		spikes["born"] = t
		spikes["life"] = 9.0
		spikes = {}


# A pickup (EMP or oil) on the road ahead; the bot uses it when the moment is right.
func _hand_tool(kind: String) -> bool:
	if bot.busy() or bot.straight_ahead() < 120.0 or main.gadgets.tool != "":
		return false
	var pa: Dictionary = bot.point_ahead(50.0)
	main.world.props.add_pickup(_flat(pa["pos"]), kind, true)
	tool_after = main.clock + 2.5
	tool_due = kind
	tool_due_t = main.clock + 5.0
	return true


# Any mode: a bot carrying a tool uses it when it pays off. EMP when the police are close
# around it; oil when one is right behind, lined up.
func _use_tools(t: float) -> void:
	if scripted:
		return
	var g: Gadgets = main.gadgets
	if tool_due != "" and t >= tool_due_t:
		# the bot drove past the pickup: it has it anyway
		if g.tool == "":
			g.tool = tool_due
		tool_due = ""
	if g.tool != "" and g.tool == tool_due:
		tool_due = ""
	if g.tool == "" or t < tool_after or main.game_over or house_t >= 0.0:
		return
	# not while a train is due: the police behind should meet it, not stall short of it
	if route_beat == "train":
		return
	var pl: Car = main.player
	if g.tool == "emp":
		var near := 0
		for c in main.police:
			if is_instance_valid(c) and not c.dead and t >= c.stall_until and c.global_position.distance_to(pl.global_position) < 26.0:
				near += 1
		if near >= 2 or (near >= 1 and (main.busted > 0.15 or t - tool_after > 3.0)):
			main.cam_mode = "heli"
			main.cam_cut = true
			shot_end = t + 2.6
			g.use_tool()
			main.slowmo(1.1, 0.4)
		elif t - tool_after > 3.0 and near == 0:
			_spawn_behind(22.0, 15.0)
			_spawn_behind(34.0, 25.0)
			tool_after = t + 1.5
		return
	if g.tool == "oil":
		var f := -pl.global_transform.basis.z
		f.y = 0.0
		f = f.normalized()
		var side := f.cross(Vector3.UP)
		for c in main.police:
			if not is_instance_valid(c) or c.dead:
				continue
			var rel: Vector3 = c.global_position - pl.global_position
			var behind := -rel.dot(f)
			if behind > 5.0 and behind < 30.0 and absf(rel.dot(side)) < 5.5 and pl.speed > 12.0:
				main.cam_mode = "front"
				main.cam_cut = true
				shot_end = t + 3.0
				g.use_tool()
				return
		if t - tool_after > 4.0:
			_spawn_behind(18.0, 12.0)
			_spawn_behind(30.0, 22.0)
			tool_after = t + 1.5


# A shield on the road ahead, and a roadblock beyond it to drive straight through.
func _shield_block() -> bool:
	if bot.busy() or bot.straight_ahead() < 230.0:
		return false
	var pa: Dictionary = bot.point_ahead(55.0)
	main.world.props.add_pickup(_flat(pa["pos"]), "shield", true)
	var pb: Dictionary = bot.point_ahead(170.0)
	var c: Vector3 = pb["pos"]
	var dirv: Vector3 = pb["dir"]
	c.y = 0.9
	main.spawn_roadblock_at(c, atan2(-dirv.x, -dirv.z))
	main.log_event("roadblock")
	ram = {"c": _flat(c), "dir": dirv}
	ram_cam = false
	return true


func _ram_tick(t: float) -> void:
	if ram.is_empty():
		return
	var pl: Car = main.player
	var c: Vector3 = ram["c"]
	var dirv: Vector3 = ram["dir"]
	var along := (c - _flat(pl.global_position)).dot(dirv)
	if along < -25.0 or along > 260.0:
		ram = {}
		return
	if main.gadgets.shielded() and along < 70.0 and along > -4.0:
		bot.ram_until = t + 0.6
		bot.lane = 0.0
		if not ram_cam and along > 30.0:
			# from beside the roadblock: the car comes straight at it and through
			ram_cam = true
			main.cam_anchor = c + dirv * 14.0 + dirv.cross(Vector3.UP) * 8.5 + Vector3(0, 2.4, 0)
			main.cam_mode = "anchor"
			main.cam_cut = true
			pass_until = t + 4.5


# Route to a level crossing, timed with a train: the car goes over a second before the
# train arrives, and the police behind it meet the train.
func _plan_train() -> bool:
	if bot.busy() or not main.rail.enabled or (main.rail.running and route_beat != "train"):
		return false
	var zr: float = main.world.rail_z()
	var a := bot.node_ahead()
	var h := bot._grid_dir()
	var north: bool = main.player.global_position.z < zr
	var rr0 := World.RAIL_ROW
	var dz := 1 if north else -1
	var best: Array[Vector2i] = []
	var best_s := INF
	var best_k := -1
	for k in range(2, World.N - 1):
		if k == 4 or k == 11:
			continue
		var before := Vector2i(k, rr0 if north else rr0 + 1)
		var pre := before - Vector2i(0, dz)
		var after := before + Vector2i(0, dz)
		var beyond := after + Vector2i(0, dz)
		if not bot._inside(pre) or not bot._inside(beyond) or bot._blocked(before) or bot._blocked(after) or bot._blocked(beyond):
			continue
		for xf in [true, false]:
			var r: Array[Vector2i] = bot._route(a, before, h, xf)
			if r.size() < 2 or r[r.size() - 1] - r[r.size() - 2] != Vector2i(0, dz):
				continue
			var lenm: float = float(r.size() - 1) * World.PITCH + main.player.global_position.distance_to(main.world.node_pos(a))
			if lenm < 140.0 or lenm > 560.0:
				continue
			var sc := absf(lenm - 240.0) + randf() * 40.0
			if sc < best_s:
				best_s = sc
				r.append(after)
				r.append(beyond)
				best = r
				best_k = k
			break
	if best.is_empty():
		return false
	var pts: Array = []
	var kinds: Array = []
	for n in best:
		pts.append(main.world.node_pos(n))
		kinds.append("road")
	bot.set_plan(pts, kinds, "train")
	route_beat = "train"
	route_t = main.clock
	train_x = main.world.line(best_k)
	train_dirz = float(dz)
	train_called = false
	train_passed = -1.0
	train_cam = false
	train_victim = false
	return true


func _train_tick(t: float) -> void:
	if route_beat != "train":
		return
	var pl: Vector3 = main.player.global_position
	var zr: float = main.world.rail_z()
	var rail: Rail = main.rail
	var to_go := (zr - pl.z) * train_dirz
	var on_road := absf(pl.x - train_x) < 10.0
	if train_passed < 0.0 and (bot.replan_needed or bot.plan_name != "train"):
		# knocked off the route (a crash, a pile-up): a new route to a crossing if there is one
		if bot.replan_needed and _plan_train():
			return
		route_beat = ""
		rail.timed = {}
		if train_hold:
			train_hold = false
			bot.halt = false
		if train_cam:
			train_cam = false
			pass_until = main.clock
		return
	if train_passed < 0.0:
		if on_road and to_go < -2.0:
			train_passed = t
			rail.after_speed = 42.0
			if rail.eta(train_x) < 2.6:
				main.log_event("train_close")
				main.slowmo(0.9, 0.45)
				# a police car right on the car's tail, so the train has someone to meet
				var close := false
				for c in main.police:
					if is_instance_valid(c) and not c.dead and absf(c.global_position.x - train_x) < 8.0:
						var behind: float = (c.global_position.z - zr) * -train_dirz
						if behind > 0.0 and behind < 45.0:
							close = true
				if not close:
					_spawn_behind(30.0, 22.0)
				if trace:
					var info := []
					for c in main.police:
						if is_instance_valid(c) and not c.dead:
							info.append("(%.0f,%.0f v%.0f)" % [c.global_position.x - train_x, (c.global_position.z - zr) * -train_dirz, c.speed])
					print("TRAIN PASS t=%.1f eta=%.2f cops rel=%s" % [t, rail.eta(train_x), " ".join(info)])
				# the police behind do not see the train coming in time
				for c in main.police:
					if is_instance_valid(c) and not c.dead and absf(c.global_position.x - train_x) < 10.0:
						c.reckless_until = t + 3.0
			return
		# safety: if the train will be there first after all, stop short of the crossing
		if on_road and to_go > 0.0 and to_go < 70.0:
			var car_eta: float = to_go / maxf(main.player.speed, 3.0)
			var tr_eta: float = rail.eta(train_x)
			if (tr_eta < car_eta + 0.7 and tr_eta < 3.5) or rail.occupied(train_x, 6.0):
				if to_go > 9.0 and not train_hold:
					train_hold = true
					bot.halt = true
					for c in main.police:
						if is_instance_valid(c):
							c.reckless_until = 0.0
		if train_hold:
			if not rail.occupied(train_x, 8.0) and rail.eta(train_x) == INF:
				train_hold = false
				bot.halt = false
			return
		var rem: float = (to_go if on_road else absf(pl.x - train_x) + absf(pl.z - zr))
		var eta: float = maxf(rem, 0.0) / maxf(main.player.speed, 14.0)
		var at := t + eta + 1.35
		if not train_called:
			train_called = rail.call_train(train_x, at)
		elif eta > 0.4:
			rail.retime(at)
		if train_called and on_road and to_go < 90.0 and to_go > 30.0 and not train_victim:
			# a police car right on the car's tail: it follows it over, and meets the train
			train_victim = true
			var cop := _spawn_behind(26.0, 18.0)
			if cop != null:
				cop.reckless_until = t + 7.0
		if train_called and on_road and to_go < 75.0 and to_go > 8.0 and not train_cam:
			# past the crossing, on the sidewalk, looking back at the car coming over
			train_cam = true
			var dirv := Vector3(0, 0, train_dirz)
			main.cam_anchor = Vector3(train_x, 0.0, zr) + dirv * 15.0 + Vector3(8.6 * (1.0 if randf() < 0.5 else -1.0), 2.6, 0.0)
			main.cam_mode = "anchor"
			main.cam_cut = true
			pass_until = t + 30.0
			main.cam_look = Vector3(train_x, 1.6, zr)
			main.cam_look_w = 0.0
	else:
		var since := t - train_passed
		if train_cam:
			# once the car is over, the camera turns to the crossing: the train and the police
			main.cam_look_w = clampf(since / 0.8, 0.0, 0.75)
		if since > 4.0 or not rail.running:
			route_beat = ""
			train_cam = false
			pass_until = t
			main.cam_look_w = 0.0


# Route along the road with a spray booth on it, lined up with the booth's lane.
func _plan_spray() -> bool:
	if bot.busy():
		return false
	var a := bot.node_ahead()
	var h := bot._grid_dir()
	var best: Array[Vector2i] = []
	var best_b := {}
	var best_dz := 1.0
	var best_s := INF
	for b: Dictionary in main.gadgets.booths:
		var k := roundi((float(b["road_x"]) + World.HALF) / World.PITCH)
		var bz: float = (b["p"] as Vector3).z
		var m := int(floor((bz + World.HALF) / World.PITCH))
		for dz in [1, -1]:
			var before := Vector2i(k, m) if dz > 0 else Vector2i(k, m + 1)
			var pre := before - Vector2i(0, dz)
			var after := before + Vector2i(0, dz)
			if not bot._inside(pre) or not bot._inside(after) or bot._blocked(before) or bot._blocked(after):
				continue
			var man := absi(pre.x - a.x) + absi(pre.y - a.y)
			if man > 8:
				continue
			for xf in [true, false]:
				var r: Array[Vector2i] = bot._route(a, before, h, xf)
				if r.size() < 2 or r[r.size() - 1] - r[r.size() - 2] != Vector2i(0, dz):
					continue
				var sc := float(r.size()) + randf()
				if sc < best_s:
					best_s = sc
					r.append(after)
					# one node more, so the plan does not run out just before the booth
					if bot._inside(after + Vector2i(0, dz)) and not bot._blocked(after + Vector2i(0, dz)):
						r.append(after + Vector2i(0, dz))
					best = r
					best_b = b
					best_dz = float(dz)
				break
	if best.is_empty():
		return false
	var pts: Array = []
	var kinds: Array = []
	for n in best:
		pts.append(main.world.node_pos(n))
		kinds.append("road")
	bot.set_plan(pts, kinds, "spray")
	booth = best_b
	spray_dirz = best_dz
	spray_lane = false
	spray_cam = false
	route_beat = "spray"
	route_t = main.clock
	return true


func _spray_tick(t: float) -> void:
	if route_beat != "spray" or booth.is_empty():
		return
	if spray_t < 0.0 and bot.plan_name != "spray":
		route_beat = ""
		booth = {}
		return
	var pl: Vector3 = main.player.global_position
	var bp: Vector3 = booth["p"]
	var road_x: float = booth["road_x"]
	var to_b := (bp.z - pl.z) * spray_dirz
	var on_road := absf(pl.x - road_x) < 9.0
	var dirv := Vector3(0, 0, spray_dirz)
	if spray_t >= 0.0 and t - spray_t > 2.5:
		route_beat = ""
		booth = {}
		pass_until = t
		return
	if not on_road:
		return
	if not spray_lane and to_b < 95.0 and to_b > 10.0:
		spray_lane = true
		var left := Vector3.UP.cross(dirv)
		bot.dodge(bp + dirv * 9.0, dirv, (bp.x - road_x) * left.x)
	if spray_lane and to_b > -8.0:
		bot.booth_ok_until = t + 0.3      # lined up: drive between the booth's walls
	if not spray_cam and to_b < 55.0 and to_b > 12.0:
		# just past the booth's exit, on its far side: the car comes out in new paint
		spray_cam = true
		var side := signf(bp.x - road_x)
		main.cam_anchor = Vector3(road_x + side * 9.2, 2.3, bp.z + spray_dirz * 15.0)
		main.cam_mode = "anchor"
		main.cam_cut = true
		pass_until = t + 6.0
	if to_b < -12.0 and spray_t < 0.0:
		route_beat = ""       # went past without a respray (cooldown): carry on
		booth = {}


func on_spray(nl: int) -> void:
	spray_t = main.clock
	esc_low = (float(main.LEVEL_HEAT[nl - 1]) + 0.5) if nl > 0 else 0.0
	heat_floor = esc_low
	done["spray"] = main.clock


# Rough seconds to the nearest safehouse from here.
func _house_eta() -> float:
	var h: Dictionary = main.gadgets.nearest_house(main.player.global_position)
	if h.is_empty():
		return -1.0
	var d: Vector3 = (h["door"] as Vector3) - main.player.global_position
	return (absf(d.x) + absf(d.z)) / 20.0 + 5.0


# Finale: drive to the safehouse, turn in through the door and stop inside.
func _plan_house() -> bool:
	var a := bot.node_ahead()
	var h := bot._grid_dir()
	var hs: Array = main.gadgets.houses.duplicate()
	var pp: Vector3 = main.player.global_position
	hs.sort_custom(func(x, y): return (x["door"] as Vector3).distance_to(pp) < (y["door"] as Vector3).distance_to(pp))
	for hh: Dictionary in hs:
		var bk: Vector2i = hh["block"]
		var door: Vector3 = hh["door"]
		var rx: float = main.world.line(bk.x)
		# from the south (heading north) there is a longer straight run up to the door
		for dz in [-1, 1]:
			var before := Vector2i(bk.x, bk.y + 1) if dz < 0 else Vector2i(bk.x, bk.y)
			var pre := before - Vector2i(0, dz)
			if not bot._inside(pre) or bot._blocked(before):
				continue
			var route: Array[Vector2i] = []
			for xf in [true, false]:
				var r: Array[Vector2i] = bot._route(a, before, h, xf)
				if r.size() >= 2 and r[r.size() - 1] - r[r.size() - 2] == Vector2i(0, dz):
					route = r
					break
				if r.size() == 1 and h == Vector2i(0, dz):
					route = r
					break
			if route.is_empty():
				continue
			var pts: Array = []
			var kinds: Array = []
			for n in route:
				pts.append(main.world.node_pos(n))
				kinds.append("road")
			var fz := float(dz)
			pts.append(Vector3(rx - 1.5, 0.9, door.z - fz * 14.0))
			kinds.append("road")
			pts.append(Vector3(rx + 4.0, 0.9, door.z - fz * 1.0))
			kinds.append("garage")
			pts.append(Vector3(door.x - 1.0, 0.9, door.z))
			kinds.append("garage")
			pts.append(Vector3(door.x + 9.0, 0.9, door.z))
			kinds.append("garage")
			bot.set_plan(pts, kinds, "garage")
			bot.external = true
			house = hh
			house_cam = false
			route_beat = "house"
			route_t = main.clock
			return true
	return false


func _house_tick(t: float) -> void:
	if route_beat != "house" or house.is_empty():
		return
	if house_t >= 0.0:
		return
	if bot.replan_needed:
		bot.external = false
		route_beat = ""
		if not _plan_house():
			bot.plan_flee(_away_point())
		return
	var door: Vector3 = house["door"]
	var pl: Vector3 = main.player.global_position
	if not house_cam and pl.distance_to(door) < 75.0:
		# across the road from the door: the car turns in and the door comes down
		house_cam = true
		var bk: Vector2i = house["block"]
		var rx: float = main.world.line(bk.x)
		var dz := signf(pl.z - door.z)
		main.cam_anchor = Vector3(rx - 8.5, 3.0, door.z + dz * 13.0)
		main.cam_mode = "anchor"
		main.cam_cut = true
		pass_until = t + 60.0
		main.cam_look = door + Vector3(2.0, 1.6, 0)
		main.cam_look_w = 0.35


func on_safehouse(_h: Dictionary) -> void:
	house_t = main.clock
	still = true
	bot.external = true
	main.cam_look_w = 0.6
	# a few seconds of the door coming down and the police outside, then the end
	duration = minf(duration, main.clock + 4.5)
	climax_t = minf(climax_t, duration)


# Last resort for a video: the car has not got anywhere for several seconds (wedged on a ramp
# edge, inside a block, in a heap of cars). Cut to a new shot with it back on the nearest road.
var prog_p := Vector3.ZERO
var prog_t := 0.0


func _rescue(t: float) -> void:
	var pl: Car = main.player
	var p := pl.global_position
	if bot.halt or house_t >= 0.0 or scripted or main.cine_t > 0.0:
		prog_p = p
		prog_t = t
		return
	if p.distance_to(prog_p) > 9.0:
		prog_p = p
		prog_t = t
		return
	if t - prog_t < 6.0:
		return
	prog_p = p
	prog_t = t
	var kx := clampi(roundi((p.x + World.HALF) / World.PITCH), 1, World.N - 1)
	var kz := clampi(roundi((p.z + World.HALF) / World.PITCH), 1, World.N - 1)
	var lx: float = main.world.line(kx)
	var lz: float = main.world.line(kz)
	var q := Vector3.ZERO
	var dirv := Vector3.ZERO
	var away := _away_point()
	if absf(p.x - lx) < absf(p.z - lz):
		q = Vector3(lx, 0.9, clampf(p.z, -World.HALF + 20.0, World.HALF - 20.0))
		dirv = Vector3(0, 0, 1.0 if q.z > away.z else -1.0)
	else:
		q = Vector3(clampf(p.x, -World.HALF + 20.0, World.HALF - 20.0), 0.9, lz)
		dirv = Vector3(1.0 if q.x > away.x else -1.0, 0, 0)
	# off the railway and out of the way of any car right there
	if absf(q.z - main.world.rail_z()) < 8.0:
		q.z += 12.0 * signf(dirv.z if dirv.z != 0.0 else 1.0)
	for c in main.cars_near(q, 6.0):
		if not c.is_player:
			c.global_position += Vector3(0, 0, 9.0) if dirv.x != 0.0 else Vector3(9.0, 0, 0)
	pl.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dirv.x, -dirv.z)), q)
	pl.linear_velocity = dirv * 14.0
	pl.angular_velocity = Vector3.ZERO
	main.cam_mode = "chase"
	main.cam_cut = true
	main.cam_dir = dirv
	main.cam_look_w = 0.0
	pass_until = t
	main.busted = 0.0
	if route_beat == "house":
		bot.external = false
		route_beat = ""
	elif route_beat != "":
		route_beat = ""
		main.rail.timed = {}
	bot.replan_needed = true
	main.log_event("rescue")


# Sitting on top of another car (a police car rammed in underneath): the wheels touch nothing,
# so neither driving nor reversing helps. Slide the car off and shove the others away.
var wedge_t := 0.0


func _unwedge(dt: float) -> void:
	var pl: Car = main.player
	if pl.airtime > 0.6 and pl.speed < 3.0 and not bot.halt:
		wedge_t += dt
	else:
		wedge_t = 0.0
	if wedge_t < 0.8:
		return
	wedge_t = 0.0
	var f := -pl.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	for c in main.cars_near(pl.global_position, 7.0):
		if c.is_player:
			continue
		var away: Vector3 = c.global_position - pl.global_position
		away.y = 0.0
		c.apply_central_impulse((away.normalized() * 7.0 + Vector3(0, 2.0, 0)) * c.mass)
	pl.linear_velocity = f * 7.0 + Vector3(0, 3.0, 0)
	pl.angular_velocity = Vector3.ZERO
	var yaw := atan2(-f.x, -f.z)
	pl.global_transform = Transform3D(Basis(Vector3.UP, yaw), pl.global_position + Vector3(0, 0.6, 0))
	main.log_event("broke_free")
