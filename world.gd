class_name World
extends Node3D
# The city: road grid, district generation, chunk streaming, ramps, flyovers,
# debris pool and the area-damage entry point used by cars and explosions.

const CELL := 2.0
const PITCH := 72.0
const ROAD_W := 14.0
const N := 16
const HALF := 576.0
const LOAD_R := 3
const MAX_DEBRIS := 80

var main
var fx
var facade_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var cube_mesh: ArrayMesh
var debris_mats: Array[ShaderMaterial] = []
var buildings: Array[Building] = []
var block_buildings := {}
var loaded_blocks := {}
var collapsing: Array[Building] = []
var debris_free: Array[RigidBody3D] = []
var debris_active: Array = []
var chunk_root: Node3D
var static_root: Node3D
var debris_root: Node3D
var last_block := Vector2i(-9999, -9999)
var load_queue: Array[Vector2i] = []
var rng := RandomNumberGenerator.new()
var ramp_points: Array[Vector3] = []
var ramps: Array[Dictionary] = []   # jump ramps: p0 (low end), p1 (high end), road k, block m, along_z, sgn
var total_cells := 0
var props: Props


# ------------------------------------------------------------ mesh helper

static func add_box(st: SurfaceTool, c: Vector3, size: Vector3, cells: Vector3, color: Color) -> void:
	var half := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var eu := absf(u.dot(half))
		var ev := absf(v.dot(half))
		var cu := absf(u.dot(cells))
		var cv := absf(v.dot(cells))
		var corners := [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for cc in corners:
			pts.append(c + n * absf(n.dot(half)) + u * (cc.x * eu) + v * (cc.y * ev))
			uvs.append(Vector2((cc.x + 1.0) * 0.5 * cu, (cc.y + 1.0) * 0.5 * cv))
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.set_color(color)
			st.add_vertex(pts[k])


static func make_box(size: Vector3, cells: Vector3, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_box(st, Vector3.ZERO, size, cells, color)
	return st.commit()


# ------------------------------------------------------------ setup

func setup(main_node, fx_node) -> void:
	main = main_node
	fx = fx_node
	rng.seed = 20261027
	chunk_root = Node3D.new()
	static_root = Node3D.new()
	debris_root = Node3D.new()
	add_child(chunk_root)
	add_child(static_root)
	add_child(debris_root)

	facade_mat = ShaderMaterial.new()
	var fs := Shader.new()
	fs.code = Shaders.FACADE
	facade_mat.shader = fs
	ground_mat = ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = Shaders.GROUND
	ground_mat.shader = gs
	cube_mesh = make_box(Vector3.ONE * CELL, Vector3.ONE, Color.WHITE)

	var ds := Shader.new()
	ds.code = Shaders.DEBRIS
	for c in [Color("b9a98f"), Color("9aa6b2"), Color("c2b8a8"), Color("8f9aa8"), Color("a89484"), Color("b5b0a6")]:
		var m := ShaderMaterial.new()
		m.shader = ds
		m.set_shader_parameter("tint", c)
		debris_mats.append(m)

	props = Props.new()
	add_child(props)
	props.setup(self)
	_make_ground()
	_generate_city()
	_make_jump_ramps()
	_make_flyover(4, 5)
	_make_flyover(11, 10)
	_make_debris_pool()


func set_night(v: float, wet: float) -> void:
	facade_mat.set_shader_parameter("night", v)
	props.set_night(v)
	ground_mat.set_shader_parameter("night", v)
	ground_mat.set_shader_parameter("wet", wet)


func _static_box(size: Vector3, xf: Transform3D, color: Color, parent: Node3D = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	bm.material = m
	mi.mesh = bm
	b.add_child(mi)
	b.transform = xf
	(parent if parent != null else static_root).add_child(b)
	return b


func _slab(from: Vector3, to: Vector3, width: float, thick: float, color: Color) -> void:
	var dir := (to - from).normalized()
	var basis := Basis.looking_at(dir, Vector3.UP)
	var center := (from + to) * 0.5 - basis.y * (thick * 0.5)
	_static_box(Vector3(width, thick, from.distance_to(to)), Transform3D(basis, center), color)


func _make_ground() -> void:
	var size := HALF * 2.0 + 200.0
	var g := StaticBody3D.new()
	g.collision_layer = 1
	g.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 2.0, size)
	cs.shape = bs
	cs.position = Vector3(0, -1.0, 0)
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.material_override = ground_mat
	g.add_child(mi)
	static_root.add_child(g)
	var wc := Color(0.4, 0.42, 0.46)
	var e := HALF + 12.0
	_static_box(Vector3(e * 2 + 4, 6, 2), Transform3D(Basis.IDENTITY, Vector3(0, 3, -e)), wc)
	_static_box(Vector3(e * 2 + 4, 6, 2), Transform3D(Basis.IDENTITY, Vector3(0, 3, e)), wc)
	_static_box(Vector3(2, 6, e * 2 + 4), Transform3D(Basis.IDENTITY, Vector3(-e, 3, 0)), wc)
	_static_box(Vector3(2, 6, e * 2 + 4), Transform3D(Basis.IDENTITY, Vector3(e, 3, 0)), wc)


func line(k: int) -> float:
	return -HALF + k * PITCH


# ------------------------------------------------------------ city generation

func _generate_city() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.09
	for bi in N:
		for bj in N:
			var key := Vector2i(bi, bj)
			var list: Array[Building] = []
			block_buildings[key] = list
			var cx := line(bi) + PITCH * 0.5
			var cz := line(bj) + PITCH * 0.5
			var dn := Vector2(cx, cz).length() / HALF
			var nv := noise.get_noise_2d(bi, bj) * 0.5 + 0.5
			var kind := "mid"
			if dn < 0.33:
				kind = "down"
			elif dn < 0.62:
				kind = "mid"
			else:
				kind = "sub"
			if dn > 0.3 and nv > 0.82:
				kind = "park"
			elif dn > 0.35 and nv < 0.2:
				kind = "ind"
			props.generate_block(key, kind)
			_fill_block(key, list, line(bi) + 10.0, line(bj) + 10.0, kind)
	for b in buildings:
		total_cells += b.total_alive()


func _fill_block(key: Vector2i, list: Array[Building], x0: float, z0: float, kind: String) -> void:
	if kind == "park":
		return
	var lots := 2
	if kind == "sub":
		lots = 3
	if kind == "ind":
		lots = 1
	var lot_cells := 26 / lots
	var gas_lot := Vector2i(-1, -1)
	if kind == "mid" and rng.randf() < 0.22:
		gas_lot = Vector2i(rng.randi_range(0, 1), rng.randi_range(0, 1))
	for a in lots:
		for b in lots:
			if Vector2i(a, b) == gas_lot:
				props.gas_station(key, Vector3(x0 + (a + 0.5) * lot_cells * CELL, 0, z0 + (b + 0.5) * lot_cells * CELL))
				continue
			if kind == "sub" and rng.randf() < 0.3:
				continue
			if kind == "mid" and rng.randf() < 0.12:
				continue
			var w := 5
			var d := 5
			var h := 4
			var tint := Color.WHITE
			var style := 0.5
			match kind:
				"down":
					w = rng.randi_range(7, 10)
					d = rng.randi_range(7, 10)
					h = rng.randi_range(10, 18)
					if rng.randf() < 0.55:
						style = 0.85
						tint = [Color(0.42, 0.55, 0.66), Color(0.38, 0.5, 0.52), Color(0.55, 0.6, 0.68), Color(0.3, 0.38, 0.5)][rng.randi() % 4]
					else:
						tint = Color(0.62, 0.62, 0.6).lerp(Color(0.78, 0.74, 0.66), rng.randf())
				"mid":
					w = rng.randi_range(6, 11)
					d = rng.randi_range(6, 11)
					h = rng.randi_range(4, 9)
					if rng.randf() < 0.55:
						style = 0.15
						tint = Color(0.62, 0.34, 0.26).lerp(Color(0.74, 0.52, 0.38), rng.randf())
					else:
						tint = Color(0.7, 0.66, 0.58).lerp(Color(0.85, 0.8, 0.7), rng.randf())
				"sub":
					w = rng.randi_range(4, 6)
					d = rng.randi_range(4, 6)
					h = rng.randi_range(2, 3)
					style = 0.15 if rng.randf() < 0.5 else 0.5
					tint = [Color(0.85, 0.78, 0.62), Color(0.62, 0.74, 0.7), Color(0.78, 0.62, 0.6), Color(0.72, 0.72, 0.82)][rng.randi() % 4]
				_:
					w = rng.randi_range(16, 22)
					d = rng.randi_range(10, 14)
					h = rng.randi_range(3, 4)
					tint = Color(0.52, 0.52, 0.54).lerp(Color(0.62, 0.45, 0.38), rng.randf() * 0.6)
			w = mini(w, lot_cells - 1)
			d = mini(d, lot_cells - 1)
			while w * d * h > 1500:
				h -= 1
			var hs := _shape_heights(kind, w, d, h)
			var ox := x0 + (a * lot_cells + rng.randi_range(0, lot_cells - w)) * CELL
			var oz := z0 + (b * lot_cells + rng.randi_range(0, lot_cells - d)) * CELL
			var bld := Building.new()
			bld.setup(self, Vector3(ox, 0.0, oz), w, d, hs, tint, style)
			_roof_defs(bld, kind)
			buildings.append(bld)
			list.append(bld)


func _shape_heights(kind: String, w: int, d: int, h: int) -> PackedInt32Array:
	var hs := PackedInt32Array()
	hs.resize(w * d)
	hs.fill(h)
	var r := rng.randf()
	if kind == "down" and r < 0.75:
		var base := maxi(3, int(h * rng.randf_range(0.35, 0.55)))
		var mid := maxi(base + 1, int(h * 0.78))
		for z in d:
			for x in w:
				var edge := mini(mini(x, w - 1 - x), mini(z, d - 1 - z))
				var v := base
				if edge >= 2:
					v = h
				elif edge >= 1:
					v = mid
				hs[x + z * w] = v
	elif kind == "mid" and r < 0.45:
		var low := 0 if rng.randf() < 0.4 else maxi(2, h / 2)
		var qx := w / 2
		var qz := d / 2
		var fx := rng.randf() < 0.5
		var fz := rng.randf() < 0.5
		for z in d:
			for x in w:
				var inx := (x >= qx) if fx else (x < qx)
				var inz := (z >= qz) if fz else (z < qz)
				if inx and inz:
					hs[x + z * w] = low
	elif kind == "ind" and r < 0.6:
		hs[0] = h + rng.randi_range(5, 8)
	return hs


func _roof_defs(b: Building, kind: String) -> void:
	if b.ny < 3:
		return
	var tops := []
	for z in b.nz:
		for x in b.nx:
			if b.init_h[x + z * b.nx] == b.ny and x > 0 and z > 0 and x < b.nx - 1 and z < b.nz - 1:
				tops.append(Vector2i(x, z))
	if tops.is_empty():
		return
	var n := rng.randi_range(1, 3)
	for i in n:
		var c: Vector2i = tops[rng.randi() % tops.size()]
		var k: String = ["tank", "ac", "ac", "antenna"][rng.randi() % 4]
		if kind != "sub" and rng.randf() < 0.3 and i == 0:
			k = "billboard"
		b.roof_defs.append([k, c.x, c.y, rng.randi()])


# ------------------------------------------------------------ ramps and flyovers

func _make_jump_ramps() -> void:
	var yellow := Color(0.85, 0.65, 0.12)
	for i in 14:
		var k := rng.randi_range(2, N - 2)
		var m := rng.randi_range(1, N - 2)
		var along_z := rng.randf() < 0.5
		var lane := (3.5 if rng.randf() < 0.5 else -3.5)
		var sgn := (1.0 if rng.randf() < 0.5 else -1.0)
		var mid := line(m) + PITCH * 0.5
		var p0: Vector3
		var p1: Vector3
		if along_z:
			p0 = Vector3(line(k) + lane, 0.05, mid - 6.0 * sgn)
			p1 = Vector3(line(k) + lane, 2.3, mid + 6.0 * sgn)
		else:
			p0 = Vector3(mid - 6.0 * sgn, 0.05, line(k) + lane)
			p1 = Vector3(mid + 6.0 * sgn, 2.3, line(k) + lane)
		_slab(p0, p1, 5.0, 0.35, yellow)
		ramp_points.append((p0 + p1) * 0.5)
		ramps.append({"p0": p0, "p1": p1, "k": k, "m": m, "along_z": along_z, "sgn": sgn})


func _make_flyover(kx: int, jz: int) -> void:
	var x := line(kx)
	var zc := line(jz)
	var hd := 6.5
	var lh := 46.0
	var conc := Color(0.55, 0.55, 0.57)
	_slab(Vector3(x, hd, zc - 36.0), Vector3(x, hd, zc + 36.0), 8.0, 1.2, conc)
	_slab(Vector3(x, 0.05, zc - 36.0 - lh), Vector3(x, hd, zc - 36.0), 8.0, 1.2, conc)
	_slab(Vector3(x, 0.05, zc + 36.0 + lh), Vector3(x, hd, zc + 36.0), 8.0, 1.2, conc)
	for s in [-1.0, 1.0]:
		_static_box(Vector3(0.5, 0.9, 72.0), Transform3D(Basis.IDENTITY, Vector3(x + s * 3.75, hd + 0.45, zc)), Color(0.7, 0.7, 0.72))
	ramp_points.append(Vector3(x, hd, zc))


# ------------------------------------------------------------ streaming

func block_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x + HALF) / PITCH)), 0, N - 1), clampi(int(floor((p.z + HALF) / PITCH)), 0, N - 1))


func load_around(p: Vector3, immediate: bool) -> void:
	var b := block_of(p)
	if b != last_block:
		last_block = b
		load_queue.clear()
		for di in range(-LOAD_R, LOAD_R + 1):
			for dj in range(-LOAD_R, LOAD_R + 1):
				var k := Vector2i(b.x + di, b.y + dj)
				if k.x < 0 or k.y < 0 or k.x >= N or k.y >= N:
					continue
				if not loaded_blocks.has(k):
					load_queue.append(k)
		load_queue.sort_custom(func(a, c): return (a - b).length_squared() < (c - b).length_squared())
		for k in loaded_blocks.keys():
			if absi(k.x - b.x) > LOAD_R + 1 or absi(k.y - b.y) > LOAD_R + 1:
				for bl in block_buildings[k]:
					bl.unload_nodes()
				props.unload_block(k)
				loaded_blocks.erase(k)
	var budget := 999 if immediate else 2
	while budget > 0 and not load_queue.is_empty():
		var k: Vector2i = load_queue.pop_front()
		if loaded_blocks.has(k):
			continue
		for bl in block_buildings[k]:
			bl.load_nodes(chunk_root)
		props.load_block(k, chunk_root)
		loaded_blocks[k] = true
		budget -= 1


# ------------------------------------------------------------ debris pool

func _make_debris_pool() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * CELL * 0.96
	for i in MAX_DEBRIS:
		var rb := RigidBody3D.new()
		rb.mass = 60.0
		rb.linear_damp = 0.08
		rb.angular_damp = 0.25
		var pm := PhysicsMaterial.new()
		pm.friction = 0.7
		pm.bounce = 0.08
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = cube_mesh
		mi.material_override = debris_mats[i % debris_mats.size()]
		rb.add_child(mi)
		debris_root.add_child(rb)
		_deactivate(rb)
		debris_free.append(rb)


func _deactivate(rb: RigidBody3D) -> void:
	rb.freeze = true
	rb.collision_layer = 0
	rb.collision_mask = 0
	rb.visible = false
	rb.scale = Vector3.ONE
	rb.position = Vector3(0, -200, 0)


func spawn_debris(pos: Vector3, vel: Vector3, ang: Vector3) -> void:
	var rb: RigidBody3D
	if debris_free.is_empty():
		var old: Array = debris_active.pop_front()
		rb = old[0]
		_deactivate(rb)
	else:
		rb = debris_free.pop_back()
	rb.freeze = false
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	rb.visible = true
	rb.scale = Vector3.ONE
	rb.global_transform = Transform3D(Basis.from_euler(Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0)), pos)
	rb.linear_velocity = vel
	rb.angular_velocity = ang
	debris_active.append([rb, 9.0 + randf() * 5.0])


func _process(delta: float) -> void:
	for i in range(debris_active.size() - 1, -1, -1):
		var e: Array = debris_active[i]
		e[1] -= delta
		var rb: RigidBody3D = e[0]
		if e[1] < 1.0:
			rb.scale = Vector3.ONE * maxf(e[1], 0.05)
		if e[1] <= 0.0 or rb.global_position.y < -8.0:
			_deactivate(rb)
			debris_free.append(rb)
			debris_active.remove_at(i)
	for i in range(collapsing.size() - 1, -1, -1):
		var b: Building = collapsing[i]
		if not b.loaded:
			b.heights.fill(0)
			b.collapsing = false
			collapsing.remove_at(i)
			continue
		b.collapse_t += delta
		if b.collapse_t >= 0.2:
			b.collapse_t = 0.0
			var cells := b.collapse_step(2)
			if cells.size() > 0:
				main.cells_down += cells.size()
				_emit_cells(cells, b.center(), 3.0, 14)
				fx.dust(b.center() + Vector3(0, b.ny * 0.5, 0), cells.size())
				main.shake_cam(0.35)
				main.play_sfx("rumble", b.center())
		if not b.collapsing:
			collapsing.remove_at(i)


func register_collapse(b: Building) -> void:
	collapsing.append(b)
	main.on_building_collapse(b)


func _emit_cells(cells: PackedVector3Array, center: Vector3, force: float, max_n: int) -> void:
	var n := cells.size()
	var step := maxi(1, n / max_n)
	var start := randi() % step
	var i := start
	while i < n:
		var p := cells[i]
		var d := p - center
		var l := maxf(d.length(), 0.5)
		var v := d / l * force * randf_range(0.5, 1.2) + Vector3(randf_range(-1, 1), randf_range(0.5, 3.0), randf_range(-1, 1))
		spawn_debris(p, v, Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
		i += step


# ------------------------------------------------------------ damage API

# Destroys building cells in a sphere, spawns debris and dust. Returns cells destroyed.
func damage_area(center: Vector3, radius: float, force: float) -> int:
	var bk := block_of(center)
	var all := PackedVector3Array()
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var k := Vector2i(bk.x + di, bk.y + dj)
			if not block_buildings.has(k):
				continue
			for b: Building in block_buildings[k]:
				if b.loaded and b.heights.size() > 0:
					var cells: PackedVector3Array = b.damage_sphere(center, radius)
					if cells.size() > 0:
						all.append_array(cells)
	for e in debris_active:
		var rb: RigidBody3D = e[0]
		var d := rb.global_position - center
		var l := maxf(d.length(), 0.5)
		if l < radius * 1.6:
			rb.apply_central_impulse(d / l * force * 40.0 * (1.0 - l / (radius * 1.6)) + Vector3(0, 60, 0))
	props.blast(center, radius)
	if all.size() > 0:
		_emit_cells(all, center, force * 0.5, 26)
		fx.dust(center, all.size())
		main.on_cells_destroyed(all.size())
	return all.size()


func car_hit_building(b: Building, point: Vector3, dir: Vector3, speed: float) -> int:
	var radius := clampf(1.8 + speed * 0.1, 2.2, 5.5)
	var c := point + dir * 1.0 + Vector3(0, 0.3, 0)
	return damage_area(c, radius, speed * 0.7)


func building_near(p: Vector3, r: float) -> Building:
	var bk := block_of(p)
	var best: Building = null
	var bd := 1e9
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var k := Vector2i(bk.x + di, bk.y + dj)
			if not block_buildings.has(k):
				continue
			for b: Building in block_buildings[k]:
				if not b.loaded:
					continue
				var lo: Vector3 = b.origin
				var hi: Vector3 = b.origin + b.size_v()
				var q := Vector3(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y), clampf(p.z, lo.z, hi.z))
				var dd := q.distance_to(p)
				if dd < r and dd < bd:
					bd = dd
					best = b
	return best


func node_pos(n: Vector2i) -> Vector3:
	return Vector3(line(n.x), 0.9, line(n.y))


# A* over the intersection grid. Returns intersection centres from near `from` to near `to`.
func route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var a := Vector2i(clampi(roundi((from.x + HALF) / PITCH), 0, N), clampi(roundi((from.z + HALF) / PITCH), 0, N))
	var b := Vector2i(clampi(roundi((to.x + HALF) / PITCH), 0, N), clampi(roundi((to.z + HALF) / PITCH), 0, N))
	var out: Array[Vector3] = []
	if a == b:
		out.append(node_pos(b))
		return out
	var came := {}
	var gs := {a: 0.0}
	var open: Array[Vector2i] = [a]
	while not open.is_empty():
		var bi := 0
		var bf := 1e9
		for i in open.size():
			var n: Vector2i = open[i]
			var f: float = gs[n] + absf(n.x - b.x) + absf(n.y - b.y)
			if f < bf:
				bf = f
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == b:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nn: Vector2i = cur + d
			if nn.x < 0 or nn.y < 0 or nn.x > N or nn.y > N:
				continue
			var ng: float = gs[cur] + 1.0
			if not gs.has(nn) or ng < gs[nn]:
				gs[nn] = ng
				came[nn] = cur
				open.append(nn)
	var n2 := b
	var guard := 0
	while n2 != a and guard < 80:
		out.push_front(node_pos(n2))
		n2 = came[n2]
		guard += 1
	out.push_front(node_pos(a))
	return out


# Random point on a road at a distance range from p, with a heading along the road.
func road_spawn(p: Vector3, dmin: float, dmax: float) -> Dictionary:
	var a := randf() * TAU
	var d := randf_range(dmin, dmax)
	var q := p + Vector3(cos(a), 0, sin(a)) * d
	q.x = clampf(q.x, -HALF + 8.0, HALF - 8.0)
	q.z = clampf(q.z, -HALF + 8.0, HALF - 8.0)
	var kx := clampi(roundi((q.x + HALF) / PITCH), 0, N)
	var kz := clampi(roundi((q.z + HALF) / PITCH), 0, N)
	var sx := absf(q.x - line(kx))
	var sz := absf(q.z - line(kz))
	var yaw := 0.0
	var center := q
	if sx < sz:
		center.x = line(kx)
		q.x = line(kx) + (3.5 if randf() < 0.5 else -3.5)
		yaw = 0.0 if randf() < 0.5 else PI
	else:
		center.z = line(kz)
		q.z = line(kz) + (3.5 if randf() < 0.5 else -3.5)
		yaw = PI * 0.5 if randf() < 0.5 else -PI * 0.5
	q.x = clampf(q.x, -HALF + 8.0, HALF - 8.0)
	q.z = clampf(q.z, -HALF + 8.0, HALF - 8.0)
	q.y = 0.9
	center.y = 0.9
	return {"pos": q, "yaw": yaw, "center": center}
