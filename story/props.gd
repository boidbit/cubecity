extends RefCounted
# Story lab: small things the characters have in the car (a pizza box, flowers, a gift ...).
# Built from boxes like everything else. A prop sits on the dashboard; fly() throws it out
# of the car as a little physics body (the pizza flying off on a jump).

const KINDS := ["pizza", "flowers", "gift", "ring", "teddy", "icecream", "chai"]
# where props sit in car space (first on the passenger side of the dashboard, then the
# driver side, then the rear deck)
const SLOTS := [Vector3(-0.42, 1.36, -0.46), Vector3(0.05, 1.36, -0.46), Vector3(0.0, 1.06, 1.42)]


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)


static func build(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"pizza":
			# cardboard box with a red and white check on the lid
			_box(n, Vector3(0.46, 0.07, 0.42), Vector3.ZERO, Color(0.85, 0.68, 0.42))
			for i in 3:
				for j in 3:
					var c := Color(0.85, 0.12, 0.1) if (i + j) % 2 == 0 else Color(0.97, 0.95, 0.9)
					_box(n, Vector3(0.1, 0.012, 0.1), Vector3((i - 1) * 0.1, 0.04, (j - 1) * 0.1), c)
		"flowers":
			for i in 3:
				var x := (i - 1) * 0.07
				_box(n, Vector3(0.025, 0.3, 0.025), Vector3(x, 0.15, 0), Color(0.2, 0.55, 0.2))
				_box(n, Vector3(0.1, 0.1, 0.1), Vector3(x, 0.33, 0), [Color(1, 0.2, 0.4), Color(1, 0.55, 0.75), Color(1, 0.3, 0.3)][i])
			_box(n, Vector3(0.16, 0.12, 0.08), Vector3(0, 0.08, 0), Color(1, 0.95, 0.9))
		"gift":
			_box(n, Vector3(0.3, 0.24, 0.3), Vector3(0, 0.12, 0), Color(0.85, 0.12, 0.25))
			_box(n, Vector3(0.06, 0.25, 0.31), Vector3(0, 0.12, 0), Color(1, 0.85, 0.2))
			_box(n, Vector3(0.31, 0.25, 0.06), Vector3(0, 0.12, 0), Color(1, 0.85, 0.2))
			_box(n, Vector3(0.14, 0.06, 0.14), Vector3(0, 0.27, 0), Color(1, 0.85, 0.2))
		"ring":
			_box(n, Vector3(0.14, 0.1, 0.14), Vector3(0, 0.05, 0), Color(0.5, 0.05, 0.12))
			_box(n, Vector3(0.08, 0.05, 0.02), Vector3(0, 0.12, 0), Color(1, 0.85, 0.3))
			_box(n, Vector3(0.04, 0.04, 0.04), Vector3(0, 0.16, 0), Color(0.75, 0.95, 1.0))
		"teddy":
			var fur := Color(0.62, 0.4, 0.22)
			_box(n, Vector3(0.26, 0.26, 0.2), Vector3(0, 0.13, 0), fur)
			_box(n, Vector3(0.22, 0.2, 0.2), Vector3(0, 0.36, 0), fur)
			for s in [-1.0, 1.0]:
				_box(n, Vector3(0.07, 0.07, 0.05), Vector3(s * 0.09, 0.48, 0), fur)
			_box(n, Vector3(0.08, 0.05, 0.03), Vector3(0, 0.33, -0.11), Color(0.9, 0.8, 0.65))
		"icecream":
			# a cone with two scoops and a cherry
			_box(n, Vector3(0.08, 0.18, 0.08), Vector3(0, 0.09, 0), Color(0.85, 0.62, 0.35))
			_box(n, Vector3(0.13, 0.1, 0.13), Vector3(0, 0.22, 0), Color(1.0, 0.62, 0.78))
			_box(n, Vector3(0.11, 0.09, 0.11), Vector3(0, 0.31, 0), Color(0.98, 0.94, 0.8))
			_box(n, Vector3(0.04, 0.04, 0.04), Vector3(0, 0.38, 0), Color(0.85, 0.08, 0.12))
		"chai":
			# a small glass of cutting chai
			_box(n, Vector3(0.09, 0.1, 0.09), Vector3(0, 0.05, 0), Color(0.72, 0.45, 0.22))
			_box(n, Vector3(0.1, 0.03, 0.1), Vector3(0, 0.11, 0), Color(0.9, 0.94, 0.97))
	return n


# Throws the prop out of the car: up, a little behind, spinning. Returns the body.
static func fly(prop: Node3D, car: Car) -> RigidBody3D:
	var xf := prop.global_transform
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 2.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 0.15, 0.4)
	cs.shape = bs
	body.add_child(cs)
	car.main.add_child(body)
	body.global_transform = xf
	prop.get_parent().remove_child(prop)
	body.add_child(prop)
	prop.transform = Transform3D.IDENTITY
	var v := car.linear_velocity
	body.linear_velocity = Vector3(v.x * 0.55, maxf(v.y, 0.0) + 7.5, v.z * 0.55) + car.global_transform.basis.x * randf_range(-1.5, 1.5)
	body.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
	return body
