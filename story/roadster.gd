extends RefCounted
# Story lab: the couple's car. The body is built from the same helpers as the other car
# bodies (CarMesh), so the car shader, dents and paint colour work on it unchanged; on top
# sits a tall cabin (make_cabin) with a roof and clear glass all round, so the characters
# can be seen inside.

# Seat positions in car space (x right, z back; the car drives toward -z)
const SEAT_Y := 1.15
const SEAT_Z := 0.7
const SEAT_X := 0.42
const WHEEL_Y := 1.4
const WHEEL_Z := 0.15


static func mesh() -> ArrayMesh:
	var profile := [
		Vector3(-2.05, 0.32, 0.9), Vector3(-2.12, 0.56, 0.91), Vector3(-1.98, 0.74, 0.9), Vector3(-0.9, 0.88, 0.89),
		Vector3(-0.5, 0.98, 0.87), Vector3(1.5, 0.98, 0.87), Vector3(2.02, 0.92, 0.89), Vector3(2.1, 0.58, 0.91),
		Vector3(2.03, 0.32, 0.9)]
	return CarMesh._body(profile, [], [], [-1.3, 1.3], 0.89, 0.87, 0.88, 0.98,
		func(st: SurfaceTool): _cockpit(st))


static func _cockpit(st: SurfaceTool) -> void:
	# dark cockpit floor and dashboard
	CarMesh.box(st, Vector3(0, 0.995, 0.5), Vector3(1.5, 0.03, 1.9), CarMesh.TRIM)
	CarMesh.box(st, Vector3(0, 1.17, -0.42), Vector3(1.6, 0.3, 0.32), CarMesh.TRIM)
	# seats in the car colour
	for x in [-SEAT_X, SEAT_X]:
		CarMesh.box(st, Vector3(x, 1.07, SEAT_Z - 0.05), Vector3(0.52, 0.16, 0.62), CarMesh.PAINT)
		CarMesh.box(st, Vector3(x, 1.45, SEAT_Z + 0.33), Vector3(0.52, 0.8, 0.14), CarMesh.PAINT)
	# door rims and the rear deck
	for x in [-0.84, 0.84]:
		CarMesh.box(st, Vector3(x, 1.1, 0.4), Vector3(0.12, 0.26, 2.0), CarMesh.PAINT)
	CarMesh.box(st, Vector3(0, 1.1, 1.5), Vector3(1.7, 0.24, 0.1), CarMesh.PAINT)


# The cabin: pillars and a roof in the car's colour, clear tinted glass between them.
const ROOF_Y := 2.32
const CAB_FRONT := -0.62     # bottom of the windscreen
const CAB_TOP_FRONT := 0.02  # top of the windscreen
const CAB_BACK := 1.42
const CAB_X := 0.86


static func make_cabin(parent: Node3D, color: Color) -> Node3D:
	var cab := Node3D.new()
	cab.name = "cabin"
	parent.add_child(cab)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.35
	paint.metallic_specular = 0.7
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.08, 0.08, 0.1)
	var y0 := 0.98
	# roof
	_part(cab, Vector3(CAB_X * 2.0 + 0.08, 0.1, CAB_BACK - CAB_TOP_FRONT + 0.1), Vector3(0, ROOF_Y, (CAB_BACK + CAB_TOP_FRONT) * 0.5), paint)
	# pillars: front ones lean back along the windscreen, middle and back ones stand straight
	for x in [-CAB_X, CAB_X]:
		var lo := Vector3(x, y0 + 0.1, CAB_FRONT)
		var hi := Vector3(x, ROOF_Y, CAB_TOP_FRONT)
		var mid := (lo + hi) * 0.5
		var pillar := _part(cab, Vector3(0.09, lo.distance_to(hi), 0.09), mid, paint)
		pillar.rotation.x = -atan2(hi.z - lo.z, hi.y - lo.y)
		_part(cab, Vector3(0.09, ROOF_Y - y0, 0.12), Vector3(x, (ROOF_Y + y0) * 0.5, 1.02), paint)
		_part(cab, Vector3(0.09, ROOF_Y - y0, 0.14), Vector3(x, (ROOF_Y + y0) * 0.5, CAB_BACK), paint)
		_part(cab, Vector3(0.05, 0.05, CAB_BACK - CAB_FRONT), Vector3(x, y0 + 0.1, (CAB_BACK + CAB_FRONT) * 0.5), trim)
	# glass, both sides drawn
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.72, 0.86, 1.0, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fl := Vector3(-CAB_X, y0 + 0.1, CAB_FRONT)
	var fr := Vector3(CAB_X, y0 + 0.1, CAB_FRONT)
	var tl := Vector3(-CAB_X, ROOF_Y, CAB_TOP_FRONT)
	var tr := Vector3(CAB_X, ROOF_Y, CAB_TOP_FRONT)
	_tri_quad(st, fl, fr, tr, tl)                                        # windscreen
	for x in [-CAB_X, CAB_X]:
		var a := Vector3(x, y0 + 0.1, CAB_FRONT)
		var b := Vector3(x, y0 + 0.1, CAB_BACK)
		var c := Vector3(x, ROOF_Y, CAB_BACK)
		var d := Vector3(x, ROOF_Y, CAB_TOP_FRONT)
		_tri_quad(st, a, b, c, d)                                        # side windows
	_tri_quad(st, Vector3(-CAB_X, y0 + 0.1, CAB_BACK), Vector3(CAB_X, y0 + 0.1, CAB_BACK),
		Vector3(CAB_X, ROOF_Y, CAB_BACK), Vector3(-CAB_X, ROOF_Y, CAB_BACK))  # rear window
	st.generate_normals()
	var gm := MeshInstance3D.new()
	gm.mesh = st.commit()
	gm.material_override = glass
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cab.add_child(gm)
	return cab


static func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _tri_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


# A steering wheel: a ring on a tilted pivot. Returns the node to spin.
static func make_wheel(parent: Node3D, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, WHEEL_Y, WHEEL_Z)
	pivot.rotation_degrees = Vector3(70, 0, 0)
	parent.add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.1)
	mat.roughness = 0.6
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.23
	tm.rings = 16
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = mat
	spin.add_child(ring)
	var spoke := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.03, 0.06)
	spoke.mesh = bm
	spoke.material_override = mat
	spin.add_child(spoke)
	return spin
