class_name Props
extends Node3D
# Street life and things that go boom: trees, street lamps, barrels, parked cars,
# gas stations, pickups and rooftop props. Data is generated once; nodes are
# created per block while it is loaded.

var world
var main
var rng := RandomNumberGenerator.new()
var block_props := {}      # Vector2i -> Array[Dictionary]
var block_mm := {}         # Vector2i -> Dictionary of MultiMesh
var block_nodes := {}      # Vector2i -> Array[Node]
var loaded := {}

var trunk_mesh: CylinderMesh
var canopy_mesh: SphereMesh
var pole_mesh: CylinderMesh
var arm_mesh: BoxMesh
var head_mesh: BoxMesh
var barrel_mesh: CylinderMesh
var lamp_mat: StandardMaterial3D
var glow_mats: Array[StandardMaterial3D] = []
var night := 0.0
var spin_t := 0.0


func setup(w) -> void:
	world = w
	main = w.main
	rng.seed = 4242
	trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.24
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk_mesh.material = _mat(Color(0.33, 0.24, 0.16))
	canopy_mesh = SphereMesh.new()
	canopy_mesh.radius = 1.7
	canopy_mesh.height = 3.0
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 5
	var cm := _mat(Color.WHITE)
	cm.vertex_color_use_as_albedo = true
	canopy_mesh.material = cm
	pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 6.5
	pole_mesh.radial_segments = 6
	pole_mesh.rings = 1
	pole_mesh.material = _mat(Color(0.25, 0.27, 0.3))
	arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(0.1, 0.1, 1.8)
	arm_mesh.material = pole_mesh.material
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.9, 0.7)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.55)
	lamp_mat.emission_energy_multiplier = 0.2
	head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.14, 0.7)
	head_mesh.material = lamp_mat
	barrel_mesh = CylinderMesh.new()
	barrel_mesh.top_radius = 0.33
	barrel_mesh.bottom_radius = 0.33
	barrel_mesh.height = 0.95
	barrel_mesh.radial_segments = 10
	barrel_mesh.rings = 1
	var bm := _mat(Color(0.75, 0.12, 0.08))
	bm.metallic = 0.4
	barrel_mesh.material = bm
	for c in [Color(1.0, 0.25, 0.3), Color(0.2, 0.7, 1.0), Color(1.0, 0.75, 0.15), Color(0.4, 1.0, 0.5), Color(0.85, 0.35, 1.0)]:
		var g := StandardMaterial3D.new()
		g.albedo_color = c
		g.emission_enabled = true
		g.emission = c
		g.emission_energy_multiplier = 0.4
		glow_mats.append(g)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _mesh_node(mesh: Mesh, pos: Vector3, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh_node(bm, pos, mat)


func set_night(v: float) -> void:
	night = v
	lamp_mat.emission_energy_multiplier = 0.2 + v * 3.5
	for g in glow_mats:
		g.emission_energy_multiplier = 0.4 + v * 2.2


# ------------------------------------------------------------ generation

func _add(key: Vector2i, d: Dictionary) -> void:
	d["alive"] = true
	block_props[key].append(d)


func generate_block(key: Vector2i, kind: String) -> void:
	block_props[key] = []
	var xa: float = world.line(key.x)
	var xb: float = world.line(key.x + 1)
	var za: float = world.line(key.y)
	var zb: float = world.line(key.y + 1)
	var tree_p := {"sub": 0.5, "mid": 0.3, "down": 0.18, "ind": 0.1, "park": 0.7, "gas": 0.3}.get(kind, 0.3) as float
	# four sidewalks: [fixed coord, along axis is z?, road side sign]
	var sides := [[xa + 8.3, true, -1.0], [xb - 8.3, true, 1.0], [za + 8.3, false, -1.0], [zb - 8.3, false, 1.0]]
	for s in sides:
		var fixed: float = s[0]
		var along_z: bool = s[1]
		var sgn: float = s[2]
		var a0 := (za if along_z else xa) + 14.0
		var a1 := (zb if along_z else xb) - 14.0
		var k := 0
		var t := a0
		while t <= a1:
			var p := Vector3(fixed, 0, t) if along_z else Vector3(t, 0, fixed)
			if k % 2 == 0 and rng.randf() < 0.6:
				var yaw := (PI * 0.5 if sgn < 0.0 else -PI * 0.5) if along_z else (0.0 if sgn < 0.0 else PI)
				_add(key, {"t": "lamp", "p": p, "yaw": yaw})
			elif rng.randf() < tree_p:
				_add(key, {"t": "tree", "p": p, "yaw": rng.randf() * TAU, "s": rng.randf_range(0.8, 1.25), "c": rng.randf()})
			t += 12.0
			k += 1
		if rng.randf() < 0.4:
			var pt := rng.randf_range(a0, a1)
			var off := fixed + sgn * 2.7
			var pp := Vector3(off, 0, pt) if along_z else Vector3(pt, 0, off)
			var yy := (0.0 if rng.randf() < 0.5 else PI) if along_z else (PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5)
			_add(key, {"t": "parked", "p": pp, "yaw": yy, "c": rng.randi() % 8})
	if rng.randf() < 0.28:
		var s2: Array = sides[rng.randi() % 4]
		var tt := rng.randf_range(-15.0, 15.0) + ((za + zb) * 0.5 if s2[1] else (xa + xb) * 0.5)
		var bp := Vector3(s2[0], 0, tt) if s2[1] else Vector3(tt, 0, s2[0])
		_add(key, {"t": "barrel", "p": bp})
	if rng.randf() < 0.2:
		var lane := 3.5 if rng.randf() < 0.5 else -3.5
		_add(key, {"t": "pickup", "p": Vector3((xa + xb) * 0.5, 0, za + lane), "k": "repair" if rng.randf() < 0.6 else "nitro"})
	if kind == "park":
		for i in 14:
			_add(key, {"t": "tree", "p": Vector3(rng.randf_range(xa + 12, xb - 12), 0, rng.randf_range(za + 12, zb - 12)), "yaw": rng.randf() * TAU, "s": rng.randf_range(0.9, 1.5), "c": rng.randf()})


func gas_station(key: Vector2i, c: Vector3) -> void:
	_add(key, {"t": "gas", "p": c})


# ------------------------------------------------------------ streaming

func load_block(key: Vector2i, parent: Node3D) -> void:
	if not block_props.has(key):
		return
	var list: Array = block_props[key]
	var nodes: Array = []
	var trees := []
	var lamps := []
	for d: Dictionary in list:
		if not d["alive"]:
			continue
		match d["t"]:
			"tree":
				trees.append(d)
			"lamp":
				lamps.append(d)
			"barrel":
				nodes.append(_barrel_node(d, parent))
			"parked":
				var cc := CivCar.new()
				parent.add_child(cc)
				cc.build(main, CivCar.palette(d["c"]), false)
				cc.global_transform = Transform3D(Basis(Vector3.UP, d["yaw"]), d["p"])
				cc.prop_ref = d
				d["node"] = cc
				nodes.append(cc)
			"pickup":
				var pn := _pickup_node(d["k"])
				pn.position = d["p"] + Vector3(0, 1.0, 0)
				parent.add_child(pn)
				d["node"] = pn
				nodes.append(pn)
				pn.visible = main.clock >= float(d.get("respawn", 0.0))
			"gas":
				var g := _gas_node(d)
				parent.add_child(g)
				nodes.append(g)
	var mms := {}
	if trees.size() > 0:
		mms["trunk"] = _mm(parent, trunk_mesh, trees.size(), false)
		mms["canopy"] = _mm(parent, canopy_mesh, trees.size(), true)
		for i in trees.size():
			var d: Dictionary = trees[i]
			d["i"] = i
			var s: float = d["s"]
			var p: Vector3 = d["p"]
			(mms["trunk"] as MultiMesh).set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), p + Vector3(0, 1.5 * s, 0)))
			(mms["canopy"] as MultiMesh).set_instance_transform(i, Transform3D(Basis(Vector3.UP, d["yaw"]).scaled(Vector3(s, s * 1.1, s)), p + Vector3(0, 3.9 * s, 0)))
			var cv: float = d["c"]
			(mms["canopy"] as MultiMesh).set_instance_color(i, Color(0.2, 0.42, 0.18).lerp(Color(0.45, 0.55, 0.2), cv))
	if lamps.size() > 0:
		mms["pole"] = _mm(parent, pole_mesh, lamps.size(), false)
		mms["arm"] = _mm(parent, arm_mesh, lamps.size(), false)
		mms["head"] = _mm(parent, head_mesh, lamps.size(), false)
		for i in lamps.size():
			var d: Dictionary = lamps[i]
			d["i"] = i
			var p: Vector3 = d["p"]
			var b := Basis(Vector3.UP, d["yaw"])
			(mms["pole"] as MultiMesh).set_instance_transform(i, Transform3D(Basis.IDENTITY, p + Vector3(0, 3.25, 0)))
			(mms["arm"] as MultiMesh).set_instance_transform(i, Transform3D(b, p + Vector3(0, 6.4, 0) + b * Vector3(0, 0, -0.85)))
			(mms["head"] as MultiMesh).set_instance_transform(i, Transform3D(b, p + Vector3(0, 6.3, 0) + b * Vector3(0, 0, -1.6)))
	for k in mms:
		nodes.append(mms[k].get_meta("node"))
	block_mm[key] = mms
	block_nodes[key] = nodes
	loaded[key] = true


func _barrel_node(d: Dictionary, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	for o in [Vector3(0, 0.48, 0), Vector3(0.7, 0.48, 0.1), Vector3(0.3, 0.48, 0.65)]:
		n.add_child(_mesh_node(barrel_mesh, o))
	n.position = d["p"]
	parent.add_child(n)
	d["node"] = n
	return n


# Director only: drops a barrel cluster mid-game (a police trap) and returns its record.
func spawn_barrels(p: Vector3) -> Dictionary:
	var key: Vector2i = world.block_of(p)
	var d := {"t": "barrel", "p": Vector3(p.x, 0.0, p.z)}
	_add(key, d)
	if loaded.has(key):
		block_nodes[key].append(_barrel_node(d, world.chunk_root))
	return d


func detonate(d: Dictionary) -> void:
	_boom(d, 0.05)


# Gas stations still standing within r of p, for the bot to aim at.
func gas_stations_near(p: Vector3, r: float) -> Array:
	var out := []
	for key in block_props:
		var c := Vector3(world.line(key.x) + World.PITCH * 0.5, 0.0, world.line(key.y) + World.PITCH * 0.5)
		if c.distance_to(Vector3(p.x, 0.0, p.z)) > r + World.PITCH:
			continue
		for d: Dictionary in block_props[key]:
			if d["t"] == "gas" and d["alive"] and (d["p"] as Vector3).distance_to(p) < r:
				out.append(d)
	return out


func _mm(parent: Node3D, mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 190.0
	parent.add_child(mmi)
	mm.set_meta("node", mmi)
	return mm


func unload_block(key: Vector2i) -> void:
	if block_nodes.has(key):
		for n in block_nodes[key]:
			if is_instance_valid(n):
				n.queue_free()
	block_nodes.erase(key)
	block_mm.erase(key)
	loaded.erase(key)
	if block_props.has(key):
		for d: Dictionary in block_props[key]:
			d.erase("node")


func _pickup_node(k: String) -> Node3D:
	var n := Node3D.new()
	var g: StandardMaterial3D = glow_mats[3] if k == "repair" else glow_mats[1]
	if k == "repair":
		n.add_child(_box(Vector3(1.1, 0.32, 0.32), Vector3.ZERO, g))
		n.add_child(_box(Vector3(0.32, 1.1, 0.32), Vector3.ZERO, g))
	else:
		var cy := CylinderMesh.new()
		cy.top_radius = 0.3
		cy.bottom_radius = 0.3
		cy.height = 1.1
		n.add_child(_mesh_node(cy, Vector3.ZERO, g))
		n.add_child(_box(Vector3(0.22, 0.25, 0.22), Vector3(0, 0.66, 0), g))
	var l := OmniLight3D.new()
	l.light_color = g.albedo_color
	l.omni_range = 5.0
	l.light_energy = 1.2
	n.add_child(l)
	n.add_to_group("pickup")
	return n


func _gas_node(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	var c: Vector3 = d["p"]
	root.position = c
	var white := _mat(Color(0.92, 0.92, 0.9))
	var red: StandardMaterial3D = glow_mats[0]
	var pad := _box(Vector3(22, 0.04, 18), Vector3(0, 0.02, 0), _mat(Color(0.2, 0.2, 0.22)))
	root.add_child(pad)
	var canopy := RigidBody3D.new()
	canopy.mass = 2500.0
	canopy.freeze = true
	canopy.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	canopy.collision_layer = 1
	canopy.collision_mask = 1 | 2 | 4
	for part in [[Vector3(11, 0.6, 8), Vector3(0, 5.0, 0), white], [Vector3(11.1, 0.35, 8.1), Vector3(0, 4.6, 0), red]]:
		canopy.add_child(_box(part[0], part[1], part[2]))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(11, 1.0, 8)
	cs.shape = bs
	cs.position = Vector3(0, 4.9, 0)
	canopy.add_child(cs)
	for px in [-4.5, 4.5]:
		for pz in [-3.0, 3.0]:
			canopy.add_child(_box(Vector3(0.4, 4.4, 0.4), Vector3(px, 2.2, pz), white))
			var pc := CollisionShape3D.new()
			var pb := BoxShape3D.new()
			pb.size = Vector3(0.4, 4.4, 0.4)
			pc.shape = pb
			pc.position = Vector3(px, 2.2, pz)
			canopy.add_child(pc)
	root.add_child(canopy)
	var pumps := []
	for px in [-2.2, 2.2]:
		var pump := StaticBody3D.new()
		pump.collision_layer = 1
		pump.add_child(_box(Vector3(0.8, 1.7, 0.6), Vector3(0, 0.85, 0), red))
		pump.add_child(_box(Vector3(0.82, 0.4, 0.62), Vector3(0, 1.45, 0), white))
		var ps := CollisionShape3D.new()
		var pbs := BoxShape3D.new()
		pbs.size = Vector3(0.8, 1.7, 0.6)
		ps.shape = pbs
		ps.position = Vector3(0, 0.85, 0)
		pump.add_child(ps)
		pump.position = Vector3(px, 0, 0)
		root.add_child(pump)
		pumps.append(pump)
	var sign_post := _box(Vector3(0.3, 8.0, 0.3), Vector3(7.0, 4.0, -3.5), white)
	root.add_child(sign_post)
	root.add_child(_box(Vector3(2.4, 2.0, 0.3), Vector3(7.0, 8.6, -3.5), red))
	d["node"] = root
	d["canopy"] = canopy
	d["pumps"] = pumps
	return root


func make_roof_prop(kind: String, sd: int) -> Node3D:
	var n := Node3D.new()
	var r := RandomNumberGenerator.new()
	r.seed = sd
	match kind:
		"tank":
			var wood := _mat(Color(0.45, 0.33, 0.22))
			var cy := CylinderMesh.new()
			cy.top_radius = 0.95
			cy.bottom_radius = 0.95
			cy.height = 1.7
			cy.radial_segments = 10
			cy.material = wood
			n.add_child(_mesh_node(cy, Vector3(0, 2.1, 0)))
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 1.0
			cone.height = 0.6
			cone.radial_segments = 10
			cone.material = wood
			n.add_child(_mesh_node(cone, Vector3(0, 3.25, 0)))
			var leg := _mat(Color(0.2, 0.2, 0.22))
			for lx in [-0.6, 0.6]:
				for lz in [-0.6, 0.6]:
					n.add_child(_box(Vector3(0.12, 1.25, 0.12), Vector3(lx, 0.62, lz), leg))
		"ac":
			var grey := _mat(Color(0.62, 0.64, 0.66))
			n.add_child(_box(Vector3(1.4, 0.9, 1.1), Vector3(0, 0.45, 0), grey))
			n.add_child(_box(Vector3(0.9, 0.05, 0.9), Vector3(0, 0.93, 0), _mat(Color(0.15, 0.15, 0.16))))
		"antenna":
			var pole := CylinderMesh.new()
			pole.top_radius = 0.04
			pole.bottom_radius = 0.1
			pole.height = 6.0
			pole.radial_segments = 6
			pole.material = _mat(Color(0.7, 0.7, 0.72))
			n.add_child(_mesh_node(pole, Vector3(0, 3.0, 0)))
			n.add_child(_box(Vector3(0.25, 0.25, 0.25), Vector3(0, 6.1, 0), glow_mats[0]))
		_:
			var dark := _mat(Color(0.12, 0.12, 0.14))
			n.add_child(_box(Vector3(0.2, 3.0, 0.2), Vector3(-2.2, 1.5, 0), dark))
			n.add_child(_box(Vector3(0.2, 3.0, 0.2), Vector3(2.2, 1.5, 0), dark))
			n.add_child(_box(Vector3(6.2, 2.6, 0.25), Vector3(0, 4.2, 0), dark))
			n.add_child(_box(Vector3(5.8, 2.2, 0.1), Vector3(0, 4.2, -0.15), glow_mats[r.randi() % glow_mats.size()]))
			n.add_child(_box(Vector3(5.8, 0.35, 0.12), Vector3(0, 3.6, -0.17), glow_mats[r.randi() % glow_mats.size()]))
			n.rotation.y = r.randf() * TAU
	n.set_meta("vr", true)
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).visibility_range_end = 260.0
	return n


func drop_roof_prop(n: Node3D) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 150.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 1.6, 1.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.8, 0)
	rb.add_child(cs)
	world.debris_root.add_child(rb)
	rb.global_transform = n.global_transform
	n.reparent(rb, true)
	rb.linear_velocity = Vector3(randf_range(-3, 3), randf_range(1, 4), randf_range(-3, 3))
	rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	main.get_tree().create_timer(9.0).timeout.connect(rb.queue_free)


# ------------------------------------------------------------ interaction

func _break(key: Vector2i, d: Dictionary, push: Vector3) -> void:
	d["alive"] = false
	var mms: Dictionary = block_mm.get(key, {})
	var i: int = d.get("i", -1)
	var hide := Transform3D(Basis().scaled(Vector3.ZERO), d["p"])
	var rb := RigidBody3D.new()
	rb.mass = 60.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	if d["t"] == "tree":
		var s: float = d["s"]
		bs.size = Vector3(1.2, 5.0, 1.2) * s
		cs.position = Vector3(0, 2.5 * s, 0)
		var trunk := _mesh_node(trunk_mesh, Vector3(0, 1.5 * s, 0))
		trunk.scale = Vector3.ONE * s
		rb.add_child(trunk)
		var can := _mesh_node(canopy_mesh, Vector3(0, 3.9 * s, 0), _mat(Color(0.22, 0.45, 0.2)))
		can.scale = Vector3(s, s * 1.1, s)
		rb.add_child(can)
		if i >= 0 and mms.has("trunk"):
			(mms["trunk"] as MultiMesh).set_instance_transform(i, hide)
			(mms["canopy"] as MultiMesh).set_instance_transform(i, hide)
	else:
		bs.size = Vector3(0.4, 6.5, 0.4)
		cs.position = Vector3(0, 3.25, 0)
		rb.add_child(_mesh_node(pole_mesh, Vector3(0, 3.25, 0)))
		rb.add_child(_mesh_node(head_mesh, Vector3(0, 6.3, -0.8)))
		if i >= 0 and mms.has("pole"):
			(mms["pole"] as MultiMesh).set_instance_transform(i, hide)
			(mms["arm"] as MultiMesh).set_instance_transform(i, hide)
			(mms["head"] as MultiMesh).set_instance_transform(i, hide)
	cs.shape = bs
	rb.add_child(cs)
	world.debris_root.add_child(rb)
	rb.global_transform = Transform3D(Basis.IDENTITY, d["p"])
	rb.linear_velocity = push + Vector3(0, 3, 0)
	rb.angular_velocity = Vector3(push.z, 0, -push.x).normalized() * 3.0
	main.get_tree().create_timer(8.0).timeout.connect(rb.queue_free)
	main.on_prop_smash(d["p"])


func _boom(d: Dictionary, delay: float) -> void:
	if not d["alive"]:
		return
	d["alive"] = false
	var p: Vector3 = d["p"]
	var big: bool = d["t"] == "gas"
	main.get_tree().create_timer(delay).timeout.connect(func():
		if d.has("node") and is_instance_valid(d["node"]):
			if big:
				for pump in d["pumps"]:
					if is_instance_valid(pump):
						pump.queue_free()
				var can: RigidBody3D = d["canopy"]
				if is_instance_valid(can):
					can.freeze = false
					can.apply_central_impulse(Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1)) * can.mass * 2.5)
					can.apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * can.mass * 6.0)
			else:
				(d["node"] as Node).queue_free()
		if big:
			main.big_boom(p + Vector3(0, 1.5, 0), 15.0)
		elif d.get("trap", false):
			main.explode_at(p + Vector3(0, 0.8, 0), 9.0, 34.0, 70.0, true, 2.5)
		else:
			main.explode_at(p + Vector3(0, 0.8, 0), 6.5, 16.0, 35.0))


func _physics_process(delta: float) -> void:
	spin_t += delta
	var pl = main.player
	if pl == null:
		return
	var pp: Vector3 = pl.global_position
	var spd: float = pl.speed
	var bk: Vector2i = world.block_of(pp)
	var now: float = main.clock
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var key := Vector2i(bk.x + di, bk.y + dj)
			if not loaded.has(key):
				continue
			for d: Dictionary in block_props[key]:
				var t: String = d["t"]
				if t == "pickup":
					var n: Node3D = d.get("node")
					if n == null:
						continue
					if not n.visible:
						if now >= float(d.get("respawn", 0.0)):
							n.visible = true
						continue
					n.rotation.y = spin_t * 2.0
					if (d["p"] as Vector3).distance_to(pp) < 3.2:
						n.visible = false
						d["respawn"] = now + 40.0
						main.on_pickup(d["k"], d["p"])
					continue
				if not d["alive"]:
					continue
				var dist := (d["p"] as Vector3).distance_to(Vector3(pp.x, 0, pp.z))
				match t:
					"tree", "lamp":
						if dist < 2.0 and spd > 4.0:
							_break(key, d, pl.linear_velocity * 0.6)
							pl.linear_velocity *= 0.93
					"barrel":
						if dist < 2.6 and spd > 2.0:
							_boom(d, 0.05)
					"gas":
						if dist < 6.0 and spd > 5.0:
							_boom(d, 0.05)   # driving into the forecourt is enough
						elif dist < 7.0 and spd > 6.0:
							for pump in d.get("pumps", []):
								if is_instance_valid(pump) and (pump as Node3D).global_position.distance_to(pp) < 3.4:
									_boom(d, 0.05)
									break


# Explosion reaches props: trees and lamps fly, barrels and gas stations chain-react.
func blast(center: Vector3, radius: float) -> void:
	var bk: Vector2i = world.block_of(center)
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var key := Vector2i(bk.x + di, bk.y + dj)
			if not loaded.has(key):
				continue
			for d: Dictionary in block_props[key]:
				if not d["alive"]:
					continue
				var p: Vector3 = d["p"]
				var dist := p.distance_to(Vector3(center.x, 0, center.z))
				var t: String = d["t"]
				if dist > radius * 1.3:
					continue
				match t:
					"tree", "lamp":
						var dirv := (p - center)
						dirv.y = 0.0
						_break(key, d, dirv.normalized() * 14.0 * (1.0 - dist / (radius * 1.3)))
					"barrel":
						_boom(d, randf_range(0.12, 0.35))
					"gas":
						_boom(d, randf_range(0.15, 0.3))
