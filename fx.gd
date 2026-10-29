class_name Fx
extends Node3D
# Particles, skid marks and synthesized sound. Everything is pooled and made in code.

var main
var fire_mesh: SphereMesh
var smoke_mesh: SphereMesh
var dust_mesh: SphereMesh
var spark_mesh: BoxMesh
var fireball_mesh: SphereMesh
var grow_fade: Curve
var shrink: Curve
var dust_pool: Array[CPUParticles3D] = []
var fire_pool: Array[CPUParticles3D] = []
var smoke_pool: Array[CPUParticles3D] = []
var spark_pool: Array[CPUParticles3D] = []
var tire_pool: Array[CPUParticles3D] = []
var idx := {"dust": 0, "fire": 0, "smoke": 0, "spark": 0, "tire": 0}
var flash: OmniLight3D
var skid_mm: MultiMesh
var skid_i := 0
var fade: Gradient
const SKID_MAX := 700

var sounds := {}
var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_i := 0
var engine_player: AudioStreamPlayer
var engine_pb: AudioStreamGeneratorPlayback
var engine_phase := 0.0
var engine_noise := 0.0
const MIX := 22050.0


func setup(main_node) -> void:
	main = main_node
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.albedo_color = Color(1, 0.55, 0.12)
	fire_mesh = SphereMesh.new()
	fire_mesh.radius = 0.3
	fire_mesh.height = 0.6
	fire_mesh.radial_segments = 8
	fire_mesh.rings = 4
	fire_mesh.material = fm

	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.2, 0.2, 0.22)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mesh = SphereMesh.new()
	smoke_mesh.radius = 0.5
	smoke_mesh.height = 1.0
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	smoke_mesh.material = sm

	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.62, 0.58, 0.52)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mesh = SphereMesh.new()
	dust_mesh.radius = 0.9
	dust_mesh.height = 1.8
	dust_mesh.radial_segments = 8
	dust_mesh.rings = 4
	dust_mesh.material = dm

	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1, 0.85, 0.4)
	spark_mesh = BoxMesh.new()
	spark_mesh.size = Vector3(0.1, 0.1, 0.3)
	spark_mesh.material = pm

	fireball_mesh = SphereMesh.new()
	fireball_mesh.radius = 1.0
	fireball_mesh.height = 2.0
	fireball_mesh.radial_segments = 14
	fireball_mesh.rings = 8

	fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.85))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	grow_fade = Curve.new()
	grow_fade.add_point(Vector2(0.0, 0.35))
	grow_fade.add_point(Vector2(0.35, 1.0))
	grow_fade.add_point(Vector2(1.0, 0.0))
	shrink = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))

	for i in 8:
		dust_pool.append(_pool_node(dust_mesh, 24, 2.6, Vector3(0, 0.6, 0), 1.5, 5.0, 180.0, grow_fade, Color(0.8, 0.77, 0.72, 0.8)))
	for i in 4:
		fire_pool.append(_pool_node(fire_mesh, 40, 0.9, Vector3(0, -12, 0), 4.0, 12.0, 180.0, shrink, Color.WHITE))
		smoke_pool.append(_pool_node(smoke_mesh, 16, 2.2, Vector3(0, 2.2, 0), 1.0, 4.0, 180.0, grow_fade, Color(0.5, 0.5, 0.5, 0.85)))
	for i in 8:
		spark_pool.append(_pool_node(spark_mesh, 14, 0.6, Vector3(0, -14, 0), 4.0, 11.0, 60.0, shrink, Color.WHITE))
	for i in 12:
		tire_pool.append(_pool_node(dust_mesh, 3, 1.2, Vector3(0, 0.5, 0), 0.4, 1.5, 30.0, grow_fade, Color(0.85, 0.85, 0.85, 0.45)))
		tire_pool[i].scale = Vector3.ONE * 0.45

	flash = OmniLight3D.new()
	flash.omni_range = 45.0
	flash.light_color = Color(1, 0.6, 0.25)
	flash.light_energy = 0.0
	add_child(flash)

	var sh := Shader.new()
	sh.code = Shaders.SKID
	var skm := ShaderMaterial.new()
	skm.shader = sh
	var qm := BoxMesh.new()
	qm.size = Vector3(1, 0.01, 1)
	skid_mm = MultiMesh.new()
	skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	skid_mm.use_colors = true
	skid_mm.mesh = qm
	skid_mm.instance_count = SKID_MAX
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in SKID_MAX:
		skid_mm.set_instance_transform(i, hidden)
		skid_mm.set_instance_color(i, Color(1, 1, 1, 1))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = skid_mm
	smi.material_override = skm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)

	_make_sounds()
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 30.0
		p.max_distance = 260.0
		add_child(p)
		sfx_pool.append(p)
	engine_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX
	gen.buffer_length = 0.12
	engine_player.stream = gen
	engine_player.volume_db = -9.0
	add_child(engine_player)
	engine_player.play()
	engine_pb = engine_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _pool_node(mesh: Mesh, amount: int, life: float, grav: Vector3, vmin: float, vmax: float, spread: float, curve: Curve, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	p.scale_amount_curve = curve
	p.color = col
	if col.a < 1.0:
		p.color_ramp = fade
	p.local_coords = false
	add_child(p)
	return p


func _next(pool: Array[CPUParticles3D], key: String) -> CPUParticles3D:
	var i: int = idx[key]
	idx[key] = (i + 1) % pool.size()
	return pool[i]


func _fire_at(p: CPUParticles3D, pos: Vector3, amount: int = -1) -> void:
	if amount > 0:
		p.amount = amount
	p.global_position = pos
	p.restart()
	p.emitting = true


func dust(pos: Vector3, cells: int) -> void:
	var p := _next(dust_pool, "dust")
	_fire_at(p, pos + Vector3(0, 1.5, 0), clampi(cells / 2 + 8, 8, 34))


func sparks(pos: Vector3, n: int = 14) -> void:
	_fire_at(_next(spark_pool, "spark"), pos, n)


func tire_smoke(pos: Vector3) -> void:
	_fire_at(_next(tire_pool, "tire"), pos + Vector3(0, 0.3, 0))


func explosion(pos: Vector3, power: float) -> void:
	_fire_at(_next(fire_pool, "fire"), pos, clampi(int(24 + power * 3.0), 24, 60))
	_fire_at(_next(smoke_pool, "smoke"), pos + Vector3(0, 1, 0), clampi(int(8 + power), 8, 24))
	var fb := MeshInstance3D.new()
	fb.mesh = fireball_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.62, 0.2, 0.9)
	fb.material_override = m
	fb.scale = Vector3.ONE * 0.6
	add_child(fb)
	fb.global_position = pos + Vector3(0, 0.8, 0)
	var tw := create_tween()
	tw.tween_property(fb, "scale", Vector3.ONE * (2.2 + power * 0.4), 0.38)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.38)
	tw.tween_callback(fb.queue_free)
	flash.global_position = pos + Vector3(0, 3, 0)
	flash.light_energy = 7.0
	var t2 := create_tween()
	t2.tween_property(flash, "light_energy", 0.0, 0.5)


func make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = smoke_mesh
	p.amount = 14
	p.lifetime = 1.8
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 1.0, 0)
	p.scale_amount_curve = grow_fade
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	p.color = Color(0.3, 0.3, 0.32, 0.8)
	p.color_ramp = fade
	p.local_coords = false
	return p


func make_flame() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = fire_mesh
	p.amount = 24
	p.lifetime = 0.22
	p.emitting = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 7.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3.ZERO
	p.scale_amount_curve = shrink
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	p.color = Color(0.55, 0.75, 1.0, 1)
	p.local_coords = false
	return p


func make_fire() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = fire_mesh
	p.amount = 12
	p.lifetime = 0.6
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, 3.0, 0)
	p.scale_amount_curve = shrink
	p.color = Color(1, 0.55, 0.15, 1)
	p.local_coords = false
	return p


func skid(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.05 or l > 3.0:
		return
	var dir := d / l
	var side := dir.cross(Vector3.UP).normalized()
	var basis := Basis(side * 0.3, Vector3.UP, dir * (l + 0.04))
	skid_mm.set_instance_transform(skid_i, Transform3D(basis, (a + b) * 0.5 + Vector3(0, 0.03, 0)))
	skid_i = (skid_i + 1) % SKID_MAX


# ------------------------------------------------------------ sound

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(MIX)
	w.stereo = false
	w.data = bytes
	return w


func _noise_burst(seconds: float, decay: float, lp: float, thump: float) -> AudioStreamWAV:
	var n := int(seconds * MIX)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / MIX
		var a := lp * (1.0 - t / seconds * 0.7)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		var v := y * exp(-t * decay) * 2.2
		v += sin(t * TAU * (thump - t * 18.0)) * exp(-t * decay * 0.8) * 0.8 * (1.0 if thump > 0.0 else 0.0)
		s[i] = v * 0.7
	return _wav(s)


func _make_sounds() -> void:
	sounds["explosion"] = _noise_burst(1.3, 3.2, 0.12, 52.0)
	sounds["crash"] = _noise_burst(0.4, 11.0, 0.45, 0.0)
	sounds["thud"] = _noise_burst(0.5, 8.0, 0.1, 70.0)
	sounds["rumble"] = _noise_burst(0.9, 3.0, 0.05, 0.0)
	sounds["siren"] = _siren(2.0)


# Police wail: pitch sweeps 530-1370 Hz and back over one period. The sweep
# averages to a whole number of cycles per period, so the loop point is seamless.
func _siren(period: float) -> AudioStreamWAV:
	var n := int(period * MIX)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / MIX
		ph += (950.0 - 420.0 * cos(TAU * t / period)) / MIX
		var p := ph * TAU
		s[i] = (sin(p) * 0.6 + sin(2.0 * p) * 0.15 + sin(3.0 * p) * 0.1) * 0.55
	var w := _wav(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func play(name: String, pos: Vector3, vol_db: float = 0.0) -> void:
	if not sounds.has(name):
		return
	var p := sfx_pool[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_pool.size()
	p.stream = sounds[name]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()


func engine(rpm: float, thr: float, active: bool) -> void:
	if engine_pb == null:
		return
	var frames := engine_pb.get_frames_available()
	if frames <= 0:
		return
	var f := rpm / 60.0 * 2.0
	var vol := (0.16 + 0.12 * thr) if active else 0.0
	var step := f / MIX
	for i in mini(frames, 1200):
		engine_phase += step
		if engine_phase > 1.0:
			engine_phase -= 1.0
		var p := engine_phase * TAU
		engine_noise += 0.15 * (randf_range(-1.0, 1.0) - engine_noise)
		var s := sin(p) + 0.55 * sin(2.0 * p + 0.6) + 0.3 * sin(3.0 * p) + 0.15 * sin(5.0 * p)
		s = s * 0.5 + engine_noise * (0.25 + thr * 0.4)
		var v := clampf(s * vol, -0.9, 0.9)
		engine_pb.push_frame(Vector2(v, v))
