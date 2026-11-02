class_name Gadgets
extends Node3D
# The escape kit, and the places that go with it:
#   spray shop    a drive-through booth over one lane: new paint, two stars less, the police
#                 lose you for a few seconds
#   safehouse     a garage to drive into: the door shuts behind you and you have escaped
#   spike strip   laid across the road ahead by the police: flat tyres for whoever drives over
#                 it (their own cars too)
#   EMP           pickup: every police car near you stalls for a few seconds
#   oil slick     pickup: dropped behind you; police that drive into it spin out
#   shield        pickup: a few seconds of no damage, no BUSTED, and police bounce off
#   cash          pickup: points times the combo; the combo grows with every stunt in a row

const COMBO_TIME := 4.0
const COMBO_MAX := 8
const SHIELD_TIME := 7.0
const EMP_R := 38.0
const SPIKE_LIFE := 30.0
const OIL_LIFE := 22.0
const OIL_R := 4.4
const PAINTS := [Color(0.85, 0.14, 0.1), Color(0.1, 0.45, 0.95), Color(0.98, 0.75, 0.1), Color(0.1, 0.7, 0.35),
	Color(0.6, 0.2, 0.85), Color(0.95, 0.45, 0.1), Color(0.92, 0.92, 0.95), Color(0.08, 0.08, 0.1)]

var main
var world
var booths: Array[Dictionary] = []
var houses: Array[Dictionary] = []
var strips: Array[Dictionary] = []
var slicks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var tool := ""             # "emp" or "oil": the one the player is carrying
var shield_until := 0.0
var shield_node: MeshInstance3D
var combo := 1
var combo_t := 0.0
var combo_best := 1
var cash := 0
var lost := {}             # police car -> clock time it finds the player again (after a respray)
var spike_t := 26.0        # normal play: seconds to the next spike strip
var escaped := false
var safe_house := {}       # the safehouse the player drove into
var flat_spark_t := 0.0
var auto_spikes := true    # normal play lays spike strips by itself; the director lays its own
var story := false         # story lab: the couple's car is not resprayed, does not hide, takes no tools


func setup(main_node) -> void:
	main = main_node
	world = main.world
	_place_booths()
	for sh in world.safehouses:
		houses.append(_build_house(sh))
	# risky cash: in the air over every ramp, and on every level crossing
	for r: Dictionary in world.ramps:
		var p0: Vector3 = r["p0"]
		var p1: Vector3 = r["p1"]
		var d := Vector3(p1.x - p0.x, 0, p1.z - p0.z).normalized()
		var p := p1 + d * 15.0
		world.props.add_pickup(Vector3(p.x, 3.4, p.z), "cash")
	var zr: float = world.rail_z()
	for k in range(1, World.N):
		world.props.add_pickup(Vector3(world.line(k), 0.0, zr), "cash")
	if main.cfg.has("trace"):
		for b in booths:
			print("BOOTH p=%s side=%d" % [str(b["p"]), int(b["side"])])
		for h in houses:
			print("SAFEHOUSE door=%s block=%s" % [str(h["door"]), str(h["block"])])
		print("RAIL z=%.0f" % zr)


func _mat(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, tag: String = "") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	_box(b, size, Vector3.ZERO, mat)
	b.position = pos
	if tag != "":
		b.set_meta(tag, true)
	parent.add_child(b)
	return b


func _label(parent: Node3D, text: String, pos: Vector3, size: int, col: Color, yaw: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	parent.add_child(l)


# ------------------------------------------------------------ spray shops

# Booths over one lane of a north-south road, a quarter of a block from an intersection,
# away from ramps, the railway, the flyovers and the safehouse doors, spread over the city.
func _place_booths() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var cands: Array = []
	for k in range(2, World.N - 1):
		if k == 4 or k == 11:
			continue
		for m in range(1, World.N - 1):
			for q in [18.0, 54.0]:
				var zc: float = world.line(m) + q
				if absf(zc - world.rail_z()) < 26.0:
					continue
				cands.append(Vector3(world.line(k), 0.0, zc))
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Vector3 = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var picked: Array[Vector3] = []
	for c: Vector3 in cands:
		if picked.size() >= 7:
			break
		var ok := true
		for r: Dictionary in world.ramps:
			if ((r["p0"] + r["p1"]) * 0.5).distance_to(c) < 30.0:
				ok = false
		for sh in world.safehouses:
			if (sh["door"] as Vector3).distance_to(c) < 30.0:
				ok = false
		for p in picked:
			if p.distance_to(c) < 250.0:
				ok = false
		if ok:
			picked.append(c)
	for i in picked.size():
		var c: Vector3 = picked[i]
		var side := 1.0 if i % 2 == 0 else -1.0
		booths.append(_build_booth(c, side))
		world.props.clear_rect(Vector3(c.x - 8.5, 0, c.z - 9.0), Vector3(c.x + 8.5, 0, c.z + 9.0))


func _build_booth(c: Vector3, side: float) -> Dictionary:
	var root := Node3D.new()
	var lane_x := c.x + side * 3.7
	root.position = Vector3(lane_x, 0, c.z)
	add_child(root)
	var wall := _mat(Color(0.9, 0.9, 0.92))
	var stripe := _glow(PAINTS[booths.size() % PAINTS.size()], 1.4)
	var dark := _mat(Color(0.15, 0.15, 0.17))
	for s in [-1.0, 1.0]:
		_solid(root, Vector3(0.4, 4.6, 11.0), Vector3(s * 3.1, 2.3, 0), wall, "booth")
		_box(root, Vector3(0.45, 0.35, 11.05), Vector3(s * 3.1, 3.7, 0), stripe)
		for zz in [-3.0, 0.0, 3.0]:
			_box(root, Vector3(0.3, 2.8, 0.18), Vector3(s * 2.8, 1.8, zz), dark)   # nozzle bars
	_box(root, Vector3(6.6, 0.4, 11.2), Vector3(0, 4.8, 0), wall)
	_box(root, Vector3(6.7, 0.3, 11.3), Vector3(0, 5.1, 0), stripe)
	for s in [-1.0, 1.0]:
		_label(root, "SPRAY", Vector3(0, 6.0, s * 5.0), 260, Color(1.0, 0.85, 0.2), 0.0 if s > 0.0 else PI)
	var mist := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 0.3)
	mist.mesh = bm
	mist.amount = 160
	mist.lifetime = 1.2
	mist.one_shot = true
	mist.explosiveness = 0.8
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(2.4, 1.6, 4.5)
	mist.direction = Vector3(0, 1, 0)
	mist.spread = 180.0
	mist.initial_velocity_min = 1.0
	mist.initial_velocity_max = 4.0
	mist.gravity = Vector3(0, -1.0, 0)
	mist.scale_amount_min = 0.6
	mist.scale_amount_max = 1.8
	mist.position = Vector3(0, 1.6, 0)
	mist.emitting = false
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(1, 1, 1, 0.55)
	mm.vertex_color_use_as_albedo = true
	bm.material = mm
	root.add_child(mist)
	return {"p": Vector3(lane_x, 0, c.z), "road_x": c.x, "side": side, "node": root, "mist": mist, "cd": 0.0}


func _respray(b: Dictionary) -> void:
	var pl: Car = main.player
	var now: float = main.clock
	b["cd"] = now + 15.0
	var cur: Color = pl.body_color
	var c: Color = PAINTS[randi() % PAINTS.size()]
	for i in 8:
		if Vector3(c.r, c.g, c.b).distance_to(Vector3(cur.r, cur.g, cur.b)) > 0.3:
			break
		c = PAINTS[randi() % PAINTS.size()]
	pl.body_color = c
	pl.mat_body.set_shader_parameter("color", c)
	for i in 4:
		pl.dents[i] = Vector4()
		pl.mat_body.set_shader_parameter("dent%d" % i, Vector4())
	pl.heal(30.0)
	var mist: CPUParticles3D = b["mist"]
	mist.color = c
	mist.restart()
	mist.emitting = true
	main.fx.play("spray", b["p"] + Vector3(0, 1.5, 0), 2.0)
	main.hud.flash(0.25)
	# two stars less; with police close by it never drops to none (they would vanish)
	var lv: int = main.level
	var near := false
	for cop in main.police:
		if is_instance_valid(cop) and not cop.dead and cop.global_position.distance_to(pl.global_position) < 150.0:
			near = true
	var nl := maxi(lv - 2, 1 if near else 0)
	if lv > 0:
		main.heat = (float(main.LEVEL_HEAT[nl - 1]) + 0.5) if nl > 0 else 0.0
	for cop in main.police:
		if is_instance_valid(cop) and not cop.dead:
			cop.target = null
			lost[cop] = now + 5.0
	main.stats["sprays"] = int(main.stats.get("sprays", 0)) + 1
	main.log_event("spray")
	add_combo(200, "NEW PAINT")
	main.hud.banner("NEW PAINT  -2 STARS")
	if main.director != null:
		main.director.on_spray(nl)


# ------------------------------------------------------------ safehouses

func _build_house(sh: Dictionary) -> Dictionary:
	var door: Vector3 = sh["door"]
	var root := Node3D.new()
	root.position = door
	add_child(root)
	var brick := _mat(Color(0.5, 0.36, 0.3))
	var trim := _mat(Color(0.25, 0.25, 0.27))
	var green := _glow(Color(0.2, 1.0, 0.4), 2.0)
	# +x is into the garage: opening 6.4 wide, 4.4 high; inside 8.5 wide, 13 deep
	_solid(root, Vector3(13.5, 5.6, 0.5), Vector3(6.75, 2.8, -4.5), brick)
	_solid(root, Vector3(13.5, 5.6, 0.5), Vector3(6.75, 2.8, 4.5), brick)
	_solid(root, Vector3(0.5, 5.6, 9.5), Vector3(13.5, 2.8, 0), brick)
	_box(root, Vector3(14.0, 0.5, 9.8), Vector3(6.75, 5.85, 0), trim)
	for s in [-1.0, 1.0]:
		_solid(root, Vector3(0.5, 5.6, 1.1), Vector3(0, 2.8, s * 3.75), brick)
	_box(root, Vector3(0.5, 1.2, 6.4), Vector3(0, 5.0, 0), brick)
	_box(root, Vector3(12.6, 0.05, 8.4), Vector3(6.5, 0.03, 0), _mat(Color(0.3, 0.3, 0.32)))
	_box(root, Vector3(0.12, 0.5, 2.6), Vector3(-0.3, 5.15, 0), green)
	_label(root, "SAFE", Vector3(-0.35, 5.0, 0), 220, Color(0.3, 1.0, 0.5), -PI * 0.5)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(7.0, 4.6, 0)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 2.0
	lamp.omni_range = 12.0
	root.add_child(lamp)
	# the roll-up door: an animated body, so a car really stops against it once it is down
	var dr := AnimatableBody3D.new()
	dr.sync_to_physics = false
	dr.collision_layer = 1
	dr.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.25, 4.4, 6.4)
	cs.shape = bs
	dr.add_child(cs)
	var dm := _mat(Color(0.62, 0.64, 0.66), 0.5)
	dm.metallic = 0.5
	_box(dr, Vector3(0.25, 4.4, 6.4), Vector3.ZERO, dm)
	for i in 8:
		_box(dr, Vector3(0.28, 0.06, 6.42), Vector3(0, -2.0 + i * 0.55, 0), trim)
	root.add_child(dr)
	var d := {"door": door, "dir": sh["dir"], "block": sh["block"], "node": root, "door_node": dr, "open": 0.0,
		"want_open": false, "inside": door + Vector3(8.0, 0, 0), "road": Vector3(world.line(sh["block"].x), 0, door.z)}
	_set_door(d)
	return d


func _set_door(d: Dictionary) -> void:
	var dr: AnimatableBody3D = d["door_node"]
	var o: float = d["open"]
	dr.position = Vector3(0.1, 2.2 + o * 4.3, 0)


func nearest_house(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for h in houses:
		var dd := (h["door"] as Vector3).distance_to(p)
		if dd < bd:
			bd = dd
			best = h
	return best


func _houses(dt: float) -> void:
	var pl: Car = main.player
	var pp := pl.global_position
	for h in houses:
		var door: Vector3 = h["door"]
		var want := false
		if escaped:
			want = false
		else:
			# it only opens for someone on the run
			want = door.distance_to(pp) < 70.0 and (main.level > 0 or main.director != null)
		var o: float = h["open"]
		o = move_toward(o, 1.0 if want else 0.0, dt / (1.0 if want else 0.8))
		if o != h["open"]:
			h["open"] = o
			_set_door(h)
		if not escaped and not story and o > 0.85:
			var rel := pp - door
			if rel.x > 4.0 and rel.x < 13.0 and absf(rel.z) < 3.6:
				_escape(h)


func _escape(h: Dictionary) -> void:
	escaped = true
	safe_house = h
	main.fx.play("door", h["door"] + Vector3(0, 3, 0), 3.0)
	main.stats["safehouse"] = 1
	main.log_event("safehouse")
	add_combo(1000, "SAFEHOUSE")
	main.hud.banner("SAFE!")
	for cop in main.police:
		if is_instance_valid(cop) and not cop.dead:
			lost[cop] = INF
			cop.target = null
	if main.director != null:
		main.director.on_safehouse(h)
	else:
		main.get_tree().create_timer(1.6).timeout.connect(func():
			main._end_game("ESCAPED"))


# ------------------------------------------------------------ spike strips

# A strip across the road at `center`, `width` wide, its middle `offset` metres to the right
# of the road's centre line (looking along `dirv`).
func drop_spikes(center: Vector3, dirv: Vector3, width: float, offset: float) -> Dictionary:
	dirv = Vector3(dirv.x, 0, dirv.z).normalized()
	var right := dirv.cross(Vector3.UP)
	var p := Vector3(center.x, 0.0, center.z) + right * offset
	var root := Node3D.new()
	root.basis = Basis(right, Vector3.UP, -dirv)
	root.position = p
	add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	World.add_box(st, Vector3(0, 0.05, 0), Vector3(width, 0.1, 0.55), Vector3.ONE, Color(0.16, 0.16, 0.17))
	var x := -width * 0.5 + 0.12
	var i := 0
	while x < width * 0.5 - 0.1:
		var c := Color(0.95, 0.8, 0.1) if (int(x / 0.6) % 2 == 0) else Color(0.1, 0.1, 0.1)
		World.add_box(st, Vector3(x, 0.105, -0.27), Vector3(0.2, 0.01, 0.04), Vector3.ONE, c)
		for zz in [-0.12, 0.12]:
			World.add_box(st, Vector3(x + (0.06 if i % 2 == 0 else 0.0), 0.16, zz), Vector3(0.05, 0.14, 0.05), Vector3.ONE, Color(0.75, 0.77, 0.8))
		x += 0.18
		i += 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.4
	m.roughness = 0.5
	mi.material_override = m
	root.add_child(mi)
	root.scale = Vector3(0.05, 1, 1)
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var d := {"p": p, "dir": dirv, "right": right, "w": width, "node": root, "born": main.clock, "hit": {}}
	strips.append(d)
	main.log_event("spikes")
	main.hud.banner("SPIKE STRIP!")
	return d


# The rest of the strip is pulled across: now it covers the whole road.
func widen_strip(d: Dictionary) -> void:
	if not d.has("road_c"):
		return
	var c: Vector3 = d["road_c"]
	var node: Node3D = d["node"]
	var full := 13.6
	var tw := create_tween()
	tw.tween_property(node, "position", c, 0.3)
	tw.parallel().tween_property(node, "scale", Vector3(full / float(d["w"]), 1, 1), 0.3)
	d["p"] = c
	d["w"] = full
	main.fx.play("pop", c, -6.0)


func _strips() -> void:
	var now: float = main.clock
	for d in strips.duplicate():
		if now - float(d["born"]) > float(d.get("life", SPIKE_LIFE)) or (d["p"] as Vector3).distance_to(main.player.global_position) > 320.0:
			(d["node"] as Node).queue_free()
			strips.erase(d)
			continue
		var p: Vector3 = d["p"]
		var dirv: Vector3 = d["dir"]
		var right: Vector3 = d["right"]
		var half: float = float(d["w"]) * 0.5 + 0.8
		for c in main._all_cars():
			if c.dead or c.is_block:
				continue
			var rel: Vector3 = c.global_position - p
			if absf(rel.dot(dirv)) > 1.6 or absf(rel.dot(right)) > half or c.global_position.y > 2.0:
				continue
			var id: int = c.get_instance_id()
			if d["hit"].has(id):
				continue
			d["hit"][id] = true
			main.fx.play("pop", c.global_position, 2.0)
			main.fx.sparks(c.global_position, 18)
			if c.is_player:
				if shielded():
					continue
				c.flat_until = now + 9.0
				main.log_event("spike_hit")
				main.hud.banner("FLAT TYRES!")
			else:
				c.flat_until = now + 60.0
				c.apply_torque_impulse(Vector3.UP * (1.0 if randf() < 0.5 else -1.0) * c.mass * 2.2)
				main.stats["spike_cops"] = int(main.stats.get("spike_cops", 0)) + 1
				main.log_event("spike_cop")
				add_combo(150, "SPIKED")


# Normal play: from two stars, the police lay a strip on the road ahead now and then.
func _lay_spikes(dt: float) -> void:
	if main.level < 2 or main.game_over:
		return
	spike_t -= dt
	if spike_t > 0.0:
		return
	spike_t = randf_range(22.0, 32.0)
	var pl: Car = main.player
	var v := Vector3(pl.linear_velocity.x, 0, pl.linear_velocity.z)
	if v.length() < 8.0:
		return
	var r: Dictionary = world.road_spawn(pl.global_position + v.normalized() * 150.0, 0.0, 8.0)
	var yaw: float = r["yaw"]
	var dirv := Vector3(-sin(yaw), 0, -cos(yaw))
	if dirv.dot(v) < 0.0:
		dirv = -dirv
	drop_spikes(r["center"], dirv, 9.5, 2.25 if randf() < 0.5 else -2.25)


# ------------------------------------------------------------ tools: EMP and oil

func use_tool() -> bool:
	match tool:
		"emp":
			tool = ""
			emp()
			return true
		"oil":
			tool = ""
			drop_oil()
			return true
	return false


func emp() -> int:
	var pl: Car = main.player
	var c := pl.global_position
	var n := 0
	for cop in main._all_cars():
		if cop.is_player or cop.dead:
			continue
		if cop.global_position.distance_to(c) < EMP_R:
			cop.stall_until = main.clock + 4.5
			main.fx.sparks(cop.global_position + Vector3(0, 1.2, 0), 24)
			n += 1
	# the ring: a glowing shell that grows and fades
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 0.6
	sm.radial_segments = 32
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.45, 0.6, 1.0, 0.6)
	mi.material_override = m
	mi.position = c + Vector3(0, 0.5, 0)
	add_child(mi)
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.5, 0.65, 1.0)
	fl.light_energy = 8.0
	fl.omni_range = 40.0
	mi.add_child(fl)
	rings.append({"node": mi, "mat": m, "light": fl, "t": 0.0})
	main.fx.play("zap", c, 4.0)
	main.hud.flash(0.3)
	main.shake_cam(0.5)
	main.stats["emp_hits"] = int(main.stats.get("emp_hits", 0)) + n
	main.log_event("emp")
	add_combo(100 + 120 * n, "EMP x%d" % n)
	return n


func drop_oil() -> void:
	var pl: Car = main.player
	var f := -pl.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var p := pl.global_position - f * 4.5
	p.y = 0.0
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.03)
	m.metallic = 0.9
	m.roughness = 0.05
	for i in 5:
		var cy := CylinderMesh.new()
		var r := OIL_R * (1.0 if i == 0 else randf_range(0.3, 0.55))
		cy.top_radius = r
		cy.bottom_radius = r
		cy.height = 0.02
		cy.radial_segments = 20
		var mi := MeshInstance3D.new()
		mi.mesh = cy
		mi.material_override = m
		mi.position = Vector3(0, 0.03, 0) if i == 0 else Vector3(randf_range(-3, 3), 0.031, randf_range(-3, 3))
		root.add_child(mi)
	root.scale = Vector3(0.1, 1, 0.1)
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.5)
	slicks.append({"p": p, "node": root, "born": main.clock, "hit": {}})
	main.fx.play("spray", p, -2.0)
	main.log_event("oil")


func _slicks() -> void:
	var now: float = main.clock
	for d in slicks.duplicate():
		if now - float(d["born"]) > OIL_LIFE:
			(d["node"] as Node).queue_free()
			slicks.erase(d)
			continue
		var p: Vector3 = d["p"]
		for c in main._all_cars():
			if c.dead or c.is_block or c.speed < 6.0:
				continue
			if c.is_player and now - float(d["born"]) < 3.0:
				continue
			var q: Vector3 = c.global_position
			if Vector2(q.x - p.x, q.z - p.z).length() > OIL_R:
				continue
			var id: int = c.get_instance_id()
			if d["hit"].has(id):
				continue
			d["hit"][id] = true
			c.slip_until = now + 1.8
			var sgn := 1.0 if randf() < 0.5 else -1.0
			c.apply_torque_impulse(Vector3.UP * sgn * c.mass * (3.2 if not c.is_player else 1.2))
			if not c.is_player:
				main.stats["oil_spins"] = int(main.stats.get("oil_spins", 0)) + 1
				main.log_event("oil_spin")
				add_combo(150, "SPIN OUT")


# ------------------------------------------------------------ shield, pickups, combo

func shielded() -> bool:
	return main.clock < shield_until


func give_shield() -> void:
	shield_until = main.clock + SHIELD_TIME
	if shield_node == null:
		shield_node = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 12
		shield_node.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.3, 1.0, 0.95, 0.22)
		shield_node.material_override = m
		shield_node.scale = Vector3(1.7, 1.25, 3.0)
		shield_node.position = Vector3(0, 0.75, 0)
		main.player.add_child(shield_node)
	shield_node.visible = true
	main.fx.play("shield", main.player.global_position, 3.0)
	main.log_event("shield")
	main.hud.banner("SHIELD!")


func on_pickup(k: String, pos: Vector3) -> void:
	if story:
		return
	match k:
		"cash":
			cash += 1
			main.stats["cash"] = int(main.stats.get("cash", 0)) + 1
			main.fx.play("coin", pos, 2.0)
			main.log_event("cash")
			add_combo(250, "CASH")
		"emp", "oil":
			tool = k
			main.fx.play("coin", pos, -2.0)
			main.log_event("got_" + k)
			main.hud.banner("EMP READY" if k == "emp" else "OIL SLICK READY")
		"shield":
			give_shield()


func add_combo(points: int, label: String) -> void:
	main.bonus += points * combo
	if main.director == null and label != "":
		main.hud.banner("%s +%d%s" % [label, points * combo, ("   x%d" % combo) if combo > 1 else ""])
	combo = mini(combo + 1, COMBO_MAX)
	combo_best = maxi(combo_best, combo)
	combo_t = COMBO_TIME


func _physics_process(dt: float) -> void:
	if main.player == null:
		return
	var now: float = main.clock
	var pl: Car = main.player
	if combo_t > 0.0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 1
	for b in booths:
		if now < float(b["cd"]) or escaped or story:
			continue
		var rel: Vector3 = pl.global_position - (b["p"] as Vector3)
		if absf(rel.z) < 4.5 and absf(rel.x) < 2.6 and pl.global_position.y < 3.0:
			_respray(b)
	for cop in lost.keys():
		if not is_instance_valid(cop) or cop.dead:
			lost.erase(cop)
		elif now >= float(lost[cop]):
			lost.erase(cop)
			if main.level > 0 and not escaped:
				cop.target = pl
	_houses(dt)
	_strips()
	_slicks()
	if auto_spikes and main.director == null:
		_lay_spikes(dt)
	# shield: police bounce off it
	if shield_node != null:
		var on := shielded()
		shield_node.visible = on
		if on:
			var left := shield_until - now
			(shield_node.material_override as StandardMaterial3D).albedo_color.a = 0.22 if left > 1.5 or fmod(now * 8.0, 1.0) < 0.5 else 0.05
			for c in main._all_cars():
				if c.is_player or c.dead:
					continue
				var away: Vector3 = c.global_position - pl.global_position
				away.y = 0.0
				if away.length() < 4.6:
					c.apply_central_impulse((away.normalized() * 6.0 + Vector3(0, 1.5, 0)) * c.mass * dt * 8.0)
					if c.is_block:
						c.is_block = false
	# the EMP ring grows and fades
	for r in rings.duplicate():
		r["t"] = float(r["t"]) + dt
		var t: float = r["t"]
		var mi: MeshInstance3D = r["node"]
		var s := lerpf(1.0, EMP_R, clampf(t / 0.6, 0.0, 1.0))
		mi.scale = Vector3(s, s * 0.35, s)
		(r["mat"] as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - clampf(t / 0.9, 0.0, 1.0))
		(r["light"] as OmniLight3D).light_energy = 8.0 * (1.0 - clampf(t / 0.5, 0.0, 1.0))
		if t > 0.95:
			mi.queue_free()
			rings.erase(r)
	# sparks off the rims of a car on flat tyres
	flat_spark_t -= dt
	if flat_spark_t <= 0.0:
		flat_spark_t = 0.12
		for c in main._all_cars():
			if not c.dead and now < c.flat_until and c.speed > 4.0 and c.global_position.distance_to(pl.global_position) < 90.0:
				main.fx.sparks(c.global_position + Vector3(0, 0.3, 0), 4)
