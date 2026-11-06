class_name Skyline
extends Node3D
# Makes the city look endless and keeps buildings from ever popping into view.
#
# 1. Every block of the real 16 x 16 city always has a cheap "far" copy of its buildings
#    (the same boxes, the same facade, the same colours as the streamed-in detailed version).
#    When a block streams in next to the player the far copy is hidden in the same frame, and
#    when it streams out the far copy is rebuilt from the buildings' current (maybe wrecked)
#    state and shown. The swap looks like nothing, so a building is never "new" on screen.
# 2. Beyond the playable grid the same road grid carries on for RING more blocks each way,
#    lined with towers, mid-rises and suburbs (clusters of tall towers every so often), and it
#    fades into the fog. Nothing out there can be driven to; it only has to read as more city.
# 3. A rail tunnel house stands at each end of the railway so the train still has somewhere to
#    come out of, now that there is no wall at the edge of the map.

const RING := 8
const FAR_CELLS := 1.0           # facade cells per CELL on the ring (bigger windows read better far away)

var world: World
var lod := {}                    # block key -> MeshInstance3D (the far copy)
var lod_cells := {}              # block key -> alive cells when the far copy was built
var queue: Array[Vector2i] = []
var ring_nodes: Array[MeshInstance3D] = []

# the six faces of a box: normal, u axis, v axis (same table as World.add_box)
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
]
const CORNERS := [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]


func setup(w: World) -> void:
	world = w
	var mid := Vector2i(World.N / 2, World.N / 2)
	for k in world.block_buildings:
		queue.append(k)
	queue.sort_custom(func(a, b): return (a - mid).length_squared() < (b - mid).length_squared())
	_build_ring()


# ------------------------------------------------------------ geometry helpers

static func new_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
		"c": PackedColorArray(), "i": PackedInt32Array()}


# Appends a box (no bottom face: nobody sees it) to a set of arrays. Same faces, UVs and
# windows as World.add_box, so the far copy matches the detailed building cell for cell.
static func add_box(a: Dictionary, c: Vector3, size: Vector3, cells: Vector3, color: Color, bottom: bool = false) -> void:
	var half := size * 0.5
	var verts: PackedVector3Array = a["v"]
	var nors: PackedVector3Array = a["n"]
	var uvs: PackedVector2Array = a["uv"]
	var cols: PackedColorArray = a["c"]
	var idx: PackedInt32Array = a["i"]
	var nfaces := 6 if bottom else 5
	for fi in nfaces:
		var f: Array = FACES[fi]
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var eu := absf(u.dot(half))
		var ev := absf(v.dot(half))
		var cu := absf(u.dot(cells))
		var cv := absf(v.dot(cells))
		var base := verts.size()
		var o := c + n * absf(n.dot(half))
		for cc: Vector2 in CORNERS:
			verts.append(o + u * (cc.x * eu) + v * (cc.y * ev))
			nors.append(n)
			uvs.append(Vector2((cc.x + 1.0) * 0.5 * cu, (cc.y + 1.0) * 0.5 * cv))
			cols.append(color)
		idx.append(base)
		idx.append(base + 1)
		idx.append(base + 2)
		idx.append(base)
		idx.append(base + 2)
		idx.append(base + 3)


static func mesh_of(a: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	if (a["v"] as PackedVector3Array).is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["v"]
	arr[Mesh.ARRAY_NORMAL] = a["n"]
	arr[Mesh.ARRAY_TEX_UV] = a["uv"]
	arr[Mesh.ARRAY_COLOR] = a["c"]
	arr[Mesh.ARRAY_INDEX] = a["i"]
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ------------------------------------------------------------ far copies of the real blocks

func _alive(key: Vector2i) -> int:
	var n := 0
	for b: Building in world.block_buildings[key]:
		n += b.total_alive()
	return n


func _build_block(key: Vector2i) -> void:
	var a := new_arrays()
	for b: Building in world.block_buildings[key]:
		var col := Color(b.tint.r, b.tint.g, b.tint.b, b.style)
		for r in b._runs():
			var sz := Vector3(r[2] * Building.C, r[3] * Building.C, Building.C)
			var c := b.origin + Vector3((r[0] + r[2] * 0.5) * Building.C, r[3] * Building.C * 0.5, (r[1] + 0.5) * Building.C)
			add_box(a, c, sz, Vector3(r[2], r[3], 1), col)
		for rd: Array in b.roof_defs:
			if rd[0] == "spire":
				var top := float(b.heights[rd[1] + rd[2] * b.nx]) * Building.C
				if top > 0.0 and b.heights[rd[1] + rd[2] * b.nx] >= b.init_h[rd[1] + rd[2] * b.nx]:
					var mc := b.origin + Vector3((rd[1] + 0.5) * Building.C, top + Landmarks.SPIRE_H * 0.5, (rd[2] + 0.5) * Building.C)
					add_box(a, mc, Vector3(0.5, Landmarks.SPIRE_H, 0.5), Vector3(1, 8, 1), Color(0.82, 0.83, 0.86, 0.5))
	if lod.has(key):
		(lod[key] as MeshInstance3D).mesh = mesh_of(a)
	else:
		lod[key] = _instance(mesh_of(a), world.facade_mat)
	lod_cells[key] = _alive(key)


func block_loaded(key: Vector2i) -> void:
	if lod.has(key):
		(lod[key] as MeshInstance3D).visible = false


# The detailed nodes of a block were just freed: the far copy takes over in this same frame.
func block_unloaded(key: Vector2i) -> void:
	if not world.block_buildings.has(key):
		return
	if not lod.has(key) or lod_cells.get(key, -1) != _alive(key):
		_build_block(key)
	(lod[key] as MeshInstance3D).visible = true


func _process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	while not queue.is_empty() and Time.get_ticks_usec() - t0 < 4000:
		var key: Vector2i = queue.pop_front()
		if lod.has(key):
			continue
		if world.loaded_blocks.has(key):
			continue        # in detail right now: its far copy is made when it streams out
		_build_block(key)


# ------------------------------------------------------------ the endless ring

static func _look(kind: String, rng: RandomNumberGenerator) -> Array:
	var tint := Color.WHITE
	var style := 0.5
	match kind:
		"down":
			if rng.randf() < 0.6:
				style = 0.85
				tint = [Color(0.42, 0.58, 0.72), Color(0.38, 0.56, 0.58), Color(0.55, 0.64, 0.74), Color(0.3, 0.42, 0.6)][rng.randi() % 4]
			else:
				tint = Color(0.66, 0.66, 0.64).lerp(Color(0.82, 0.76, 0.66), rng.randf())
		"mid":
			if rng.randf() < 0.5:
				style = 0.15
				tint = Color(0.68, 0.36, 0.26).lerp(Color(0.8, 0.56, 0.4), rng.randf())
			else:
				tint = Color(0.74, 0.7, 0.62).lerp(Color(0.88, 0.82, 0.72), rng.randf())
		"sub":
			style = 0.15 if rng.randf() < 0.5 else 0.5
			tint = [Color(0.9, 0.8, 0.6), Color(0.62, 0.78, 0.74), Color(0.84, 0.62, 0.6), Color(0.72, 0.74, 0.88)][rng.randi() % 4]
		_:
			tint = Color(0.56, 0.56, 0.58).lerp(Color(0.68, 0.48, 0.4), rng.randf() * 0.6)
	return [tint, World.encode_style(style, rng.randi_range(0, 3))]


func _build_ring() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var noise := FastNoiseLite.new()
	noise.seed = 91
	noise.frequency = 0.17
	var chunks := {}
	var zr := world.rail_z()
	var lot_for := {"down": 2, "mid": 2, "sub": 3, "ind": 1}
	for bi in range(-RING, World.N + RING):
		for bj in range(-RING, World.N + RING):
			if bi >= 0 and bi < World.N and bj >= 0 and bj < World.N:
				continue
			var ring_d := maxi(maxi(-bi, bi - (World.N - 1)), maxi(-bj, bj - (World.N - 1)))
			var nv := noise.get_noise_2d(bi, bj) * 0.5 + 0.5
			var kind := "mid"
			if nv > 0.6:
				kind = "down"          # a second downtown on the horizon
			elif ring_d > 3 or nv < 0.3:
				kind = "sub"
			if nv < 0.12 and ring_d > 1:
				continue               # a park
			if nv > 0.88 and kind != "down":
				kind = "ind"
			# the rail tunnel houses stand where the railway leaves the map
			if bj == World.RAIL_ROW and (bi == World.N or bi == World.N + 1 or bi == -1 or bi == -2):
				continue
			var key := Vector2i(floori(bi / 4.0), floori(bj / 4.0))
			if not chunks.has(key):
				chunks[key] = new_arrays()
			var arrays: Dictionary = chunks[key]
			var lots: int = lot_for[kind]
			var lot_cells := 26 / lots
			var x0 := world.line(bi) + 10.0
			var z0 := world.line(bj) + 10.0
			for a in lots:
				for b in lots:
					if kind == "sub" and rng.randf() < 0.3:
						continue
					var w := 5
					var d := 5
					var h := 4
					match kind:
						"down":
							w = rng.randi_range(7, 10)
							d = rng.randi_range(7, 10)
							h = rng.randi_range(14, 34) if rng.randf() < 0.7 else rng.randi_range(8, 14)
						"mid":
							w = rng.randi_range(6, 11)
							d = rng.randi_range(6, 11)
							h = rng.randi_range(4, 11)
						"sub":
							w = rng.randi_range(4, 6)
							d = rng.randi_range(4, 6)
							h = rng.randi_range(2, 3)
						_:
							w = rng.randi_range(16, 22)
							d = rng.randi_range(10, 14)
							h = rng.randi_range(3, 4)
					w = mini(w, lot_cells - 1)
					d = mini(d, lot_cells - 1)
					var ox := x0 + (a * lot_cells + rng.randi_range(0, lot_cells - w)) * World.CELL
					var oz := z0 + (b * lot_cells + rng.randi_range(0, lot_cells - d)) * World.CELL
					if bj == World.RAIL_ROW and oz + d * World.CELL > zr - World.RAIL_CLEAR and oz < zr + World.RAIL_CLEAR:
						continue
					var lk := _look(kind, rng)
					var tint: Color = lk[0]
					var col := Color(tint.r, tint.g, tint.b, float(lk[1]))
					var size := Vector3(w, h, d) * World.CELL
					var cells := size / (World.CELL * FAR_CELLS * 2.0)
					add_box(arrays, Vector3(ox, 0.0, oz) + size * Vector3(0.5, 0.5, 0.5), size, cells, col)
					# a tower gets a narrower upper tier now and then, so the skyline is not all boxes
					if kind == "down" and h >= 10 and rng.randf() < 0.55:
						var inset := rng.randi_range(1, 2)
						var w2 := maxi(w - inset * 2, 2)
						var d2 := maxi(d - inset * 2, 2)
						var h2 := maxi(int(h * rng.randf_range(0.25, 0.5)), 2)
						var s2 := Vector3(w2, h2, d2) * World.CELL
						var base := Vector3(ox + inset * World.CELL, h * World.CELL, oz + inset * World.CELL)
						add_box(arrays, base + s2 * Vector3(0.5, 0.5, 0.5), s2, s2 / (World.CELL * FAR_CELLS * 2.0), col)
	for key in chunks:
		var mesh := mesh_of(chunks[key])
		ring_nodes.append(_instance(mesh, world.facade_mat))
	_build_tunnel_houses(zr)


# A big concrete block over the end of the track: the train disappears into it and comes out
# of it. 85 m long, so a whole train (58 m) fits inside with room to spare.
func _build_tunnel_houses(zr: float) -> void:
	var a := new_arrays()
	var conc := Color(0.62, 0.62, 0.64, 0.0)
	var dark := Color(0.34, 0.34, 0.37, 0.0)
	for s in [-1.0, 1.0]:
		var cx: float = s * (World.HALF + 10.5 + 42.5)
		add_box(a, Vector3(cx, 7.0, zr), Vector3(85.0, 14.0, 62.0), Vector3(1, 1, 1), conc)
		add_box(a, Vector3(cx, 14.6, zr), Vector3(85.0, 1.2, 64.0), Vector3(1, 1, 1), dark)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_instance(mesh_of(a), mat)
