class_name CarMesh
extends RefCounted
# Builds car bodies from a side profile: sloped hood, windscreen, roof, rear glass,
# narrower cabin (tumblehome), side windows and dark wheel arches. Vertex colour alpha
# tells the car shader what a surface is: 0 = paint, 0.5 = black trim, 1 = glass.

const PAINT := Color(1, 1, 1, 0.0)
const TRIM := Color(0.04, 0.04, 0.05, 0.5)
const GLASS := Color(0.05, 0.08, 0.12, 1.0)

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


static func body(kind: String) -> ArrayMesh:
	if cache.has(kind):
		return cache[kind]
	var m: ArrayMesh
	if kind == "sport":
		m = _body([
			Vector3(-2.05, 0.32, 0.9), Vector3(-2.12, 0.56, 0.91), Vector3(-1.98, 0.74, 0.9), Vector3(-0.8, 0.86, 0.89),
			Vector3(-0.15, 1.26, 0.7), Vector3(0.7, 1.28, 0.7), Vector3(1.45, 0.97, 0.86), Vector3(2.02, 0.92, 0.89),
			Vector3(2.1, 0.58, 0.91), Vector3(2.03, 0.32, 0.9)],
			[3, 5],
			[Vector2(-0.7, 0.92), Vector2(-0.18, 1.21), Vector2(0.68, 1.23), Vector2(1.36, 0.98)],
			[-1.3, 1.3], 0.89, 0.7, 0.86, 1.28,
			func(st: SurfaceTool):
				box(st, Vector3(0, 0.48, -2.13), Vector3(0.95, 0.16, 0.04), TRIM)
				box(st, Vector3(0, 0.3, 0), Vector3(1.7, 0.08, 3.9), TRIM)
				box(st, Vector3(0, 1.0, 0.05), Vector3(1.66, 0.25, 0.08), PAINT))
	elif kind == "sedan":
		m = _body([
			Vector3(-2.1, 0.34, 0.92), Vector3(-2.15, 0.6, 0.93), Vector3(-2.0, 0.78, 0.92), Vector3(-0.95, 0.88, 0.91),
			Vector3(-0.35, 1.38, 0.74), Vector3(0.85, 1.4, 0.74), Vector3(1.35, 0.98, 0.9), Vector3(2.05, 0.94, 0.91),
			Vector3(2.12, 0.6, 0.93), Vector3(2.06, 0.34, 0.92)],
			[3, 5],
			[Vector2(-0.86, 0.94), Vector2(-0.37, 1.32), Vector2(0.84, 1.34), Vector2(1.26, 0.99)],
			[-1.3, 1.3], 0.91, 0.74, 0.88, 1.38,
			func(st: SurfaceTool):
				box(st, Vector3(0, 0.5, -2.16), Vector3(1.0, 0.18, 0.04), TRIM)
				box(st, Vector3(0, 0.32, 0), Vector3(1.75, 0.08, 4.0), TRIM)
				box(st, Vector3(0, 1.08, 0.24), Vector3(1.5, 0.3, 0.08), PAINT))
	elif kind == "suv":
		m = _body([
			Vector3(-2.15, 0.4, 0.95), Vector3(-2.2, 0.72, 0.96), Vector3(-2.05, 0.95, 0.95), Vector3(-0.95, 1.05, 0.94),
			Vector3(-0.45, 1.62, 0.8), Vector3(1.7, 1.66, 0.8), Vector3(2.1, 1.1, 0.93), Vector3(2.2, 0.98, 0.94),
			Vector3(2.22, 0.62, 0.96), Vector3(2.12, 0.4, 0.95)],
			[3, 5],
			[Vector2(-0.95, 1.08), Vector2(-0.5, 1.56), Vector2(1.6, 1.6), Vector2(1.95, 1.1)],
			[-1.4, 1.45], 0.94, 0.8, 1.0, 1.66,
			func(st: SurfaceTool):
				box(st, Vector3(0, 0.58, -2.23), Vector3(1.15, 0.22, 0.04), TRIM)
				box(st, Vector3(0, 0.38, 0), Vector3(1.85, 0.08, 4.3), TRIM)
				box(st, Vector3(0.62, 1.69, 0.5), Vector3(0.06, 0.05, 2.2), TRIM)
				box(st, Vector3(-0.62, 1.69, 0.5), Vector3(0.06, 0.05, 2.2), TRIM))
	elif kind == "van":
		m = _body([
			Vector3(-2.3, 0.42, 0.98), Vector3(-2.36, 0.85, 0.99), Vector3(-2.2, 1.1, 0.98), Vector3(-1.55, 1.3, 0.97),
			Vector3(-1.05, 2.0, 0.95), Vector3(2.25, 2.05, 0.95), Vector3(2.4, 1.1, 0.97), Vector3(2.38, 0.42, 0.98)],
			[3],
			[Vector2(-1.5, 1.34), Vector2(-1.1, 1.95), Vector2(0.3, 1.97), Vector2(0.3, 1.34)],
			[-1.55, 1.6], 0.98, 0.95, 1.3, 2.05,
			func(st: SurfaceTool):
				box(st, Vector3(0, 0.6, -2.38), Vector3(1.3, 0.24, 0.04), TRIM)
				box(st, Vector3(0, 0.4, 0), Vector3(1.9, 0.08, 4.6), TRIM))
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
