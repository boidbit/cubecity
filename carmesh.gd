class_name CarMesh
extends RefCounted
# Builds car bodies from a side profile: sloped hood, windscreen, roof, rear glass,
# narrower cabin (tumblehome), side windows and dark wheel arches. Vertex colour alpha
# tells the car shader what a surface is: 0 = paint, 0.5 = black trim, 0.7 = headlamp,
# 0.8 = tail lamp, 1 = glass.
#
# Bodies are lofted: a ring of 20 points (underside, skirt, flanks, cabin with tumblehome,
# roof) is swept from nose to tail, its height following the car's side silhouette, its plan
# rounded at both ends. Every surface is smooth-shaded (a crease only where two faces really
# meet at a corner), so the paint catches light like paint instead of showing facets.

const PAINT := Color(1, 1, 1, 0.0)
const TRIM := Color(0.04, 0.04, 0.05, 0.5)
const GLASS := Color(0.05, 0.08, 0.12, 1.0)
const LAMP_H := Color(1.0, 0.95, 0.8, 0.7)
const LAMP_T := Color(0.9, 0.05, 0.05, 0.8)

static var cache := {}


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var nn := -n.normalized()
	for v in [a, b, c]:
		st.set_normal(nn)
		st.set_color(col)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	_tri(st, a, b, c, outward, col)
	_tri(st, a, c, d, outward, col)


static func box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n: Vector3 in axes:
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		var o := c + n * absf(n.dot(h))
		var eu := u * absf(u.dot(h))
		var ev := v * absf(v.dot(h))
		_quad(st, o - eu - ev, o + eu - ev, o + eu + ev, o - eu + ev, n, col)


static func _side_poly(st: SurfaceTool, pts2: PackedVector2Array, widths: PackedFloat32Array, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(pts2)
	for s in [-1.0, 1.0]:
		var out := Vector3(s, 0, 0)
		for i in range(0, idx.size(), 3):
			var a := Vector3(s * widths[idx[i]], pts2[idx[i]].y, pts2[idx[i]].x)
			var b := Vector3(s * widths[idx[i + 1]], pts2[idx[i + 1]].y, pts2[idx[i + 1]].x)
			var c := Vector3(s * widths[idx[i + 2]], pts2[idx[i + 2]].y, pts2[idx[i + 2]].x)
			_tri(st, a, b, c, out, col)


# The older extruded-silhouette builder, still used by the story's convertible (story/roadster.gd).
# profile: Vector3(z, y, half_width) going around the silhouette.
static func _body(profile: Array, glass_edges: Array, window: Array, wheel_z: Array, low_w: float, cabin_w: float, cab_y0: float, cab_y1: float, extras: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var cen := Vector2.ZERO
	var pts := PackedVector2Array()
	var ws := PackedFloat32Array()
	for p: Vector3 in profile:
		cen += Vector2(p.x, p.y)
		pts.append(Vector2(p.x, p.y))
		ws.append(p.z)
	cen /= n
	for i in n:
		var p: Vector3 = profile[i]
		var q: Vector3 = profile[(i + 1) % n]
		var d := Vector2(q.x - p.x, q.y - p.y)
		var n2 := Vector2(d.y, -d.x)
		var mid := Vector2(p.x + q.x, p.y + q.y) * 0.5
		if n2.dot(mid - cen) < 0.0:
			n2 = -n2
		var out := Vector3(0, n2.y, n2.x)
		var col := GLASS if glass_edges.has(i) else (TRIM if i == n - 1 else PAINT)
		_quad(st, Vector3(-p.z, p.y, p.x), Vector3(p.z, p.y, p.x), Vector3(q.z, q.y, q.x), Vector3(-q.z, q.y, q.x), out, col)
	_side_poly(st, pts, ws, PAINT)
	# side windows follow the cabin taper
	var wp := PackedVector2Array()
	var ww := PackedFloat32Array()
	for v: Vector2 in window:
		wp.append(v)
		var t := clampf((v.y - cab_y0) / (cab_y1 - cab_y0), 0.0, 1.0)
		ww.append(lerpf(low_w, cabin_w, t) + 0.012)
	_side_poly(st, wp, ww, GLASS)
	# wheel arches
	for z: float in wheel_z:
		var arc := PackedVector2Array()
		var aw := PackedFloat32Array()
		for k in 11:
			var a := PI * float(k) / 10.0
			arc.append(Vector2(z + cos(a) * 0.52, 0.34 + sin(a) * 0.5))
			aw.append(low_w + 0.015)
		_side_poly(st, arc, aw, TRIM)
	extras.call(st)
	return st.commit()



const RING_N := 20
const STATIONS := 38


static func _top_y(pts: Array, z: float) -> float:
	if z <= (pts[0] as Vector2).x:
		return (pts[0] as Vector2).y
	for i in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		if z <= q.x:
			return lerpf(p.y, q.y, (z - p.x) / maxf(q.x - p.x, 0.0001))
	return (pts[pts.size() - 1] as Vector2).y


# The silhouette height at z, with the corners (hood to windscreen, roof to boot) eased off.
static func _top_smooth(pts: Array, z: float) -> float:
	return (_top_y(pts, z - 0.2) + 2.0 * _top_y(pts, z) + _top_y(pts, z + 0.2)) * 0.25


static func _in(z: float, r: Vector2) -> bool:
	return z >= r.x and z <= r.y


# One ring of the loft at station z. Returns the 20 points; also fills info (the facts the
# colouring needs: width scale at the ends, roof height, whether there is a cabin here).
static func _ring(sp: Dictionary, z: float, info: Dictionary) -> PackedVector3Array:
	var pts: Array = sp["top"]
	var zmin: float = (pts[0] as Vector2).x
	var zmax: float = (pts[pts.size() - 1] as Vector2).x
	var tip: float = sp["tip"]
	var s := clampf(minf(z - zmin, zmax - z) / tip, 0.0, 1.0)
	var f := sqrt(maxf(1.0 - (1.0 - s) * (1.0 - s), 0.0))
	var yb: float = sp["yb"]
	var yt := _top_smooth(pts, z)
	var belt: float = sp["belt"]
	var wl: float = sp["low_w"] * maxf(f, 0.04)
	var yb_e := yb + (1.0 - f) * 0.1
	var yt_e := yt - (1.0 - f) * (yt - yb) * 0.3
	var cab_t := smoothstep(belt + 0.04, sp["roof"], yt)
	var wc: float = lerpf(wl, sp["cabin_w"] * maxf(f, 0.04), cab_t)
	var belt_y := minf(belt, yt_e - 0.2)
	var lo := yb_e + 0.1
	var right: Array[Vector2] = [
		Vector2(0.0, yb_e),
		Vector2(wl - 0.16, yb_e),
		Vector2(wl, lo),
		Vector2(wl, lo + (belt_y - lo) * 0.33),
		Vector2(wl, lo + (belt_y - lo) * 0.66),
		Vector2(wl, belt_y),
		Vector2(lerpf(wl, wc, 0.55), belt_y + (yt_e - 0.1 - belt_y) * 0.55),
		Vector2(wc, yt_e - 0.1),
		Vector2(wc - 0.09, yt_e - 0.025),
		Vector2(wc * 0.55, yt_e),
		Vector2(0.0, yt_e),
	]
	var out := PackedVector3Array()
	for p in right:
		out.append(Vector3(p.x, p.y, z))
	for k in range(9, 0, -1):
		out.append(Vector3(-right[k].x, right[k].y, z))
	info["f"] = f
	info["wl"] = wl
	info["yt"] = yt_e
	info["cab"] = cab_t > 0.3 and f > 0.6
	return out


static func _paint_for(sp: Dictionary, seg: int, c: Vector3, f: float, wl: float, cab: bool, nrm: Vector3 = Vector3.ZERO) -> Color:
	var pts: Array = sp["top"]
	var zmin: float = (pts[0] as Vector2).x
	var zmax: float = (pts[pts.size() - 1] as Vector2).x
	var ax := absf(c.x)
	var u := ax / maxf(wl, 0.05)
	var ly: float = sp["lamp_y"]
	# lamps and grille on the nose, lamps on the tail
	var facing := absf(nrm.z)       # only surfaces that face the nose or the tail carry lamps
	if c.z < zmin + 0.45 and seg >= 2 and seg <= 6 and facing > 0.72:
		if u > 0.5 and u < 1.05 and c.y > ly - 0.11 and c.y < ly + 0.1:
			return LAMP_H
		if u <= 0.5 and c.y > 0.42 and c.y < ly + 0.08:
			return TRIM
		if c.y < 0.58:
			return TRIM
	if c.z > zmax - 0.45 and seg >= 2 and seg <= 6 and facing > 0.72:
		if u > 0.45 and u < 1.05 and c.y > ly - 0.08 and c.y < ly + 0.13:
			return LAMP_T
		if c.y < 0.56:
			return TRIM
	match seg:
		0, 1:
			return TRIM
		2, 3, 4:
			for wz: float in sp["wheels"]:
				var dz := (c.z - wz) / 0.47
				var dy := (c.y - 0.4) / 0.5
				if dz * dz + dy * dy < 1.0 and ax > sp["low_w"] - 0.2:
					return TRIM
			return PAINT
		5, 6:
			if cab and _in(c.z, sp["side_win"]):
				for pz: float in sp["pillars"]:
					if absf(c.z - pz) < 0.06:
						return PAINT
				return GLASS
			return PAINT
		8, 9:
			if cab and (_in(c.z, sp["wind_f"]) or _in(c.z, sp["wind_r"])):
				return GLASS
			return PAINT
		_:
			return PAINT


static func _loft(sp: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = sp["top"]
	var zmin: float = (pts[0] as Vector2).x
	var zmax: float = (pts[pts.size() - 1] as Vector2).x
	var rings: Array[PackedVector3Array] = []
	var infos: Array[Dictionary] = []
	for i in STATIONS:
		var t := float(i) / float(STATIONS - 1)
		var z := zmin + (zmax - zmin) * (0.5 - 0.5 * cos(PI * t))
		var info := {}
		rings.append(_ring(sp, z, info))
		infos.append(info)
	# cell normals
	var cn := []
	for i in STATIONS - 1:
		var row := []
		var ctr := Vector3(0, (infos[i]["yt"] + sp["yb"]) * 0.5, rings[i][0].z)
		for j in RING_N:
			var a := rings[i][j]
			var b := rings[i][(j + 1) % RING_N]
			var d := rings[i + 1][j]
			var n := (b - a).cross(d - a)
			if n.length() < 1e-9:
				n = (rings[i + 1][(j + 1) % RING_N] - a).cross(b - a)
			n = n.normalized()
			var mid := (a + b + d + rings[i + 1][(j + 1) % RING_N]) * 0.25
			if n.dot(mid - ctr) < 0.0:
				n = -n
			row.append(n)
		cn.append(row)
	for i in STATIONS - 1:
		for j in RING_N:
			var j1 := (j + 1) % RING_N
			var v := [rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]]
			var own: Vector3 = cn[i][j]
			var cen: Vector3 = (v[0] + v[1] + v[2] + v[3]) * 0.25
			var seg := j if j < 10 else 19 - j
			var info: Dictionary = infos[i]
			var col := _paint_for(sp, seg, cen, (infos[i]["f"] + infos[i + 1]["f"]) * 0.5, (infos[i]["wl"] + infos[i + 1]["wl"]) * 0.5, infos[i]["cab"] and infos[i + 1]["cab"], own)
			# per-corner smooth normal: average the neighbouring cells that bend away gently
			var corner_cells := [[i - 1, j - 1], [i - 1, j], [i, j - 1], [i, j]]
			var nrm: Array[Vector3] = []
			var corners := [[0, 0], [0, 1], [1, 1], [1, 0]]
			for ci in 4:
				var ox: int = corners[ci][0]
				var oy: int = corners[ci][1]
				var sum := Vector3.ZERO
				for di in [ox - 1, ox]:
					for dj in [oy - 1, oy]:
						var ii: int = i + di
						var jj: int = posmod(j + dj, RING_N)
						if ii < 0 or ii >= STATIONS - 1:
							continue
						var nb: Vector3 = cn[ii][jj]
						if nb.dot(own) > 0.78:
							sum += nb
				nrm.append((sum if sum.length() > 0.001 else own).normalized())
			# two triangles, wound so the face points the way `own` does
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = v[tri[0]]
				var b: Vector3 = v[tri[1]]
				var c: Vector3 = v[tri[2]]
				var fn := (b - a).cross(c - a)
				if fn.length() < 1e-10:
					continue
				var order: Array = tri
				if fn.dot(own) < 0.0:
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					st.set_normal(nrm[k])
					st.set_color(col)
					st.add_vertex(v[k])
	# end caps
	for end in [0, STATIONS - 1]:
		var ring: PackedVector3Array = rings[end]
		var ctr := Vector3.ZERO
		for p in ring:
			ctr += p
		ctr /= float(RING_N)
		var out := Vector3(0, 0, -1.0 if end == 0 else 1.0)
		var capc := TRIM if (infos[end]["yt"] < 0.8) else PAINT
		for j in RING_N:
			var a := ring[j]
			var b := ring[(j + 1) % RING_N]
			var n := (b - a).cross(ctr - a)
			var tri := [a, b, ctr] if n.dot(out) > 0.0 else [b, a, ctr]
			for p in tri:
				st.set_normal(out)
				st.set_color(capc)
				st.add_vertex(p)
	# door seams, handles and mirrors
	var wl: float = sp["low_w"]
	var belt: float = sp["belt"]
	for sgn in [-1.0, 1.0]:
		for dz: float in sp["doors"]:
			box(st, Vector3(sgn * (wl + 0.003), (0.5 + belt) * 0.5, dz), Vector3(0.012, belt - 0.5, 0.022), TRIM)
		for hz: float in sp["handles"]:
			box(st, Vector3(sgn * (wl + 0.012), belt - 0.1, hz), Vector3(0.026, 0.045, 0.17), TRIM)
		box(st, Vector3(sgn * (wl + 0.1), sp["mirror_y"], sp["mirror_z"]), Vector3(0.2, 0.12, 0.09), PAINT)
		box(st, Vector3(sgn * (wl + 0.015), sp["mirror_y"] - 0.07, sp["mirror_z"] + 0.02), Vector3(0.06, 0.05, 0.06), TRIM)
	if sp.has("extras"):
		(sp["extras"] as Callable).call(st)
	return st.commit()


static func _spec(kind: String) -> Dictionary:
	match kind:
		"sport":
			return {"top": [Vector2(-2.12, 0.56), Vector2(-1.98, 0.74), Vector2(-0.8, 0.86), Vector2(-0.15, 1.26), Vector2(0.7, 1.28),
					Vector2(1.45, 0.97), Vector2(2.02, 0.92), Vector2(2.1, 0.58)],
				"low_w": 0.89, "cabin_w": 0.7, "belt": 0.86, "roof": 1.28, "yb": 0.32, "tip": 0.34,
				"wheels": [-1.3, 1.3], "wind_f": Vector2(-0.85, -0.1), "wind_r": Vector2(0.66, 1.5), "side_win": Vector2(-0.68, 1.38),
				"pillars": [0.35], "doors": [-0.5, 0.32], "handles": [-0.3, 0.52], "mirror_z": -0.78, "mirror_y": 0.98, "lamp_y": 0.66}
		"sedan":
			return {"top": [Vector2(-2.15, 0.6), Vector2(-2.0, 0.78), Vector2(-0.95, 0.88), Vector2(-0.35, 1.38), Vector2(0.85, 1.4),
					Vector2(1.35, 0.98), Vector2(2.05, 0.94), Vector2(2.12, 0.6)],
				"low_w": 0.91, "cabin_w": 0.74, "belt": 0.88, "roof": 1.38, "yb": 0.34, "tip": 0.34,
				"wheels": [-1.3, 1.3], "wind_f": Vector2(-0.98, -0.28), "wind_r": Vector2(0.8, 1.4), "side_win": Vector2(-0.84, 1.26),
				"pillars": [0.2], "doors": [-0.62, 0.2, 0.98], "handles": [-0.4, 0.4], "mirror_z": -0.9, "mirror_y": 1.02, "lamp_y": 0.66}
		"suv":
			return {"top": [Vector2(-2.2, 0.72), Vector2(-2.05, 0.95), Vector2(-0.95, 1.05), Vector2(-0.45, 1.62), Vector2(1.7, 1.66),
					Vector2(2.1, 1.1), Vector2(2.2, 0.98), Vector2(2.22, 0.62)],
				"low_w": 0.94, "cabin_w": 0.8, "belt": 1.0, "roof": 1.66, "yb": 0.4, "tip": 0.26,
				"wheels": [-1.4, 1.45], "wind_f": Vector2(-0.98, -0.4), "wind_r": Vector2(1.72, 2.12), "side_win": Vector2(-0.9, 1.98),
				"pillars": [0.3, 1.05], "doors": [-0.7, 0.3, 1.15], "handles": [-0.45, 0.55], "mirror_z": -0.92, "mirror_y": 1.1, "lamp_y": 0.74}
		_:
			return {"top": [Vector2(-2.36, 0.85), Vector2(-2.2, 1.1), Vector2(-1.55, 1.3), Vector2(-1.05, 2.0), Vector2(2.25, 2.05),
					Vector2(2.4, 1.1)],
				"low_w": 0.98, "cabin_w": 0.95, "belt": 1.3, "roof": 2.05, "yb": 0.42, "tip": 0.14,
				"wheels": [-1.55, 1.6], "wind_f": Vector2(-1.55, -1.05), "wind_r": Vector2(9.0, 9.1), "side_win": Vector2(-1.5, 0.3),
				"pillars": [-0.5], "doors": [-0.95, 0.4], "handles": [-0.7, 0.62], "mirror_z": -1.3, "mirror_y": 1.45, "lamp_y": 0.9}


static func body(kind: String) -> ArrayMesh:
	if cache.has(kind):
		return cache[kind]
	var m: ArrayMesh
	if kind == "sport" or kind == "sedan" or kind == "suv" or kind == "van":
		m = _loft(_spec(kind))
	else:
		# armoured SWAT truck: boxy on purpose
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		box(st, Vector3(0, 0.95, 0), Vector3(2.3, 0.9, 5.4), PAINT)
		box(st, Vector3(0, 1.85, -1.7), Vector3(2.2, 0.95, 1.7), PAINT)
		box(st, Vector3(0, 2.0, 0.95), Vector3(2.3, 1.25, 3.4), PAINT)
		box(st, Vector3(0, 1.95, -2.56), Vector3(1.9, 0.5, 0.04), GLASS)
		box(st, Vector3(1.11, 1.95, -1.75), Vector3(0.02, 0.45, 1.1), GLASS)
		box(st, Vector3(-1.11, 1.95, -1.75), Vector3(0.02, 0.45, 1.1), GLASS)
		box(st, Vector3(0, 0.75, -2.85), Vector3(2.4, 0.5, 0.25), TRIM)
		box(st, Vector3(0, 0.55, 0), Vector3(2.0, 0.2, 5.2), TRIM)
		m = st.commit()
	cache[kind] = m
	return m
