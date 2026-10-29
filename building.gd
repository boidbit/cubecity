class_name Building
extends RefCounted
# One destructible building. Data lives for the whole game; nodes exist only while
# its block is near the player. Each column keeps one height (cells stay contiguous
# from the ground), so setbacks, L-shapes and chimneys are just different column heights.

const C := 2.0

var world
var origin: Vector3
var nx := 1
var ny := 1
var nz := 1
var heights := PackedInt32Array()
var init_h := PackedInt32Array()
var shown := PackedByteArray()
var tint := Color.WHITE
var style := 0.5
var roof_defs: Array = []      # [kind, x, z, seed]
var roof_nodes: Array = []     # [Node3D, column index, needed height]
var body: StaticBody3D
var simple: MeshInstance3D
var mmi: MultiMeshInstance3D
var mm: MultiMesh
var shapes: Array[CollisionShape3D] = []
var detailed := false
var loaded := false
var collapsing := false
var collapse_t := 0.0


func setup(w, o: Vector3, sx: int, sz: int, hs: PackedInt32Array, t: Color, st: float) -> void:
	world = w
	origin = o
	nx = sx
	nz = sz
	heights = hs
	init_h = hs.duplicate()
	ny = 1
	for h in hs:
		ny = maxi(ny, h)
	tint = t
	style = st


func size_v() -> Vector3:
	return Vector3(nx, ny, nz) * C


func center() -> Vector3:
	return origin + size_v() * 0.5


func cell_pos(x: int, y: int, z: int) -> Vector3:
	return origin + Vector3((x + 0.5) * C, (y + 0.5) * C, (z + 0.5) * C)


func idx(x: int, y: int, z: int) -> int:
	return x + nx * (z + nz * y)


func is_alive(x: int, y: int, z: int) -> bool:
	if x < 0 or z < 0 or y < 0 or x >= nx or z >= nz:
		return false
	return y < heights[x + z * nx]


func total_alive() -> int:
	var n := 0
	for h in heights:
		n += h
	return n


func _runs() -> Array:
	# merges equal-height neighbours along x: [x0, z, len, h]
	var out := []
	for z in nz:
		var x := 0
		while x < nx:
			var h := heights[x + z * nx]
			if h <= 0:
				x += 1
				continue
			var x1 := x
			while x1 + 1 < nx and heights[x1 + 1 + z * nx] == h:
				x1 += 1
			out.append([x, z, x1 - x + 1, h])
			x = x1 + 1
	return out


func load_nodes(parent: Node3D) -> void:
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("bld", self)
	parent.add_child(body)
	if detailed:
		_build_multimesh()
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var col := Color(tint.r, tint.g, tint.b, style)
		for r in _runs():
			var sz := Vector3(r[2] * C, r[3] * C, C)
			var c := origin + Vector3((r[0] + r[2] * 0.5) * C, r[3] * C * 0.5, (r[1] + 0.5) * C)
			World.add_box(st, c, sz, Vector3(r[2], r[3], 1), col)
		simple = MeshInstance3D.new()
		simple.mesh = st.commit()
		simple.material_override = world.facade_mat
		body.add_child(simple)
	_rebuild_collision()
	_make_roof()
	loaded = true


func unload_nodes() -> void:
	if body != null and is_instance_valid(body):
		body.queue_free()
	body = null
	simple = null
	mmi = null
	mm = null
	shapes.clear()
	roof_nodes.clear()
	loaded = false


func _make_roof() -> void:
	roof_nodes.clear()
	for d in roof_defs:
		var x: int = d[1]
		var z: int = d[2]
		var h := heights[x + z * nx]
		if h <= 0 or h < init_h[x + z * nx]:
			continue
		var n: Node3D = world.props.make_roof_prop(d[0], d[3])
		n.position = origin + Vector3((x + 0.5) * C, h * C, (z + 0.5) * C)
		body.add_child(n)
		roof_nodes.append([n, x + z * nx, h])


func _check_roof() -> void:
	for i in range(roof_nodes.size() - 1, -1, -1):
		var r: Array = roof_nodes[i]
		if heights[r[1]] < r[2]:
			var n: Node3D = r[0]
			if is_instance_valid(n):
				world.props.drop_roof_prop(n)
			roof_nodes.remove_at(i)


func _make_detailed() -> void:
	detailed = true
	if simple != null:
		simple.queue_free()
		simple = null
	_build_multimesh()


func _build_multimesh() -> void:
	var total := nx * ny * nz
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = world.cube_mesh
	mm.instance_count = total
	shown.resize(total)
	shown.fill(0)
	var hidden_basis := Basis().scaled(Vector3.ZERO)
	for y in ny:
		for z in nz:
			for x in nx:
				var i := idx(x, y, z)
				var p := cell_pos(x, y, z)
				var v := 0.94 + 0.12 * fposmod(sin(float(i) * 12.9898 + origin.x * 0.31 + origin.z * 0.17) * 43758.5453, 1.0)
				mm.set_instance_color(i, Color(tint.r * v, tint.g * v, tint.b * v, style))
				if is_alive(x, y, z) and _exposed(x, y, z):
					mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
					shown[i] = 1
				else:
					mm.set_instance_transform(i, Transform3D(hidden_basis, p))
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = world.facade_mat
	body.add_child(mmi)


func _exposed(x: int, y: int, z: int) -> bool:
	return not (is_alive(x - 1, y, z) and is_alive(x + 1, y, z) and is_alive(x, y, z - 1) and is_alive(x, y, z + 1) and is_alive(x, y + 1, z) and (y == 0 or is_alive(x, y - 1, z)))


func _rebuild_collision() -> void:
	for s in shapes:
		if is_instance_valid(s):
			s.disabled = true
			s.queue_free()
	shapes.clear()
	if body == null:
		return
	for r in _runs():
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r[2] * C, r[3] * C, C)
		cs.shape = bs
		cs.position = origin + Vector3((r[0] + r[2] * 0.5) * C, r[3] * C * 0.5, (r[1] + 0.5) * C)
		body.add_child(cs)
		shapes.append(cs)


# Destroys every column cell inside the sphere, plus everything above it.
func damage_sphere(c: Vector3, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sz := size_v()
	if c.x + r < origin.x or c.x - r > origin.x + sz.x or c.z + r < origin.z or c.z - r > origin.z + sz.z or c.y - r > sz.y:
		return out
	var killed := PackedInt32Array()
	var r2 := r * r
	var x0 := clampi(int(floor((c.x - r - origin.x) / C)), 0, nx - 1)
	var x1 := clampi(int(floor((c.x + r - origin.x) / C)), 0, nx - 1)
	var z0 := clampi(int(floor((c.z - r - origin.z) / C)), 0, nz - 1)
	var z1 := clampi(int(floor((c.z + r - origin.z) / C)), 0, nz - 1)
	var any := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var h := heights[x + z * nx]
			for y in h:
				if cell_pos(x, y, z).distance_squared_to(c) <= r2:
					any = true
					break
	if not any:
		return out
	if not detailed:
		_make_detailed()
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var h := heights[x + z * nx]
			if h <= 0:
				continue
			var lowest := -1
			for y in h:
				if cell_pos(x, y, z).distance_squared_to(c) <= r2:
					lowest = y
					break
			if lowest >= 0:
				for y in range(lowest, h):
					out.append(cell_pos(x, y, z))
					killed.append(idx(x, y, z))
				heights[x + z * nx] = lowest
	if killed.size() > 0:
		_after_damage(killed)
		_check_collapse()
	return out


func _after_damage(killed: PackedInt32Array) -> void:
	var hidden_basis := Basis().scaled(Vector3.ZERO)
	for i in killed:
		var x := i % nx
		var z := (i / nx) % nz
		var y := i / (nx * nz)
		mm.set_instance_transform(i, Transform3D(hidden_basis, cell_pos(x, y, z)))
		shown[i] = 0
	for i in killed:
		var x := i % nx
		var z := (i / nx) % nz
		var y := i / (nx * nz)
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
			var ax: int = x + d.x
			var ay: int = y + d.y
			var az: int = z + d.z
			if is_alive(ax, ay, az):
				var j := idx(ax, ay, az)
				if shown[j] == 0:
					mm.set_instance_transform(j, Transform3D(Basis.IDENTITY, cell_pos(ax, ay, az)))
					shown[j] = 1
	_rebuild_collision()
	_check_roof()


func _check_collapse() -> void:
	if collapsing:
		return
	var weak := 0
	var cols := 0
	for i in heights.size():
		if init_h[i] <= 0:
			continue
		cols += 1
		if heights[i] < int(init_h[i] * 0.5):
			weak += 1
	if cols > 0 and weak > int(cols * 0.4) and ny > 3:
		collapsing = true
		collapse_t = 0.0
		world.register_collapse(self)


func collapse_step(layers: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var killed := PackedInt32Array()
	for z in nz:
		for x in nx:
			var h := heights[x + z * nx]
			if h <= 0:
				continue
			var nh := maxi(0, h - layers)
			for y in range(nh, h):
				out.append(cell_pos(x, y, z))
				killed.append(idx(x, y, z))
			heights[x + z * nx] = nh
	if killed.size() > 0 and mm != null:
		_after_damage(killed)
	if total_alive() == 0:
		collapsing = false
	return out
