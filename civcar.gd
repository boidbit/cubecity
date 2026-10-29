class_name CivCar
extends RigidBody3D
# Parked cars and traffic. Traffic drives kinematically along the left lane of the
# road grid; the moment the player (or police) gets close it becomes a real
# physics body so the crash is physical. Enough damage makes it explode.

const COLORS := [Color(0.85, 0.85, 0.82), Color(0.1, 0.1, 0.12), Color(0.55, 0.57, 0.6), Color(0.15, 0.25, 0.55),
	Color(0.6, 0.12, 0.1), Color(0.85, 0.7, 0.2), Color(0.2, 0.42, 0.3), Color(0.9, 0.45, 0.15)]

var main
var hp := 45.0
var dead := false
var moving := false
var mat: ShaderMaterial
var fire_p: CPUParticles3D
var prop_ref = null
var dir := Vector3(0, 0, -1)
var node := Vector2i.ZERO
var target := Vector3.ZERO
var cruise := 11.0
var yaw := 0.0
var last_v := Vector3.ZERO


static func palette(i: int) -> Color:
	return COLORS[i % COLORS.size()]


func build(m, color: Color, traffic: bool) -> void:
	main = m
	mass = 1000.0
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	angular_damp = 0.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.82, 1.0, 4.1)
	cs.shape = bs
	cs.position = Vector3(0, 0.65, 0)
	add_child(cs)
	mat = ShaderMaterial.new()
	mat.shader = Shaders.get_shader(Shaders.CAR)
	mat.set_shader_parameter("color", color)
	var bmi := MeshInstance3D.new()
	bmi.mesh = CarMesh.body("sedan")
	bmi.material_override = mat
	bmi.position = Vector3(0, -0.15, 0)
	add_child(bmi)
	var tire := CylinderMesh.new()
	tire.top_radius = 0.38
	tire.bottom_radius = 0.38
	tire.height = 0.28
	tire.radial_segments = 10
	tire.rings = 1
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.05, 0.05, 0.05)
	tire.material = tm
	for x in [-0.84, 0.84]:
		for z in [-1.3, 1.3]:
			var w := MeshInstance3D.new()
			w.mesh = tire
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(x, 0.24, z)
			add_child(w)
	add_to_group("loose")
	if traffic:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		moving = true
	else:
		can_sleep = true
		sleeping = true


func start_route(pos: Vector3, d: Vector3) -> void:
	dir = d
	var w = main.world
	var half: float = World.HALF
	var pitch: float = World.PITCH
	if absf(d.z) > 0.5:
		var i := clampi(roundi((pos.x + half) / pitch), 0, World.N)
		var j := int(floor((pos.z + half) / pitch)) if d.z < 0.0 else int(ceil((pos.z + half) / pitch))
		node = Vector2i(i, clampi(j, 0, World.N))
		pos.x = w.line(i)
	else:
		var j2 := clampi(roundi((pos.z + half) / pitch), 0, World.N)
		var i2 := int(floor((pos.x + half) / pitch)) if d.x < 0.0 else int(ceil((pos.x + half) / pitch))
		node = Vector2i(clampi(i2, 0, World.N), j2)
		pos.z = w.line(j2)
	var left := Vector3.UP.cross(dir)
	pos += left * 3.5
	yaw = atan2(-dir.x, -dir.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.15, pos.z))
	_set_target()


func _set_target() -> void:
	var left := Vector3.UP.cross(dir)
	target = main.world.node_pos(node) + left * 3.5
	target.y = 0.15


func _next_dir() -> void:
	var opts := []
	var right := dir.cross(Vector3.UP)
	var left := -right
	for c in [[dir, 0.6], [left, 0.2], [right, 0.2]]:
		var dv: Vector3 = c[0]
		var nn := node + Vector2i(roundi(dv.x), roundi(dv.z))
		if nn.x >= 0 and nn.y >= 0 and nn.x <= World.N and nn.y <= World.N:
			opts.append([dv, nn, c[1]])
	if opts.is_empty():
		dir = -dir
		node = node + Vector2i(roundi(dir.x), roundi(dir.z))
		return
	var r := randf() * 1.0
	var pick = opts[0]
	var acc := 0.0
	for o in opts:
		acc += o[2]
		if r <= acc:
			pick = o
			break
	dir = pick[0]
	node = pick[1]


func knock(v: Vector3) -> void:
	if freeze:
		freeze = false
		moving = false
		linear_velocity = v
		last_v = v


func hurt(a: float) -> void:
	if dead:
		return
	hp -= a
	mat.set_shader_parameter("damage", clampf(1.0 - hp / 45.0, 0.0, 1.0))
	if hp <= 0.0:
		dead = true
		if prop_ref != null:
			prop_ref["alive"] = false
		knock(Vector3.ZERO)
		fire_p = main.fx.make_fire()
		fire_p.position = Vector3(0, 1.0, 0)
		add_child(fire_p)
		fire_p.emitting = true
		var sm: CPUParticles3D = main.fx.make_smoke()
		sm.position = Vector3(0, 1.2, 0)
		add_child(sm)
		sm.emitting = true
		main.explode_at.call_deferred(global_position + Vector3(0, 0.8, 0), 6.5, 16.0, 30.0)
		main.on_civ_wreck(self)


func _physics_process(delta: float) -> void:
	if moving:
		var p := global_position
		var to := target - p
		to.y = 0.0
		var step := cruise * delta
		if to.length() < maxf(step, 1.0):
			_next_dir()
			_set_target()
			to = target - p
			to.y = 0.0
		var mv := to.normalized() * minf(step, to.length())
		var want := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want, minf(1.0, 7.0 * delta))
		global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x + mv.x, 0.15, p.z + mv.z))
		# become physical right before something hits us
		for c in main.cars_near(global_position, 7.0):
			var rel: Vector3 = c.linear_velocity - to.normalized() * cruise
			var toc: Vector3 = global_position - c.global_position
			if rel.dot(toc) > 1.0 and toc.length() < 5.5 + c.speed * 0.05:
				knock(to.normalized() * cruise)
				break
	elif not freeze:
		var dv := (linear_velocity - last_v).length()
		if dv > 7.0:
			hurt((dv - 7.0) * 3.5)
		last_v = linear_velocity
