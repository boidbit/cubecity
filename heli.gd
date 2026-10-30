class_name Heli
extends Node3D
# The police helicopter. In normal play it circles high above (26 m). In recorded
# runs ("low") it chases down the street at rooftop-gap height, kicking up dust, and
# the director can stage an intercept: it hovers where the bot's jump will pass, the
# car flies into it, and it spins down and explodes.
#
# States: chase (follow the car), intercept (fly to a point and wait for the car),
# crash (falling), wreck (burning on the ground).

const CHOP_DB_REC := 6.0       # the recorded rotor loop is mastered quieter than the synthesized one
const CHOP_DB_SYNTH := -3.0

var main
var low := false              # recorded runs: chase at street level instead of high above
var down := false             # shot down: it does not come back
var state := "chase"
var t := 0.0
var rotor: Node3D
var tail_rotor: Node3D
var spot: SpotLight3D
var chop: AudioStreamPlayer3D
var nav_a: StandardMaterial3D
var nav_b: StandardMaterial3D
var fire: CPUParticles3D
var smoke: CPUParticles3D
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var target := Vector3.ZERO
var face := Vector3(0, 0, -1)
var intercept_until := 0.0
var wash_t := 0.0
var wreck_t := 0.0
var last_pos := Vector3.ZERO
var parts: Array[Node3D] = []


func setup(main_node) -> void:
	main = main_node
	_build()
	visible = false


func _mat(c: Color, metal: float = 0.3, rough: float = 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	(parent if parent != null else self).add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _part(bm, pos, mat, rot, parent)


func _build() -> void:
	var navy := _mat(Color(0.07, 0.09, 0.16), 0.5, 0.4)
	var white := _mat(Color(0.92, 0.93, 0.96), 0.2, 0.5)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.4, 0.5)
	var glass := _mat(Color(0.12, 0.2, 0.3), 0.9, 0.1)
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.25, 0.4)
	glass.emission_energy_multiplier = 0.4
	# cabin and cockpit
	var cab := CapsuleMesh.new()
	cab.radius = 1.0
	cab.height = 3.8
	_part(cab, Vector3.ZERO, navy, Vector3(90, 0, 0))
	var ck := SphereMesh.new()
	ck.radius = 0.95
	ck.height = 1.9
	var cockpit := _part(ck, Vector3(0, 0.2, -1.4), glass)
	cockpit.scale = Vector3(1.0, 0.85, 1.25)
	_box(Vector3(2.04, 0.2, 2.6), Vector3(0, -0.2, 0.5), white)
	# tail
	var boom := CylinderMesh.new()
	boom.top_radius = 0.17
	boom.bottom_radius = 0.3
	boom.height = 5.4
	_part(boom, Vector3(0, 0.25, 4.1), navy, Vector3(90, 0, 0))
	_box(Vector3(0.12, 1.3, 0.9), Vector3(0, 0.85, 6.5), navy)
	_box(Vector3(1.6, 0.08, 0.5), Vector3(0, 0.35, 6.2), navy)
	tail_rotor = Node3D.new()
	tail_rotor.position = Vector3(0.22, 0.9, 6.55)
	add_child(tail_rotor)
	_box(Vector3(0.05, 1.1, 0.12), Vector3.ZERO, dark, Vector3.ZERO, tail_rotor)
	_box(Vector3(0.05, 0.12, 1.1), Vector3.ZERO, dark, Vector3.ZERO, tail_rotor)
	# skids
	for sx in [-0.95, 0.95]:
		_box(Vector3(0.12, 0.1, 3.4), Vector3(sx, -1.4, 0.2), dark)
		for sz in [-0.7, 1.1]:
			_box(Vector3(0.08, 0.6, 0.08), Vector3(sx * 0.95, -1.1, sz), dark)
	# rotor: mast, four blades and a faint disc for the blur
	_part(_cyl(0.12, 0.6), Vector3(0, 1.3, 0), dark)
	rotor = Node3D.new()
	rotor.position = Vector3(0, 1.62, 0)
	add_child(rotor)
	for a in [0.0, 45.0, 90.0, 135.0]:
		_box(Vector3(5.6, 0.04, 0.26), Vector3.ZERO, dark, Vector3(0, a, 0), rotor)
	var disc := CylinderMesh.new()
	disc.top_radius = 5.4
	disc.bottom_radius = 5.4
	disc.height = 0.02
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.7, 0.75, 0.8, 0.1)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dmi := _part(disc, Vector3.ZERO, dm, Vector3.ZERO, rotor)
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# lights: searchlight, red tail light and a white belly strobe
	spot = SpotLight3D.new()
	spot.spot_range = 90.0
	spot.spot_angle = 14.0
	spot.light_energy = 6.0
	spot.position = Vector3(0, -0.9, -0.8)
	add_child(spot)
	nav_a = _glow_mat(Color(1.0, 0.1, 0.1))
	nav_b = _glow_mat(Color(1.0, 1.0, 1.0))
	_part(_sphere(0.14), Vector3(0, 1.3, 6.6), nav_a)
	_part(_sphere(0.16), Vector3(0, -1.0, 1.4), nav_b)
	chop = AudioStreamPlayer3D.new()
	chop.stream = main.fx.stream_for("heli_loop", "chop")
	chop.unit_size = 22.0
	chop.max_distance = 260.0
	chop.volume_db = CHOP_DB_REC if main.fx.has_bank("heli_loop") else CHOP_DB_SYNTH
	chop.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(chop)
	fire = main.fx.make_fire()
	fire.amount = 24
	fire.position = Vector3(0, 0.4, 2.0)
	add_child(fire)
	smoke = main.fx.make_smoke()
	smoke.position = Vector3(0, 0.6, 2.0)
	add_child(smoke)


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


# Appear off to one side of the player and fly in.
func summon() -> void:
	var pl: Car = main.player
	var side := Vector3(1, 0, 1) if not low else Vector3(0.6, 0, 0.8)
	global_position = pl.global_position + side * (120.0 if not low else 90.0) + Vector3(0, 40.0 if not low else 22.0, 0)
	last_pos = global_position
	visible = true
	state = "chase"
	chop.play()


func start_intercept(point: Vector3, facing: Vector3, secs: float) -> void:
	if state == "crash" or state == "wreck":
		return
	state = "intercept"
	main.log_event("heli_intercept")
	target = point
	face = Vector3(facing.x, 0, facing.z).normalized()
	intercept_until = main.clock + secs


# Aim the waiting helicopter at the point the car will actually reach.
func retune_intercept(point: Vector3, secs: float) -> void:
	if state == "intercept":
		main.log_event("heli_aim")
		target = point
		intercept_until = main.clock + secs


func tick(dt: float) -> void:
	t += dt
	rotor.rotate_y(dt * (38.0 if state != "crash" else 14.0))
	tail_rotor.rotate_x(dt * 50.0)
	var blink := fmod(t * 1.6, 1.0)
	nav_a.emission_energy_multiplier = 4.0 if blink < 0.2 else 0.3
	nav_b.emission_energy_multiplier = 5.0 if fmod(t * 2.5, 1.0) < 0.08 else 0.2
	match state:
		"chase":
			_chase(dt)
		"intercept":
			_intercept(dt)
		"crash":
			_crash_tick(dt)
		"wreck":
			wreck_t -= dt
			if wreck_t <= 0.0:
				visible = false
				down = true
				fire.emitting = false
				smoke.emitting = false
	# the rotor note rises a little when it flies hard
	var spd := (global_position - last_pos).length() / maxf(dt, 0.001)
	chop.pitch_scale = lerpf(chop.pitch_scale, 0.95 + clampf(spd / 45.0, 0.0, 0.2), minf(4.0 * dt, 1.0))
	last_pos = global_position


func _flat_fwd() -> Vector3:
	var pl: Car = main.player
	var v := Vector3(pl.linear_velocity.x, 0, pl.linear_velocity.z)
	if v.length() > 6.0:
		return v.normalized()
	var f := -pl.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _chase(dt: float) -> void:
	var pl: Car = main.player
	var goal: Vector3
	var rate := 0.9
	if low:
		var fwd := _flat_fwd()
		var side := fwd.cross(Vector3.UP)
		goal = pl.global_position - fwd * 16.0 + side * sin(t * 0.45) * 5.0 + Vector3(0, 10.0 + sin(t * 0.9) * 1.2, 0)
		goal += Vector3(pl.linear_velocity.x, 0, pl.linear_velocity.z) * 0.3
		rate = 1.8
	else:
		goal = pl.global_position + pl.linear_velocity * 0.9 + Vector3(sin(t * 0.4) * 14.0, 26.0, cos(t * 0.4) * 14.0)
	global_position = global_position.lerp(goal, 1.0 - exp(-rate * dt))
	var look := pl.global_position - global_position
	look.y = 0.0
	if look.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), 2.5 * dt)
	var hv := (global_position - last_pos) / maxf(dt, 0.001)
	hv.y = 0.0
	rotation.x = lerpf(rotation.x, -clampf(hv.length() * 0.012, 0.0, 0.3), 3.0 * dt)
	spot.look_at(pl.global_position, Vector3.UP)
	_wash(dt)


func _intercept(dt: float) -> void:
	var pl: Car = main.player
	global_position = global_position.lerp(target, 1.0 - exp(-4.5 * dt))
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 4.0 * dt)
	rotation.x = lerpf(rotation.x, 0.0, 3.0 * dt)
	spot.look_at(pl.global_position, Vector3.UP)
	_wash(dt)
	# the car is in the air and has reached the helicopter
	var hit := global_position + Vector3(0, -1.1, 0)
	if pl.airtime > 0.1 and pl.global_position.distance_to(hit) < 4.6:
		_shot_down()
	elif main.clock > intercept_until:
		main.log_event("heli_miss")
		state = "chase"      # missed: carry on chasing


func _wash(dt: float) -> void:
	wash_t -= dt
	if wash_t <= 0.0 and global_position.y < 24.0:
		wash_t = 0.1
		main.fx.tire_smoke(Vector3(global_position.x, 0.05, global_position.z))


func _shot_down() -> void:
	state = "crash"
	var pl: Car = main.player
	vel = pl.linear_velocity * 0.45 + Vector3(randf_range(-3, 3), 2.0, randf_range(-3, 3))
	spin = Vector3(randf_range(-2.0, 2.0), 9.0 * (1.0 if randf() < 0.5 else -1.0), randf_range(-3.0, 3.0))
	fire.emitting = true
	smoke.emitting = true
	spot.visible = false
	chop.stop()
	main.fx.explosion(global_position, 5.0)
	main.fx.play("explosion", global_position, 4.0)
	main.fx.boom(global_position, 10.0)
	main.shake_cam(1.0)
	main.bonus += 1000
	main.stats["heli_down"] += 1
	main.log_event("heli_down")
	main.hud.banner("HELICOPTER DOWN +1000")
	main.slowmo(2.2, 0.3)
	# rotor blades fly off
	for k in 3:
		var rb := RigidBody3D.new()
		rb.mass = 20.0
		rb.collision_layer = 4
		rb.collision_mask = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.0, 0.1, 0.3)
		cs.shape = bs
		rb.add_child(cs)
		_box(Vector3(4.0, 0.05, 0.26), Vector3.ZERO, _mat(Color(0.05, 0.05, 0.06)), Vector3.ZERO, rb)
		main.world.debris_root.add_child(rb)
		rb.global_position = rotor.global_position + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1))
		rb.linear_velocity = Vector3(randf_range(-14, 14), randf_range(4, 12), randf_range(-14, 14))
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		main.get_tree().create_timer(7.0).timeout.connect(rb.queue_free)


func _crash_tick(dt: float) -> void:
	vel.y -= 20.0 * dt
	var from := global_position
	global_position += vel * dt
	rotation += spin * dt
	# trail of smoke and sparks while it falls
	if randf() < 0.3:
		main.fx.sparks(global_position, 6)
	var q := PhysicsRayQueryParameters3D.create(from, global_position + vel.normalized() * 1.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if global_position.y < 1.2 or not hit.is_empty():
		_impact()


func _impact() -> void:
	state = "wreck"
	wreck_t = 7.0
	var p := global_position
	main.explode_at(p + Vector3(0, 0.5, 0), 10.0, 26.0, 40.0, false, 1.4)
	for i in 10:
		main.world.spawn_debris(p + Vector3(randf_range(-2, 2), 1.0, randf_range(-2, 2)),
			Vector3(randf_range(-9, 9), randf_range(3, 12), randf_range(-9, 9)),
			Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
	vel = Vector3.ZERO
	spin = Vector3.ZERO
	global_position.y = maxf(global_position.y, 0.6)
	rotation = Vector3(randf_range(-0.3, 0.3), rotation.y, randf_range(0.5, 1.2))
	rotor.visible = false
