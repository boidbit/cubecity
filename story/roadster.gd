extends RefCounted
# Story lab: an open-top version of the player's car, so the two characters can be seen
# sitting in it. Built from the same helpers as the other car bodies (CarMesh), so the car
# shader, dents and paint colour work on it unchanged.

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
	# roll bars
	for x in [-0.5, 0.5]:
		CarMesh.box(st, Vector3(x, 1.4, 1.32), Vector3(0.1, 0.8, 0.1), CarMesh.TRIM)
	# low windscreen
	var a := Vector3(-0.8, 1.1, -0.5)
	var b := Vector3(0.8, 1.1, -0.5)
	var c := Vector3(0.8, 1.58, -0.08)
	var d := Vector3(-0.8, 1.58, -0.08)
	CarMesh._quad(st, a, b, c, d, Vector3(0, 0.7, -1.0), CarMesh.GLASS)
	CarMesh.box(st, Vector3(0, 1.6, -0.08), Vector3(1.66, 0.06, 0.06), CarMesh.TRIM)


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
