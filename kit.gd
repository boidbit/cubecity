class_name Kit
extends RefCounted
# The asset kit: reusable, hand-built parts made in code (no downloads, no third-party
# packs), so a new vehicle or prop starts from good pieces instead of from scratch.
# Everything here is cached: the first call builds the mesh, every later call reuses it.
#
#   Kit.wheel(radius, width)   a rounded tyre with a five-spoke rim, as a ready MeshInstance3D
#   Kit.lathe(profile, seg)    a surface of revolution (tyres, lamps, domes, columns ...)
#   Kit.smooth_cells(...)      smooth-shading helper used by the car bodies (see carmesh.gd)
#
# Car bodies live in carmesh.gd, buildings in building.gd / landmarks.gd, props in props.gd.

static var _wheel_cache := {}
static var _wheel_mat: StandardMaterial3D


static func wheel_material() -> StandardMaterial3D:
	if _wheel_mat == null:
		_wheel_mat = StandardMaterial3D.new()
		_wheel_mat.vertex_color_use_as_albedo = true
		_wheel_mat.roughness = 0.75
		_wheel_mat.metallic = 0.05
		_wheel_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _wheel_mat


# Appends a surface of revolution around the Y axis. profile: Vector2(radius, y) from bottom
# to top. Normals follow the profile, so a rounded profile gives a smooth tyre.
static func lathe(st: SurfaceTool, profile: Array, seg: int, col: Color, center: Vector3 = Vector3.ZERO) -> void:
	var n := profile.size()
	for i in n - 1:
		var p: Vector2 = profile[i]
		var q: Vector2 = profile[i + 1]
		var t := (q - p)
		var nn := Vector2(t.y, -t.x).normalized()      # outward normal in the (radius, y) plane
		var pn := nn
		var qn := nn
		if i > 0:
			var t0: Vector2 = (p - (profile[i - 1] as Vector2))
			pn = (nn + Vector2(t0.y, -t0.x).normalized()).normalized()
		if i < n - 2:
			var t1: Vector2 = ((profile[i + 2] as Vector2) - q)
			qn = (nn + Vector2(t1.y, -t1.x).normalized()).normalized()
		for s in seg:
			var a0 := TAU * float(s) / float(seg)
			var a1 := TAU * float(s + 1) / float(seg)
			var c0 := Vector2(cos(a0), sin(a0))
			var c1 := Vector2(cos(a1), sin(a1))
			var v00 := center + Vector3(c0.x * p.x, p.y, c0.y * p.x)
			var v01 := center + Vector3(c1.x * p.x, p.y, c1.y * p.x)
			var v10 := center + Vector3(c0.x * q.x, q.y, c0.y * q.x)
			var v11 := center + Vector3(c1.x * q.x, q.y, c1.y * q.x)
			var n00 := Vector3(c0.x * pn.x, pn.y, c0.y * pn.x)
			var n01 := Vector3(c1.x * pn.x, pn.y, c1.y * pn.x)
			var n10 := Vector3(c0.x * qn.x, qn.y, c0.y * qn.x)
			var n11 := Vector3(c1.x * qn.x, qn.y, c1.y * qn.x)
			for tri: Array in [[v00, v10, v11, n00, n10, n11], [v00, v11, v01, n00, n11, n01]]:
				for k in 3:
					st.set_normal(tri[3 + k])
					st.set_color(col)
					st.add_vertex(tri[k])


static func _flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


# A tyre (rounded shoulders) with a five-spoke rim on both faces, axis along X.
static func wheel(r: float, w: float) -> MeshInstance3D:
	var key := "%d_%d" % [int(r * 100.0), int(w * 100.0)]
	if not _wheel_cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hw := w * 0.5
		var tire := Color(0.045, 0.045, 0.05)
		# inner wall, rounded shoulder, tread, shoulder, outer wall
		var prof := [Vector2(r * 0.62, -hw), Vector2(r * 0.86, -hw * 0.98), Vector2(r * 0.96, -hw * 0.82),
			Vector2(r, -hw * 0.45), Vector2(r, hw * 0.45), Vector2(r * 0.96, hw * 0.82),
			Vector2(r * 0.86, hw * 0.98), Vector2(r * 0.62, hw)]
		lathe(st, prof, 18, tire)
		# rim: a dark dish, a silver ring, five spokes and a hub, on each face
		var silver := Color(0.82, 0.83, 0.87)
		var dark := Color(0.12, 0.12, 0.14)
		for side in [-1.0, 1.0]:
			var y: float = side * (hw * 0.99)
			var out := Vector3(0, side, 0)
			var seg := 20
			for s in seg:
				var a0 := TAU * float(s) / float(seg)
				var a1 := TAU * float(s + 1) / float(seg)
				var d0 := Vector3(cos(a0), 0, sin(a0))
				var d1 := Vector3(cos(a1), 0, sin(a1))
				var spoke := int(float(s) / 2.0) % 2 == 0     # alternate: spoke / gap, 5 of each
				var ci := Vector3(0, y, 0)
				_flat_tri(st, ci + d0 * r * 0.58, ci + d1 * r * 0.58, ci + d1 * r * 0.5, out, silver)
				_flat_tri(st, ci + d0 * r * 0.58, ci + d1 * r * 0.5, ci + d0 * r * 0.5, out, silver)
				_flat_tri(st, ci + d0 * r * 0.5, ci + d1 * r * 0.5, ci + d1 * r * 0.16, out, silver if spoke else dark)
				_flat_tri(st, ci + d0 * r * 0.5, ci + d1 * r * 0.16, ci + d0 * r * 0.16, out, silver if spoke else dark)
				_flat_tri(st, ci + d0 * r * 0.16, ci + d1 * r * 0.16, ci, out, Color(0.3, 0.3, 0.33))
		var m := st.commit()
		m.surface_set_material(0, wheel_material())
		# the lathe axis is Y; cars want it along X
		_wheel_cache[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _wheel_cache[key]
	mi.rotation_degrees = Vector3(0, 0, 90)
	return mi
