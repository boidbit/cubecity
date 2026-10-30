class_name Stunts
extends Node3D
# Set pieces the director builds on the road just ahead of the bot, then removes once
# it has passed. They are what makes the city worth watching: a jump from one tower
# top to another, a corridor of barrels, a tower brought down as the car goes by.

# MEGA JUMP, measured along the road from the start of the ramp (metres):
#   0..56     ramp up the face of tower A (rises 11 m)
#   56..70    roof of tower A; the last 8 m kick up 2.2 m
#   70..100   gap
#   100..124  roof of tower B (3 m lower than tower A)
#   124..184  ramp down
# A car leaving the kicker at 20 to 40 m/s lands on tower B or its ramp down; slower or
# faster would fall short or overshoot.
const RAMP_L := 56.0
const RAMP_H := 11.0
const DECK_L := 14.0
const DECK_B_L := 24.0
const KICK_L := 8.0
const KICK_H := 2.2
const GAP := 30.0
const DOWN_L := 60.0
const DROP_B := 3.0
const TOWER_W := 14.0
const RAMP_W := 9.0
const MEGA_LEN := RAMP_L + DECK_L + GAP + DECK_B_L + DOWN_L

var main
var world: World
var live: Array[Dictionary] = []   # {root, a, b, free_at}


func setup(main_node) -> void:
	main = main_node
	world = main.world


func _tower(parent: Node3D, origin: Vector3, dirv: Vector3, s0: float, length: float, height: float, tint: Color, style: float) -> void:
	var b := Basis.looking_at(dirv, Vector3.UP)
	var c := origin + dirv * (s0 + length * 0.5) + Vector3(0, height * 0.5, 0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(TOWER_W, height, length)
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var sz := Vector3(TOWER_W, height, length)
	mi.mesh = World.make_box(sz, sz / World.CELL, Color(tint.r, tint.g, tint.b, style))
	mi.material_override = world.facade_mat
	body.add_child(mi)
	body.transform = Transform3D(b, c)
	parent.add_child(body)


# A drivable slab whose top surface runs from `from` to `to`.
func _ramp(parent: Node3D, from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var thick := 0.6
	var dirv := (to - from).normalized()
	var b := Basis.looking_at(dirv, Vector3.UP)
	var c := (from + to) * 0.5 - b.y * (thick * 0.5)
	world._static_box(Vector3(width, thick, from.distance_to(to)), Transform3D(b, c), color, parent)


func _pt(origin: Vector3, dirv: Vector3, s: float, y: float = 0.0) -> Vector3:
	return origin + dirv * s + Vector3(0, y, 0)


func _register(root: Node3D, a: Vector3, b: Vector3, keep: float) -> void:
	live.append({"root": root, "a": a, "b": b, "free_at": main.clock + keep})
	world.stunt_zones.append([a, b])
	# the structure rises out of the ground while the bot is still far away
	root.position.y = -26.0
	var tw := create_tween()
	tw.tween_property(root, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Tower-top to tower-top jump. Returns the waypoints for the bot.
func build_mega(origin: Vector3, dirv: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var yellow := Color(0.9, 0.68, 0.1)
	var ha := RAMP_H
	var hb := RAMP_H - DROP_B
	_tower(root, origin, dirv, RAMP_L, DECK_L, ha, Color(0.62, 0.62, 0.6), 0.5)
	_tower(root, origin, dirv, RAMP_L + DECK_L + GAP, DECK_B_L, hb, Color(0.3, 0.42, 0.55), 0.85)
	_ramp(root, _pt(origin, dirv, 0.0, 0.05), _pt(origin, dirv, RAMP_L, ha), RAMP_W, yellow)
	var s_kick := RAMP_L + DECK_L - KICK_L
	_ramp(root, _pt(origin, dirv, s_kick, ha), _pt(origin, dirv, RAMP_L + DECK_L, ha + KICK_H), RAMP_W, yellow)
	var s_down := RAMP_L + DECK_L + GAP + DECK_B_L
	_ramp(root, _pt(origin, dirv, s_down, hb), _pt(origin, dirv, s_down + DOWN_L, 0.05), RAMP_W + 2.0, yellow)
	var end := _pt(origin, dirv, MEGA_LEN)
	_register(root, origin - dirv * 12.0, end + dirv * 12.0, 14.0)
	var lip := _pt(origin, dirv, RAMP_L + DECK_L)
	return {
		"pts": [_pt(origin, dirv, -30.0), origin, lip, _pt(origin, dirv, RAMP_L + DECK_L + GAP + 6.0),
			_pt(origin, dirv, s_down + 14.0), _pt(origin, dirv, MEGA_LEN + 28.0)],
		"kinds": ["road", "ramp", "ramp", "air", "road", "road"],
		"lip": lip, "dir": dirv, "ramp_top": _pt(origin, dirv, RAMP_L, ha),
	}


# A short kicker ramp on the road itself (story lab: "jump" right where the story needs it).
# About a second of air at 25-35 m/s.
func build_kicker(origin: Vector3, dirv: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var rl := 15.0
	var h := 2.6
	_ramp(root, _pt(origin, dirv, 0.0, 0.05), _pt(origin, dirv, rl, h), RAMP_W, Color(0.9, 0.68, 0.1))
	# the support under the lip, so it reads as a ramp and not a floating slab
	var lip := _pt(origin, dirv, rl)
	world._static_box(Vector3(RAMP_W, h, 0.5), Transform3D(Basis.looking_at(dirv, Vector3.UP), lip + Vector3(0, h * 0.5, 0) - dirv * 0.25), Color(0.3, 0.3, 0.32), root)
	_register(root, origin - dirv * 10.0, lip + dirv * 6.0, 12.0)
	return {
		"pts": [_pt(origin, dirv, -30.0), origin, lip, _pt(origin, dirv, rl + 30.0), _pt(origin, dirv, rl + 70.0)],
		"kinds": ["road", "ramp", "ramp", "air", "road"],
		"lip": lip, "dir": dirv,
	}


# A run of barrel clusters down the road: they go off one after another as the bot passes.
func build_corridor(origin: Vector3, dirv: Vector3, count: int = 7) -> Dictionary:
	var right := dirv.cross(Vector3.UP)
	for i in count:
		var p := origin + dirv * (i * 9.0) + right * (2.0 if i % 2 == 0 else -2.0)
		world.props.spawn_barrels(p)
	var end := origin + dirv * (count * 9.0)
	return {"pts": [origin - dirv * 30.0, end + dirv * 6.0, end + dirv * 40.0], "kinds": ["road", "road", "road"]}


# Picks a tall building beside the road ahead and returns it with the point to blow at its
# base, or {} if there is none in range.
func pick_tower(origin: Vector3, dirv: Vector3, min_h: int) -> Dictionary:
	var left := Vector3.UP.cross(dirv)
	var best: Building = null
	var best_s := -1e9
	var bk: Vector2i = world.block_of(origin)
	for di in range(-3, 4):
		for dj in range(-3, 4):
			var key := Vector2i(bk.x + di, bk.y + dj)
			if not world.block_buildings.has(key):
				continue
			for b: Building in world.block_buildings[key]:
				if b.ny < min_h or b.collapsing or not b.loaded or b.total_alive() < b.nx * b.nz * b.ny * 0.5:
					continue
				var rel := b.center() - origin
				rel.y = 0.0
				var along := rel.dot(dirv)
				var lat := absf(rel.dot(left))
				if along < 50.0 or along > 150.0 or lat > 36.0:
					continue
				var sc := float(b.ny) - lat * 0.1 + randf()
				if sc > best_s:
					best_s = sc
					best = b
	if best == null:
		return {}
	return {"building": best, "along": (best.center() - origin).dot(dirv)}


# Blow the base of a building and bring it down in a full collapse.
func demolish(b: Building) -> void:
	if b.collapsing or not b.loaded:
		return
	var c := b.center()
	var pl: Vector3 = main.player.global_position
	var toward := Vector3(pl.x - c.x, 0, pl.z - c.z).normalized()
	var base := Vector3(c.x, 2.0, c.z) + toward * minf(b.size_v().x, b.size_v().z) * 0.4
	main.explode_at(base, 9.0, 26.0, 20.0, false, 1.0)
	if not b.collapsing:
		if not b.detailed:
			b._make_detailed()
		b.collapsing = true
		b.collapse_t = 0.0
		world.register_collapse(b)


# Takes down the stunt structure the car is stuck in or next to, so it can drive on.
func dismantle_near(p: Vector3, r: float) -> bool:
	for e in live.duplicate():
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(a + ab * t) < r:
			world.stunt_zones.erase([a, b])
			var root: Node3D = e["root"]
			if is_instance_valid(root):
				root.queue_free()
			live.erase(e)
			return true
	return false


func _process(_dt: float) -> void:
	for e in live.duplicate():
		var root: Node3D = e["root"]
		if not is_instance_valid(root):
			live.erase(e)
			continue
		if main.clock >= float(e["free_at"]):
			var pl: Vector3 = main.player.global_position
			var a: Vector3 = e["a"]
			var b: Vector3 = e["b"]
			# only remove it once the bot is well clear (nobody is on it)
			var ab := b - a
			var t := clampf((pl - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
			if pl.distance_to(a + ab * t) > 70.0 or main.game_over:
				world.stunt_zones.erase([a, b])
				root.queue_free()
				live.erase(e)
