class_name Oracle
extends RefCounted
# The director's eyes on the road for the swarm show: "the director saves the car".
#
# Every tenth of a second or so it looks 3 s ahead at every car that could get in the way of the bot's
# car (traffic, police, wrecks) and tries 21 moves: a lane to drive in (7 of them) and braking, holding
# or nitro (3). Each move is played out against where those cars will be (a car keeps its velocity; a
# jousting police car, see Car.line_until, drives straight on, so that is exact) and scored:
#   - a clean miss costs nothing, a hit costs more the faster the cars close on each other (a hit at
#     speed is never chosen), and anything closer than half a metre counts as a hit;
#   - a near miss at speed, a metre or so edge to edge, is good television and earns a bonus;
#   - the director can open a "hit window" in which a small hit (5 to 20 m/s) is wanted, and `risk`
#     (0 calm .. 1 wild) says how much a small hit is minded the rest of the time.
# The best move goes to the bot as a lane, a speed cap and nitro. When even the best move still ends
# in a hard hit within a second, the car that would hit swerves at the last moment (a "save").

const HORIZON := 3.0
const STEP := 0.15
const SAMPLE := 5.0              # metres between the samples of the bot's path
const SAMPLES := 36
const REACH := 130.0             # cars farther away than this are not looked at
const CAR_W := 0.91              # half width and half length of a car (see Car.build)
const CAR_L := 2.05
const LANES: Array[float] = [-5.0, -3.0, -1.5, 0.0, 1.5, 3.0, 5.0]
const DSPEED: Array[float] = [-11.0, 0.0, 9.0]     # change of speed: brake, hold, nitro
const LAT_RATE := 6.0            # m/s the car can move sideways at most
const LAT_TAU := 0.5             # the car follows a new lane like a spring: 63 % of the way after this many seconds
const LAT_DELAY := 0.15          # s before a new lane shows
const A_UP := 5.0
const A_NITRO := 10.0
const A_DOWN := 8.0
const V_MAX := 50.0
const NEAR := 1.8                # a miss closer than this (edge to edge) is a near miss
const SAFE := 0.45               # ... and closer than this is as good as a hit
const HARD := 24.0               # m/s of closing speed at which a hit is never chosen
const COMMIT := 7.0              # what it costs to pass a car on the other side from the one chosen
const PAD_RATE := 1.6            # a chasing car follows the car sideways: its half width grows this fast (m/s) ...
const PAD_MAX := 2.6             # ... up to this much
const NEAR_ROAD := 4.6           # driving farther than this from the line of the road costs

var main
var bot: Bot
var car: Car
# what the bot reads
var lane := 0.0                  # where to drive, metres to the left (+) of the plan's line
var speed_cap := 0.0             # m/s, 0 = no limit
var nitro := false
var until := 0.0                 # main.clock until which the answer holds
# what the director sets
var risk := 0.3                  # 0 minds every hit, 1 takes small ones
var hit_window := false          # a small hit is wanted now
var enabled := true
# what it counts
var saves := 0
var evasions := 0
var ticks := 0
var seen_peak := 0
var relevant_peak := 0
var next_save := 0.0
var last_lane := 0.0
var last_dv := 1
var info := ""                   # a line for the trace
var debug := false               # --trace: print what it sees and chooses when something is close

var _pp := PackedVector2Array()  # the bot's path, sampled
var _pd := PackedVector2Array()
var _threats: Array[Dictionary] = []
var _commit := {}                # threat id -> the side (+1 left, -1 right) the bot's car passes it on

func setup(main_node, bot_node: Bot) -> void:
	main = main_node
	bot = bot_node
	car = main.player


func off() -> void:
	lane = 0.0
	speed_cap = 0.0
	nitro = false
	until = 0.0


# ------------------------------------------------------------ the path and the cars

func _f2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# The plan sampled every SAMPLE metres from the car on: positions and unit directions.
func _sample_path() -> bool:
	_pp.resize(SAMPLES)
	_pd.resize(SAMPLES)
	var cur := _f2(car.global_position)
	var verts: Array[Vector2] = [cur]
	for i in range(bot.idx, mini(bot.idx + 8, bot.pts.size())):
		var v := _f2(bot.pts[i])
		if v.distance_to(verts[verts.size() - 1]) > 0.5:
			verts.append(v)
	if verts.size() < 2:
		return false
	var seg := 0
	var seg_start := 0.0
	var seg_len := verts[0].distance_to(verts[1])
	var dir := (verts[1] - verts[0]) / maxf(seg_len, 0.01)
	for k in SAMPLES:
		var at := float(k) * SAMPLE
		while at > seg_start + seg_len and seg + 2 < verts.size():
			seg_start += seg_len
			seg += 1
			seg_len = verts[seg].distance_to(verts[seg + 1])
			dir = (verts[seg + 1] - verts[seg]) / maxf(seg_len, 0.01)
		_pp[k] = verts[seg] + dir * (at - seg_start)
		_pd[k] = dir
	return true


func _add_threat(c: Node3D, v: Vector2, h: Vector2, kind: String, predictable: bool, pp: Vector2) -> void:
	var p := _f2(c.global_position)
	if p.distance_squared_to(pp) > REACH * REACH:
		return
	if h.length_squared() < 0.01:
		var f := -c.global_transform.basis.z
		h = Vector2(f.x, f.z)
	var hitter := false
	if c is Car:
		var cc := c as Car
		hitter = not cc.line_passes and main.clock < cc.line_until
	_threats.append({"o": c, "id": c.get_instance_id(), "p": p, "v": v, "h": h.normalized(), "kind": kind, "pred": predictable, "hitter": hitter})


func _gather(pp: Vector2) -> void:
	_threats.clear()
	for c in main.police:
		if is_instance_valid(c) and not c.dead:
			var v := _f2(c.linear_velocity)
			_add_threat(c, v, v if v.length() > 4.0 else Vector2.ZERO, "cop", main.clock < c.line_until or c.is_block, pp)
	for c in main.blocks:
		if is_instance_valid(c) and not c.dead:
			_add_threat(c, _f2(c.linear_velocity), Vector2.ZERO, "block", true, pp)
	for c in main.wrecks:
		if is_instance_valid(c):
			_add_threat(c, _f2(c.linear_velocity), Vector2.ZERO, "wreck", true, pp)
	for c in main.civs:
		if not is_instance_valid(c) or c.dead:
			continue
		if c.moving:
			var d := Vector2(c.dir.x, c.dir.z)
			_add_threat(c, d * c.cruise, d, "civ", true, pp)
		elif c.linear_velocity.length() > 1.5:
			var v2 := _f2(c.linear_velocity)
			_add_threat(c, v2, v2, "civ", false, pp)


# ------------------------------------------------------------ playing a move out

# Separation of two cars (oriented boxes) along the best separating axis: negative = they overlap.
# hp, hj are their unit headings, np, nj the normals; the player's car is CAR_L x CAR_W (half extents),
# the other one CAR_L x wj. With C = |hp.hj| and S = |hp.nj| the half extents of one car along the axes of
# the other work out as below.
func _gap(rel: Vector2, hp: Vector2, hj: Vector2, wj: float) -> float:
	var np_ := Vector2(hp.y, -hp.x)
	var nj := Vector2(hj.y, -hj.x)
	var c := absf(hp.dot(hj))
	var s := absf(hp.dot(nj))
	return maxf(maxf(absf(rel.dot(hp)) - (CAR_L + CAR_L * c + wj * s), absf(rel.dot(np_)) - (CAR_W + CAR_L * s + wj * c)),
		maxf(absf(rel.dot(hj)) - (CAR_L + CAR_L * c + CAR_W * s), absf(rel.dot(nj)) - (wj + CAR_L * s + CAR_W * c)))


# Where the bot's car will be, step by step, if it drives in `lane_t` and changes speed by DSPEED[dv].
func _track(lane_t: float, dv: int, ell0: float, v0: float, vref: float, n: int, ps: PackedVector2Array, hs: PackedVector2Array, vs: PackedVector2Array) -> void:
	var s := 0.0
	var ell := ell0
	var v := v0
	var vt := clampf(vref + DSPEED[dv], 4.0, V_MAX)
	var a_up := A_NITRO if dv == 2 else A_UP
	for k in n:
		var x := minf(s / SAMPLE, float(SAMPLES) - 1.001)
		var i0 := int(x)
		var fr := x - float(i0)
		var base := _pp[i0].lerp(_pp[i0 + 1], fr)
		var d := _pd[i0].lerp(_pd[i0 + 1], fr)
		d = d.normalized() if d.length_squared() > 0.0001 else _pd[i0]
		var left := Vector2(d.y, -d.x)
		var tau := float(k) * STEP
		var ell_next := ell
		if tau >= LAT_DELAY:
			ell_next = ell + clampf((lane_t - ell) * (1.0 - exp(-STEP / LAT_TAU)), -LAT_RATE * STEP, LAT_RATE * STEP)
		var vel := d * v + left * ((ell_next - ell) / STEP)
		ps[k] = base + left * ell
		vs[k] = vel
		hs[k] = vel.normalized() if vel.length_squared() > 1.0 else d
		ell = ell_next
		v = clampf(v + clampf((vt - v) * 3.0, -A_DOWN, a_up) * STEP, 0.0, V_MAX)
		s += v * STEP


# The cars that matter: those that come within 20 m of the bot's car in the next 3 s if it just drives on.
func _relevant(ell0: float, v0: float, n: int) -> Array[Dictionary]:
	var ps := PackedVector2Array()
	var hs := PackedVector2Array()
	var vs := PackedVector2Array()
	ps.resize(n)
	hs.resize(n)
	vs.resize(n)
	_track(ell0, 1, ell0, v0, v0, n, ps, hs, vs)
	var out: Array[Dictionary] = []
	for t in _threats:
		var close := false
		var p: Vector2 = t["p"]
		var v: Vector2 = t["v"]
		for k in range(0, n, 3):
			if (p + v * (float(k) * STEP)).distance_squared_to(ps[k]) < 400.0:
				close = true
				break
		if close:
			out.append(t)
	return out


# What a move would cost, and what it would hit. Returns {"cost", "hit" (the threat, or null), "tau", "vr", "side"}.
func _score(lane_t: float, dv: int, ell0: float, v0: float, vref: float, n: int, rel: Array[Dictionary], ps: PackedVector2Array, hs: PackedVector2Array, vs: PackedVector2Array) -> Dictionary:
	_track(lane_t, dv, ell0, v0, vref, n, ps, hs, vs)
	var cost := 0.0
	var worst := {"hit": null, "tau": 99.0, "vr": 0.0, "side": 1.0, "cost": 0.0, "sides": {}}
	var sides: Dictionary = worst["sides"]
	var w_hit := lerpf(45.0, 8.0, risk)
	var bonus := 0.4 + 0.8 * risk
	for t in rel:
		var p: Vector2 = t["p"]
		var v: Vector2 = t["v"]
		var hj: Vector2 = t["h"]
		var min_gap := 1e9
		var vr_min := 0.0
		var hit_k := -1
		var vr_hit := 0.0
		var side_hit := 1.0
		var side_min := 1.0
		var pred: bool = t["pred"]
		if hit_window and not pred and String(t["kind"]) == "cop":
			continue         # a hit window: the police cars that are chasing are let through, they will hit
		for k in n:
			var tk := float(k) * STEP
			var rv := (p + v * tk) - ps[k]
			if rv.length_squared() > 144.0:
				continue
			var g := _gap(rv, hs[k], hj, CAR_W if pred else CAR_W + minf(PAD_MAX, PAD_RATE * tk))
			if g < min_gap:
				min_gap = g
				vr_min = (vs[k] - v).length()
				side_min = 1.0 if rv.dot(Vector2(hs[k].y, -hs[k].x)) >= 0.0 else -1.0
			if g < 0.0 and hit_k < 0:
				hit_k = k
				vr_hit = (vs[k] - v).length()
				var left := Vector2(hs[k].y, -hs[k].x)
				side_hit = 1.0 if rv.dot(left) >= 0.0 else -1.0
		var c := 0.0
		if pred and min_gap < 6.0:
			var ts: int = t["id"]
			sides[ts] = side_hit if hit_k >= 0 else side_min
			if _commit.has(ts) and float(_commit[ts]) != float(sides[ts]):
				c += COMMIT
		if hit_k >= 0 or min_gap < SAFE:
			var vr := vr_hit if hit_k >= 0 else vr_min
			var hc := w_hit * (0.5 + (vr / 9.0) * (vr / 9.0))
			if vr < 9.0:
				hc *= 1.0 - 0.6 * risk
			if hit_window and vr >= 5.0 and vr <= HARD:
				hc = -12.0
			elif vr > HARD:
				hc += 200.0
			if hit_k < 0:
				hc *= clampf((SAFE - min_gap) / SAFE, 0.2, 1.0)
			c += hc
			if hit_k >= 0 and float(hit_k) * STEP < float(worst["tau"]):
				worst["hit"] = t["o"]
				worst["tau"] = float(hit_k) * STEP
				worst["vr"] = vr_hit
				worst["side"] = side_hit
		elif min_gap < NEAR and vr_min > 12.0 and pred:
			c += -bonus * (1.0 - (min_gap - SAFE) / (NEAR - SAFE))
		if hit_window and bool(t["hitter"]) and hit_k < 0 and min_gap < 40.0:
			c += minf(7.0, 2.5 + min_gap)      # a hit is wanted: aim at the hitter, the farther the miss the worse
		cost += c
	worst["cost"] = cost
	return worst


# ------------------------------------------------------------ the decision

func tick() -> void:
	ticks += 1
	if not enabled or bot.pts.is_empty() or bot.idx >= bot.pts.size() or car.airtime > 0.05 or car.dead \
			or String(bot.kinds[bot.idx]) != "road" or bot.halt or bot.reverse_t > 0.0:
		off()
		return
	if not _sample_path():
		off()
		return
	var pp := _f2(car.global_position)
	_gather(pp)
	seen_peak = maxi(seen_peak, _threats.size())
	var n := int(HORIZON / STEP) + 1
	# where the car is across the road: measured against the leg of the plan it is on
	var leg_a := bot._prev(bot.idx)
	var leg_b := bot._flat(bot.pts[bot.idx])
	var leg := Vector2(leg_b.x - leg_a.x, leg_b.z - leg_a.z)
	var ell0 := 0.0
	if leg.length() > 1.0:
		var ld := leg.normalized()
		ell0 = (pp - Vector2(leg_a.x, leg_a.z)).dot(Vector2(ld.y, -ld.x))
	ell0 = clampf(ell0, -6.0, 6.0)
	var v0 := maxf(car.fwd_speed, 1.0)
	var vref := minf(bot.cruise, bot._corner_limit(bot._flat(car.global_position)))
	vref = maxf(vref, 6.0)
	var rel := _relevant(ell0, v0, n)
	relevant_peak = maxi(relevant_peak, rel.size())
	if rel.is_empty():
		last_lane = lerpf(last_lane, 0.0, 0.5)
		lane = last_lane
		speed_cap = 0.0
		nitro = false
		until = main.clock + 0.4
		last_dv = 1
		info = "clear"
		return
	var ps := PackedVector2Array()
	var hs := PackedVector2Array()
	var vs := PackedVector2Array()
	ps.resize(n)
	hs.resize(n)
	vs.resize(n)
	var best_cost := 1e9
	var best_lane := 0.0
	var best_dv := 1
	var best: Dictionary = {}
	for dv in DSPEED.size():
		if dv == 2 and car.nitro < 12.0:
			continue
		for lane_t in LANES:
			var r := _score(lane_t, dv, ell0, v0, vref, n, rel, ps, hs, vs)
			var cost: float = r["cost"]
			cost += absf(lane_t) * 0.12 + absf(lane_t - ell0) * 0.1
			cost += (absf(lane_t) - NEAR_ROAD) * (absf(lane_t) - NEAR_ROAD) * 2.0 if absf(lane_t) > NEAR_ROAD else 0.0
			cost += 1.0 if dv == 0 else (0.2 if dv == 2 else 0.0)
			if is_equal_approx(lane_t, last_lane) and dv == last_dv:
				cost -= 0.8          # keep to the last choice unless another is clearly better
			if cost < best_cost:
				best_cost = cost
				best_lane = lane_t
				best_dv = dv
				best = r
	var chosen_sides: Dictionary = best.get("sides", {})
	var alive_ids := {}
	for t in rel:
		alive_ids[t["id"]] = true
	for id in _commit.keys():
		if not alive_ids.has(id):
			_commit.erase(id)
	for id in chosen_sides.keys():
		if not _commit.has(id):
			_commit[id] = chosen_sides[id]
	if not is_equal_approx(best_lane, last_lane) or best_dv != last_dv:
		evasions += 1
	last_lane = best_lane
	last_dv = best_dv
	lane = best_lane
	speed_cap = maxf(vref + DSPEED[best_dv], 4.0) if best_dv == 0 else 0.0
	nitro = best_dv == 2
	until = main.clock + 0.4
	info = "lane %.1f dv %d cost %.1f threats %d/%d" % [best_lane, best_dv, best_cost, rel.size(), _threats.size()]
	if debug:
		var near_s := ""
		for t in rel:
			var tp: Vector2 = t["p"]
			var tv: Vector2 = t["v"]
			var d := tp.distance_to(pp)
			if d < 60.0 and bool(t["pred"]):
				var ld := Vector2(bot._flat(car.global_transform.basis.z).z, 0.0)
				near_s += " [%s %.0fm v=%.0f]" % [t["kind"], d, (tv - Vector2(car.linear_velocity.x, car.linear_velocity.z)).length()]
		if best_dv == 0 or v0 < 14.0:
			var all_s := ""
			var shown := 0
			for t in rel:
				var tp: Vector2 = t["p"]
				var tv: Vector2 = t["v"]
				if tp.distance_to(pp) < 30.0 and shown < 8:
					shown += 1
					all_s += " {%s%s %.0fm |v|=%.0f}" % [t["kind"], "*" if bool(t["pred"]) else "", tp.distance_to(pp), tv.length()]
			print("BRAKE t=%.2f v0=%.0f lane=%.1f dv=%d cost=%.1f rel=%d%s" % [main.clock, v0, best_lane, best_dv, best_cost, rel.size(), all_s])
		if near_s != "":
			print("ORACLE t=%.2f ell0=%.1f v0=%.0f %s hit=%s tau=%.2f vr=%.0f%s" % [main.clock, ell0, v0, info, str(best.get("hit") != null), float(best.get("tau", 99.0)), float(best.get("vr", 0.0)), near_s])
	# the save: the best move still ends in a hard hit within a second, so the other car swerves
	var hit: Variant = best.get("hit")
	if hit != null and is_instance_valid(hit) and float(best["tau"]) <= 0.8 and float(best["vr"]) > 16.0 \
			and not (hit_window and float(best["vr"]) <= HARD) and main.clock >= next_save:
		_save(hit, float(best["tau"]), float(best["side"]))


# The car that would hit swerves away from the bot's path at the last moment.
func _save(o: Node3D, tau: float, side: float) -> void:
	next_save = main.clock + 1.5
	if debug:
		var desc := "?"
		for t in _threats:
			if t["o"] == o:
				var tp: Vector2 = t["p"]
				var tv: Vector2 = t["v"]
				desc = "%s pred=%s dist=%.0f m vel=(%.0f,%.0f) |v|=%.0f" % [t["kind"], str(t["pred"]), tp.distance_to(_f2(car.global_position)), tv.x, tv.y, tv.length()]
				if o is Car:
					desc += " line_until=%.1f target=%s hold=%s" % [(o as Car).line_until, str((o as Car).target != null), str((o as Car).hold)]
		print("SAVE t=%.2f tau=%.2f side=%.0f  %s | player v=%.0f lane=%.1f" % [main.clock, tau, side, desc, car.linear_velocity.length(), lane])
	var f := -car.global_transform.basis.z
	var left := Vector3.UP.cross(f)
	var push := left * side
	var dv := clampf(2.8 / maxf(tau, 0.25), 3.0, 9.0)
	if o is CivCar:
		var cc := o as CivCar
		var v := Vector3(cc.dir.x, 0, cc.dir.z) * cc.cruise if cc.moving else cc.linear_velocity
		cc.knock(v)
		cc.apply_central_impulse(push * cc.mass * dv)
	elif o is RigidBody3D:
		var rb := o as RigidBody3D
		rb.apply_central_impulse(push * rb.mass * dv)
	saves += 1
	main.stats["saves"] += 1
	main.log_event("save")
