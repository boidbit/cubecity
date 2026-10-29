class_name Car
extends VehicleBody3D
# Player car, police cars and the SWAT truck. VehicleBody3D suspension and tyres,
# plus arcade assists for the player (yaw control, side grip, drift boost, nitro).

var main
var kind := "sport"
var is_player := false
var is_block := false
var is_swat := false
var hp := 100.0
var max_hp := 100.0
var dead := false
var input_gas := 0.0
var input_steer := 0.0
var input_hb := 0.0
var input_nitro := false
var engine_max := 3000.0
var vmax := 40.0
var grip_front := 2.2
var grip_rear := 2.0
var body_color := Color.RED
var dmg_scale := 1.0
var impact_threshold := 5.0

var fwd_speed := 0.0
var speed := 0.0
var hb_smooth := 0.0
var nitro := 40.0
var nitro_active := false
var drift_t := 0.0
var airtime := 0.0
var last_hurt := 0.0
var wheels: Array[VehicleWheel3D] = []
var parts: Array[MeshInstance3D] = []
var mat_body: ShaderMaterial
var dents: Array[Vector4] = [Vector4(), Vector4(), Vector4(), Vector4()]
var dent_i := 0
var last_vel := Vector3.ZERO
var impact_acc := 0.0
var impact_t := 0.0
var impact_dir := Vector3.ZERO
var flip_t := 0.0
var hit_cd := 0.0
var skid_prev: Array = [null, null, null, null]
var siren_a: StandardMaterial3D
var siren_b: StandardMaterial3D
var siren_light: OmniLight3D
var siren_t := 0.0
var head_lights: Array[SpotLight3D] = []
var smoke: CPUParticles3D
var fire: CPUParticles3D
var flame: CPUParticles3D

# ai
var target: Node3D = null
var stuck_t := 0.0
var reverse_t := 0.0
var pit_side := 1.0
var top_speed := 28.0
var path: Array[Vector3] = []
var path_t := 0.0


func build(color: Color, player: bool, k: String = "") -> void:
	is_player = player
	body_color = color
	kind = k if k != "" else ("sport" if player else "sedan")
	is_swat = kind == "swat"
	var swat := is_swat
	mass = 1100.0 if player else (3200.0 if swat else 1250.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25 if not swat else 0.1, 0.05)
	angular_damp = 0.8
	linear_damp = 0.02
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false

	if swat:
		_shape(Vector3(2.3, 1.0, 5.5), Vector3(0, 0.95, 0))
		_shape(Vector3(2.3, 1.3, 5.0), Vector3(0, 2.0, 0.2))
	else:
		_shape(Vector3(1.82, 0.62, 4.1), Vector3(0, 0.6, 0))
		_shape(Vector3(1.42, 0.45, 1.9), Vector3(0, 1.08, 0.25))

	var sh := Shader.new()
	sh.code = Shaders.CAR
	mat_body = ShaderMaterial.new()
	mat_body.shader = sh
	mat_body.set_shader_parameter("color", color)
	mat_body.set_shader_parameter("mesh_offset", Vector3.ZERO)
	mat_body.set_shader_parameter("dent_radius", 1.1 if not swat else 1.6)
	var bmi := MeshInstance3D.new()
	bmi.mesh = CarMesh.body(kind)
	bmi.material_override = mat_body
	add_child(bmi)

	var pcol := StandardMaterial3D.new()
	pcol.albedo_color = color
	pcol.metallic = 0.5
	pcol.roughness = 0.3
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.05, 0.05, 0.06)
	trim.roughness = 0.7
	var fz := -2.15 if not swat else -2.95
	var rz := 2.14 if not swat else 2.75
	_part(Vector3(1.9, 0.22, 0.16), Vector3(0, 0.42, fz), trim if not swat else pcol)
	_part(Vector3(1.9, 0.22, 0.16), Vector3(0, 0.42, rz), trim)
	if not swat:
		_part(Vector3(0.16, 0.1, 0.12), Vector3(-0.98, 0.96, -0.6), pcol)
		_part(Vector3(0.16, 0.1, 0.12), Vector3(0.98, 0.96, -0.6), pcol)
	if player:
		_part(Vector3(1.75, 0.06, 0.34), Vector3(0, 1.16, 1.88), trim)
		_part(Vector3(0.08, 0.2, 0.1), Vector3(-0.6, 1.03, 1.88), trim)
		_part(Vector3(0.08, 0.2, 0.1), Vector3(0.6, 1.03, 1.88), trim)

	var hw := 0.62 if not swat else 0.85
	var hy := 0.66 if not swat else 1.0
	for x in [-hw, hw]:
		_glow(Vector3(0.42, 0.12, 0.05), Vector3(x, hy, fz + 0.03), Color(1, 0.95, 0.8), 2.5)
		_glow(Vector3(0.4, 0.12, 0.05), Vector3(x, hy + 0.08, rz - 0.06), Color(1, 0.08, 0.08), 1.6)

	var wr := 0.4 if not swat else 0.56
	var wx := 0.86 if not swat else 1.06
	var wz := 1.3 if not swat else 1.85
	var wy := 0.58 if not swat else 0.85
	for pos in [Vector3(-wx, wy, -wz), Vector3(wx, wy, -wz), Vector3(-wx, wy, wz), Vector3(wx, wy, wz)]:
		var w := VehicleWheel3D.new()
		w.position = pos
		w.wheel_radius = wr
		w.wheel_rest_length = 0.2
		w.suspension_travel = 0.3
		w.suspension_stiffness = 100.0 if not swat else 120.0
		w.suspension_max_force = 30000.0 if not swat else 80000.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.1
		w.wheel_roll_influence = 0.1
		var front: bool = pos.z < 0.0
		w.use_as_steering = front
		w.use_as_traction = true
		w.wheel_friction_slip = grip_front if front else grip_rear
		_wheel_visual(w, wr)
		add_child(w)
		wheels.append(w)

	if player:
		for x in [-0.6, 0.6]:
			var sl := SpotLight3D.new()
			sl.position = Vector3(x, 0.75, -2.1)
			sl.spot_range = 45.0
			sl.spot_angle = 30.0
			sl.light_energy = 0.0
			add_child(sl)
			head_lights.append(sl)
		flame = main.fx.make_flame()
		flame.position = Vector3(0.45, 0.38, 2.2)
		add_child(flame)
	else:
		var ly := 1.48 if not swat else 2.7
		var lz := 0.25 if not swat else -1.0
		_part(Vector3(1.1, 0.1, 0.32), Vector3(0, ly - 0.08, lz), trim)
		siren_a = _glow(Vector3(0.48, 0.15, 0.28), Vector3(-0.3, ly, lz), Color(1, 0.1, 0.1), 3.0)
		siren_b = _glow(Vector3(0.48, 0.15, 0.28), Vector3(0.3, ly, lz), Color(0.2, 0.4, 1), 3.0)
		siren_light = OmniLight3D.new()
		siren_light.position = Vector3(0, ly + 0.5, lz)
		siren_light.omni_range = 12.0
		siren_light.light_energy = 2.5
		add_child(siren_light)
		if not swat:
			for s in [-1.0, 1.0]:
				_deco(Vector3(0.02, 0.26, 1.7), Vector3(s * 0.925, 0.62, 0.0), trim)

	smoke = main.fx.make_smoke()
	smoke.position = Vector3(0, 1.0, -1.3)
	add_child(smoke)
	fire = main.fx.make_fire()
	fire.position = Vector3(0, 1.0, -1.3)
	add_child(fire)


func _shape(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)


func _wheel_visual(w: VehicleWheel3D, r: float) -> void:
	var tire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.3
	cm.radial_segments = 16
	cm.rings = 1
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.04, 0.04, 0.045)
	tm.roughness = 0.85
	cm.material = tm
	tire.mesh = cm
	tire.rotation_degrees = Vector3(0, 0, 90)
	w.add_child(tire)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r * 0.66
	rm.bottom_radius = r * 0.66
	rm.height = 0.32
	rm.radial_segments = 14
	rm.rings = 1
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.75, 0.76, 0.8)
	mm.metallic = 0.9
	mm.roughness = 0.25
	rm.material = mm
	rim.mesh = rm
	rim.rotation_degrees = Vector3(0, 0, 90)
	w.add_child(rim)
	for a in [0.0, 60.0, 120.0]:
		var sp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, r * 1.25, 0.07)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.2, 0.2, 0.22)
		dm.metallic = 0.6
		bm.material = dm
		sp.mesh = bm
		sp.rotation_degrees = Vector3(a, 0, 0)
		w.add_child(sp)


func _deco(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _part(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	parts.append(mi)
	return mi


func _glow(size: Vector3, pos: Vector3, color: Color, energy: float) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return m


func set_headlights(night: float) -> void:
	for l in head_lights:
		l.light_energy = night * 6.0


func rpm() -> float:
	var s := absf(fwd_speed)
	var gear := mini(int(s / 8.5), 4)
	var frac := (s - gear * 8.5) / 8.5
	return 900.0 + frac * 4600.0 + absf(input_gas) * 800.0 + (900.0 if nitro_active else 0.0)


# ------------------------------------------------------------ damage

func hurt(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount * dmg_scale
	last_hurt = Time.get_ticks_msec() / 1000.0
	if is_player:
		main.on_player_hurt(amount)
	_update_look()
	if hp <= 0.0:
		dead = true
		main.on_car_dead(self)


func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(max_hp, hp + amount)
	_update_look()


func _update_look() -> void:
	var d := clampf(1.0 - hp / max_hp, 0.0, 1.0)
	mat_body.set_shader_parameter("damage", d)
	smoke.emitting = hp < max_hp * 0.45
	fire.emitting = hp < max_hp * 0.2


func add_dent(world_point: Vector3, depth: float) -> void:
	var lp := to_local(world_point)
	var ex := 0.95 if not is_swat else 1.2
	var ez := 2.1 if not is_swat else 2.8
	lp.x = clampf(lp.x, -ex, ex)
	lp.y = clampf(lp.y, 0.35, 1.3 if not is_swat else 2.4)
	lp.z = clampf(lp.z, -ez, ez)
	dents[dent_i] = Vector4(lp.x, lp.y, lp.z, depth)
	dent_i = (dent_i + 1) % 4
	for i in 4:
		mat_body.set_shader_parameter("dent%d" % i, dents[i])


func detach_part(world_point: Vector3) -> void:
	if parts.is_empty():
		return
	var best := 0
	var bd := 1e9
	for i in parts.size():
		var d := parts[i].global_position.distance_to(world_point)
		if d < bd:
			bd = d
			best = i
	var p := parts[best]
	parts.remove_at(best)
	var xf := p.global_transform
	var mesh := p.mesh
	var mat := p.material_override
	p.queue_free()
	var rb := RigidBody3D.new()
	rb.mass = 25.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (mesh as BoxMesh).size
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	rb.add_child(mi)
	main.world.debris_root.add_child(rb)
	rb.global_transform = xf
	rb.linear_velocity = linear_velocity * 0.8 + Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2))
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	main.get_tree().create_timer(9.0).timeout.connect(rb.queue_free)


# ------------------------------------------------------------ driving

func _physics_process(delta: float) -> void:
	if dead:
		return
	hit_cd = maxf(0.0, hit_cd - delta)
	var fwd := -global_transform.basis.z
	fwd_speed = linear_velocity.dot(fwd)
	speed = linear_velocity.length()

	_handle_impacts(delta)
	if siren_a != null:
		_siren(delta)
	if is_player:
		if main.game_over:
			input_gas = 0.0
			input_steer = 0.0
			input_hb = 0.0
			input_nitro = false
		else:
			_player_plow()
	elif not is_block:
		_ai(delta)

	var max_steer := 0.55 / (1.0 + absf(fwd_speed) * (0.08 if is_player else 0.04))
	steering = move_toward(steering, input_steer * max_steer, (4.0 if is_player else 2.6) * delta)

	hb_smooth = move_toward(hb_smooth, input_hb, 6.0 * delta)
	var gm: float = main.grip_mult
	for w in wheels:
		if w.position.z < 0.0:
			w.wheel_friction_slip = grip_front * gm * (1.0 - 0.1 * hb_smooth)
		else:
			w.wheel_friction_slip = grip_rear * gm * lerpf(1.0, 0.55, hb_smooth)

	var top := vmax + (12.0 if nitro_active else 0.0)
	var gas := input_gas
	var brake_f := 0.0
	var eng := 0.0
	if is_block:
		brake_f = 40.0
	elif gas > 0.0:
		if fwd_speed < -1.5:
			brake_f = 24.0 * gas
		else:
			var curve := clampf(1.0 - pow(maxf(fwd_speed, 0.0) / top, 2.2), 0.0, 1.0)
			eng = gas * engine_max * (0.35 + 0.65 * curve) * (1.0 if fwd_speed < top else 0.0)
	elif gas < 0.0:
		if fwd_speed > 1.5:
			brake_f = 26.0 * -gas
		elif fwd_speed > -12.0:
			eng = gas * engine_max * 0.45
	else:
		brake_f = 1.2
	engine_force = -eng   # VehicleBody3D drives toward +Z for positive force
	brake = brake_f + (0.0 if is_player else 5.0 * input_hb)

	var drag := linear_velocity * (0.9 + 0.06 * speed) * mass * 0.0016
	apply_central_force(-drag)
	apply_central_force(-global_transform.basis.y * speed * speed * 0.9)

	var grounded := 0
	for w in wheels:
		if w.is_in_contact():
			grounded += 1
	if is_player:
		_assists(delta, grounded, fwd)

	if grounded == 0 and is_player:
		airtime += delta
		var lv := global_transform.basis
		apply_torque(lv.x * input_gas * -900.0 + lv.z * input_steer * -500.0)
		apply_torque(-angular_velocity * 900.0)
	else:
		if is_player and airtime > 0.9:
			main.on_big_air(airtime)
		airtime = 0.0

	if global_transform.basis.y.y < 0.3 and speed < 4.0:
		flip_t += delta
		if flip_t > 1.5:
			flip_t = 0.0
			if is_player:
				var yaw := global_transform.basis.get_euler().y
				global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.6, 0))
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
			else:
				hurt(999.0)
	else:
		flip_t = 0.0

	if is_player and not main.game_over:
		var now := Time.get_ticks_msec() / 1000.0
		if now - last_hurt > 4.0 and hp < max_hp:
			heal(5.0 * delta)

	_skid_and_smoke()
	last_vel = linear_velocity


# Arcade assists: the car turns where you point it, does not slide unless drifting,
# and drifting fills the nitro.
func _assists(delta: float, grounded: int, fwd: Vector3) -> void:
	var right := global_transform.basis.x
	var lat := linear_velocity.dot(right)
	if grounded >= 2:
		var spd := absf(fwd_speed)
		var gain := clampf(spd / 5.0, 0.0, 1.0) * lerpf(2.3, 1.15, clampf(spd / 40.0, 0.0, 1.0))
		var desired := input_steer * gain * signf(fwd_speed + 0.01) * (1.0 + 0.15 * hb_smooth)
		var slip := atan2(absf(lat), maxf(absf(fwd_speed), 1.0))
		# past ~35 degrees of slip, steer the nose back so a drift never becomes a spin
		if hb_smooth > 0.3 and slip > 0.6:
			desired = -signf(lat) * 0.6 * gain
		var err := desired - angular_velocity.y
		apply_torque(Vector3.UP * err * 1700.0 * 6.0)
		var grip_k := lerpf(5.0, 0.9, hb_smooth)
		if slip > 0.7:
			grip_k = maxf(grip_k, 2.5)
		apply_central_force(-right * lat * mass * grip_k)
		if hb_smooth > 0.3 and speed > 6.0 and input_gas > 0.0:
			apply_central_force(linear_velocity.normalized() * mass * 4.0 * input_gas)
		if fwd_speed > 5.0:
			apply_central_force(fwd * absf(lat) * mass * 0.8)
			if input_gas > 0.0:
				apply_central_force(fwd * mass * absf(input_steer) * 4.5 * input_gas)
	if hb_smooth > 0.5 and absf(lat) > 3.0 and speed > 8.0:
		drift_t += delta
		nitro = minf(100.0, nitro + 9.0 * delta)
	elif drift_t > 0.0 and hb_smooth < 0.2:
		if drift_t > 0.7:
			main.on_drift(drift_t)
			apply_central_impulse(fwd * mass * minf(drift_t, 2.5) * 1.6)
		drift_t = 0.0

	nitro_active = input_nitro and nitro > 0.0 and grounded >= 2
	if nitro_active:
		nitro = maxf(0.0, nitro - 28.0 * delta)
		apply_central_force(fwd * mass * 9.0)
	flame.emitting = nitro_active


func _skid_and_smoke() -> void:
	for i in wheels.size():
		var w := wheels[i]
		var slip := 0.0
		if w.is_in_contact() and speed > 4.0:
			slip = 1.0 - w.get_skidinfo()
		if is_player:
			var lat := absf(linear_velocity.dot(global_transform.basis.x))
			if w.position.z > 0.0 and w.is_in_contact():
				slip = maxf(slip, clampf((lat - 3.0) / 4.0, 0.0, 1.0))
		if slip > 0.45:
			var wp := w.global_position
			var p := Vector3(wp.x, 0.05, wp.z)
			var prev = skid_prev[i]
			if prev != null:
				main.fx.skid(prev, p)
			skid_prev[i] = p
			if randf() < 0.35:
				main.fx.tire_smoke(p)
		else:
			skid_prev[i] = null


func _handle_impacts(delta: float) -> void:
	var dv := linear_velocity - last_vel
	var hit_other := false
	for b in get_colliding_bodies():
		if b is StaticBody3D or b is VehicleBody3D:
			hit_other = true
	var mag := Vector3(dv.x, dv.y * 0.3, dv.z).length()
	if hit_other and mag > 2.2 and hit_cd <= 0.0:
		impact_acc += mag
		impact_dir = -dv.normalized()
		impact_t = 0.0
		hit_cd = 0.05
	elif impact_acc > 0.0:
		impact_t += delta
		if impact_t > 0.2:
			_apply_impact(impact_acc, impact_dir)
			impact_acc = 0.0


func _apply_impact(total: float, dir: Vector3) -> void:
	var gp := global_position + dir * 1.3 + Vector3(0, 0.2, 0)
	var over := maxf(total - impact_threshold, 0.0)
	hurt(pow(over, 1.15) * 0.6)
	add_dent(gp, clampf(total * 0.025, 0.06, 0.4))
	if total > 9.0 and randf() < 0.6:
		detach_part(gp)
	main.on_car_impact(self, gp, total)


# Player only: destroy buildings just before contact so the car can plough through.
func _player_plow() -> void:
	if fwd_speed < 9.0 or hit_cd > 0.0:
		return
	var space := get_world_3d().direct_space_state
	var dirv := Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized()
	var side := dirv.cross(Vector3.UP)
	var reach := 2.4 + fwd_speed * 0.1
	for off: float in [0.0, -0.8, 0.8]:
		var o: Vector3 = global_position + Vector3(0, 0.9, 0) + side * off
		var q := PhysicsRayQueryParameters3D.create(o, o + dirv * reach, 1)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var col: Object = r["collider"]
		if col is StaticBody3D and col.has_meta("bld"):
			var b: Building = col.get_meta("bld")
			var cells: int = main.world.car_hit_building(b, r["position"], dirv, fwd_speed)
			if cells > 0:
				linear_velocity *= clampf(1.0 - cells * 0.005, 0.7, 1.0)
				hit_cd = 0.12
				hurt(minf(cells * 0.025, 3.0))
				nitro = minf(100.0, nitro + cells * 0.08)
				main.on_car_plow(self, r["position"], cells)
				return


# ------------------------------------------------------------ police AI

func _siren(delta: float) -> void:
	siren_t += delta
	var on := sin(siren_t * 14.0) > 0.0
	siren_a.emission_energy_multiplier = 4.0 if on else 0.2
	siren_b.emission_energy_multiplier = 0.2 if on else 4.0
	siren_light.light_color = Color(1, 0.1, 0.1) if on else Color(0.2, 0.4, 1.0)
	siren_light.visible = global_position.distance_squared_to(main.player.global_position) < 5000.0


func _ai(delta: float) -> void:
	if target == null or target.dead or main.game_over:
		input_gas = 0.0
		input_steer = 0.0
		return
	var tpos: Vector3 = target.global_position
	var to := tpos - global_position
	to.y = 0.0
	var dist := to.length()
	var tvel: Vector3 = target.linear_velocity
	var lead := clampf(dist / maxf(speed + 6.0, 6.0), 0.0, 1.4)
	var aim := tpos + tvel * lead
	var direct := false
	if dist < 90.0:
		var sp := get_world_3d().direct_space_state
		var rq := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), tpos + Vector3(0, 1.0, 0), 1)
		direct = sp.intersect_ray(rq).is_empty()
	if not direct:
		path_t -= delta
		if path_t <= 0.0 or path.is_empty():
			path_t = randf_range(0.7, 1.2)
			path = main.world.route(global_position, tpos)
			while path.size() > 1 and global_position.distance_to(path[1]) < path[0].distance_to(path[1]):
				path.remove_at(0)
		while path.size() > 1 and global_position.distance_to(path[0]) < 16.0:
			path.remove_at(0)
		if not path.is_empty():
			aim = path[0]
	elif dist < 22.0 and target.speed > 6.0 and not is_swat:
		var tf: Vector3 = -target.global_transform.basis.z
		var tr: Vector3 = target.global_transform.basis.x
		aim = tpos - tf * 2.0 + tr * pit_side * 1.1
	var d := aim - global_position
	d.y = 0.0
	var desired := atan2(-d.x, -d.z)
	var f := -global_transform.basis.z
	var heading := atan2(-f.x, -f.z)
	var diff := wrapf(desired - heading, -PI, PI)
	var st := clampf(diff * 1.8, -1.0, 1.0)

	var space := get_world_3d().direct_space_state
	var o := global_position + Vector3(0, 0.9, 0)
	for s: float in [-1.0, 1.0]:
		var dirv := f.rotated(Vector3.UP, s * 0.5)
		var q := PhysicsRayQueryParameters3D.create(o, o + dirv * 11.0, 1)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			st -= s * (1.2 - o.distance_to(r["position"]) / 11.0)
	var qf := PhysicsRayQueryParameters3D.create(o, o + f * 9.0, 1)
	var blocked := not space.intersect_ray(qf).is_empty()
	input_steer = clampf(st, -1.0, 1.0)

	var want := top_speed
	if absf(diff) > 0.9:
		want = 9.0
	elif absf(diff) > 0.45:
		want = top_speed * 0.6
	if blocked:
		want = minf(want, 8.0)
	input_gas = clampf((want - fwd_speed) * 0.35, -1.0, 1.0)
	if dist < 6.0 and absf(diff) < 0.6:
		input_gas = 1.0
	input_hb = 0.0

	if reverse_t > 0.0:
		reverse_t -= delta
		input_gas = -1.0
		input_steer = -input_steer
	elif absf(fwd_speed) < 1.2 and input_gas > 0.2:
		stuck_t += delta
		if stuck_t > 1.1:
			stuck_t = 0.0
			reverse_t = 0.9
	else:
		stuck_t = 0.0
