extends Node3D
# Cube City Chase 2: big city, real car physics, destruction, wanted level.

var world: World
var fx: Fx
var hud: Hud
var player: Car
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var rain: CPUParticles3D
var heli: Node3D
var heli_rotor: Node3D
var heli_spot: SpotLight3D
var police: Array[Car] = []
var blocks: Array[Car] = []

var game_over := false
var time_alive := 0.0
var score := 0
var bonus := 0
var cubes := 0
var wrecked := 0
var heat := 0.0
var level := 1
var blast_cd := 0.0
var spawn_t := 2.5
var block_t := 22.0
var shake := 0.0
var cam_dir := Vector3(0, 0, -1)
var tod := 0.22
var rain_amt := 0.0
var grip_mult := 1.0
var escape_t := 0.0
var best := 0
var heli_t := 0.0
var test_mode := false
var test_cam := false
var civs: Array[CivCar] = []
var civ_t := 0.0
var swat: Car = null
var swat_t := 18.0
var slowmo_until := 0.0
var slowmo_cd := 0.0
var cine_t := 0.0
var cine_target := Vector3.ZERO
var cine_h := 10.0
var cine_ang := 0.0
var boom_times: Array[float] = []


func _ready() -> void:
	randomize()
	_load_best()
	_make_env()
	fx = Fx.new()
	add_child(fx)
	fx.setup(self)
	world = World.new()
	add_child(world)
	world.setup(self, fx)
	_make_player()
	world.load_around(player.global_position, true)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_make_heli()
	_make_rain()
	cam.global_position = player.global_position + Vector3(0, 4, 9)


func _make_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.25
	sky_mat.ground_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.0014
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	cam = Camera3D.new()
	cam.far = 420.0
	cam.fov = 62.0
	add_child(cam)


func _make_player() -> void:
	player = Car.new()
	player.main = self
	player.build(Color(0.85, 0.14, 0.1), true)
	player.max_hp = 100.0
	player.hp = 100.0
	add_child(player)
	var start := Vector3(world.line(8) + 3.5, 0.9, world.line(8) + 36.0)
	player.global_transform = Transform3D(Basis.IDENTITY, start)


func _make_heli() -> void:
	heli = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.14, 0.2)
	var parts := [
		[Vector3(2.2, 1.7, 5.0), Vector3(0, 0, 0)],
		[Vector3(0.5, 0.5, 5.0), Vector3(0, 0.2, 4.6)],
		[Vector3(1.6, 0.1, 0.9), Vector3(0, 0.5, 6.8)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = mat
		mi.position = p[1]
		heli.add_child(mi)
	heli_rotor = Node3D.new()
	heli_rotor.position = Vector3(0, 1.1, 0)
	for a in [0.0, PI * 0.5]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(11.0, 0.06, 0.4)
		mi.mesh = bm
		mi.material_override = mat
		mi.rotation.y = a
		heli_rotor.add_child(mi)
	heli.add_child(heli_rotor)
	heli_spot = SpotLight3D.new()
	heli_spot.spot_range = 90.0
	heli_spot.spot_angle = 14.0
	heli_spot.light_energy = 6.0
	heli_spot.position = Vector3(0, -0.8, -1.5)
	heli.add_child(heli_spot)
	heli.visible = false
	add_child(heli)


func _make_rain() -> void:
	rain = CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.8, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.82, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = m
	rain.mesh = bm
	rain.amount = 450
	rain.lifetime = 0.8
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(28, 1, 28)
	rain.direction = Vector3(0, -1, 0)
	rain.spread = 2.0
	rain.initial_velocity_min = 32.0
	rain.initial_velocity_max = 38.0
	rain.gravity = Vector3(0, -10, 0)
	rain.local_coords = false
	rain.emitting = false
	add_child(rain)


# ------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var now := Time.get_ticks_msec() / 1000.0
	if Engine.time_scale < 1.0 and now >= slowmo_until:
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
	_update_traffic(delta)
	if not game_over:
		time_alive += delta
		blast_cd = maxf(0.0, blast_cd - delta)
		player.input_gas = hud.in_gas
		player.input_steer = hud.in_steer
		player.input_hb = hud.in_hb
		player.input_nitro = hud.in_nitro
		_update_police(delta)
		_update_wanted(delta)
	score = int(time_alive) + cubes + wrecked * 100 + bonus
	world.load_around(player.global_position, false)
	_update_heli(delta)
	_update_cam(delta)
	_update_env(delta)
	shake = maxf(0.0, shake - delta * 1.8)
	if not test_mode:
		fx.engine(player.rpm(), absf(player.input_gas), not game_over and not player.dead)
	hud.update_hud()


func _all_cars() -> Array[Car]:
	var out: Array[Car] = [player]
	for c in police:
		if is_instance_valid(c):
			out.append(c)
	for c in blocks:
		if is_instance_valid(c):
			out.append(c)
	return out


# ------------------------------------------------------------ police

func _spawn_police() -> void:
	var dirv := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	if dirv.length() < 3.0:
		dirv = -player.global_transform.basis.z
	dirv = dirv.normalized()
	for attempt in 6:
		var r: Dictionary = world.road_spawn(player.global_position + dirv * 50.0, 70.0, 130.0)
		var pos: Vector3 = r["pos"]
		if pos.distance_to(player.global_position) < 65.0:
			continue
		var yaw: float = r["yaw"]
		var f := Vector3(-sin(yaw), 0, -cos(yaw))
		if f.dot(player.global_position - pos) < 0.0:
			yaw += PI
		var c := Car.new()
		c.main = self
		c.build(Color(0.93, 0.94, 0.97), false)
		c.max_hp = 70.0
		c.hp = 70.0
		c.dmg_scale = 2.2
		c.impact_threshold = 3.0
		c.top_speed = 25.0 + level * 2.2 + randf() * 3.0
		c.vmax = c.top_speed + 6.0
		c.engine_max = 2500.0
		c.target = player
		c.pit_side = 1.0 if randf() < 0.5 else -1.0
		add_child(c)
		c.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		police.append(c)
		return


func _spawn_swat() -> void:
	var r: Dictionary = world.road_spawn(player.global_position, 90.0, 140.0)
	var pos: Vector3 = r["pos"]
	var yaw: float = r["yaw"]
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	if f.dot(player.global_position - pos) < 0.0:
		yaw += PI
	var c := Car.new()
	c.main = self
	c.build(Color(0.07, 0.08, 0.1), false, "swat")
	c.max_hp = 260.0
	c.hp = 260.0
	c.engine_max = 7500.0
	c.top_speed = 24.0 + level * 1.5
	c.vmax = c.top_speed + 5.0
	c.dmg_scale = 0.8
	c.impact_threshold = 6.0
	c.target = player
	add_child(c)
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.4, 0))
	police.append(c)
	swat = c
	hud.banner("SWAT TRUCK INCOMING")


func _update_traffic(dt: float) -> void:
	civ_t -= dt
	for c in civs.duplicate():
		if not is_instance_valid(c):
			civs.erase(c)
		elif c.global_position.distance_to(player.global_position) > 240.0:
			civs.erase(c)
			c.queue_free()
	if civ_t <= 0.0 and civs.size() < 12:
		civ_t = 0.5
		var r: Dictionary = world.road_spawn(player.global_position, 70.0, 170.0)
		var yaw: float = r["yaw"]
		var d := Vector3(roundf(-sin(yaw)), 0, roundf(-cos(yaw)))
		var c := CivCar.new()
		add_child(c)
		c.build(self, CivCar.palette(randi()), true)
		c.cruise = randf_range(9.0, 13.0)
		c.start_route(r["pos"], d)
		civs.append(c)


func cars_near(pos: Vector3, r: float) -> Array:
	var out := []
	for c in _all_cars():
		if not c.dead and c.global_position.distance_to(pos) < r:
			out.append(c)
	return out


func _spawn_roadblock() -> void:
	var dirv := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	if dirv.length() < 5.0:
		dirv = -player.global_transform.basis.z
	dirv = dirv.normalized()
	var r: Dictionary = world.road_spawn(player.global_position + dirv * 190.0, 0.0, 10.0)
	var pos: Vector3 = r["pos"]
	var yaw: float = r["yaw"]
	var along := Vector3(-sin(yaw), 0, -cos(yaw))
	var across := along.cross(Vector3.UP)
	var center: Vector3 = r["center"]
	for s in [-1.0, 1.0]:
		var c := Car.new()
		c.main = self
		c.build(Color(0.93, 0.94, 0.97), false)
		c.is_block = true
		c.max_hp = 70.0
		c.hp = 70.0
		add_child(c)
		var p: Vector3 = center + across * (s * 3.3)
		p.y = 0.9
		c.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5 + randf_range(-0.2, 0.2)), p)
		blocks.append(c)


func _update_police(dt: float) -> void:
	var caps := [3, 5, 6, 8, 10]
	var cap: int = caps[level - 1]
	spawn_t -= dt
	if spawn_t <= 0.0 and police.size() < cap:
		spawn_t = randf_range(2.5, 4.5)
		_spawn_police()
	for c in police.duplicate():
		if not is_instance_valid(c):
			police.erase(c)
		elif c.global_position.distance_to(player.global_position) > 320.0:
			police.erase(c)
			c.queue_free()
		elif not c.is_swat:
			c.top_speed = 25.0 + level * 2.2
	for c in blocks.duplicate():
		if not is_instance_valid(c):
			blocks.erase(c)
		elif c.global_position.distance_to(player.global_position) > 280.0:
			blocks.erase(c)
			c.queue_free()
	if level >= 3 and (swat == null or not is_instance_valid(swat) or swat.dead):
		swat_t -= dt
		if swat_t <= 0.0:
			swat_t = 40.0
			_spawn_swat()
	if level >= 2:
		block_t -= dt
		if block_t <= 0.0 and blocks.size() < 4:
			block_t = maxf(10.0, 30.0 - level * 3.0)
			_spawn_roadblock()


func _update_wanted(dt: float) -> void:
	var nearest := 1e9
	for c in police:
		if is_instance_valid(c) and not c.dead:
			nearest = minf(nearest, c.global_position.distance_to(player.global_position))
	if nearest < 45.0:
		heat += dt * 0.35
	var spotted := false
	if heli.visible:
		var d := heli.global_position - player.global_position
		d.y = 0.0
		spotted = d.length() < 55.0
	if nearest > 100.0 and not spotted:
		escape_t += dt
	else:
		escape_t = 0.0
	if escape_t > 7.0:
		heat = maxf(0.0, heat - dt * 5.0)
	var nl := 1
	for t in [12.0, 30.0, 55.0, 85.0]:
		if heat >= t:
			nl += 1
	if nl != level:
		if nl > level:
			hud.banner("WANTED LEVEL %d" % nl)
		else:
			hud.banner("HEAT DOWN")
		level = nl


func _update_heli(dt: float) -> void:
	var on := level >= 4 and not game_over
	if on and not heli.visible:
		heli.visible = true
		heli.global_position = player.global_position + Vector3(120, 40, 120)
	elif not on and heli.visible and level < 4:
		heli.visible = false
	if not heli.visible:
		return
	heli_t += dt
	heli_rotor.rotate_y(dt * 38.0)
	var tgt := player.global_position + player.linear_velocity * 0.9 + Vector3(sin(heli_t * 0.4) * 14.0, 26.0, cos(heli_t * 0.4) * 14.0)
	heli.global_position = heli.global_position.lerp(tgt, 1.0 - exp(-0.9 * dt))
	var look := player.global_position - heli.global_position
	look.y = 0.0
	if look.length() > 0.5:
		heli.rotation.y = lerp_angle(heli.rotation.y, atan2(-look.x, -look.z), 2.0 * dt)
	heli_spot.look_at(player.global_position, Vector3.UP)


# ------------------------------------------------------------ camera and environment

func cinematic(target: Vector3, height: float) -> void:
	cine_t = 2.6
	cine_target = target
	cine_h = height
	var away := player.global_position - target
	cine_ang = atan2(away.z, away.x)


func _update_cam(dt: float) -> void:
	if test_cam:
		return
	if cine_t > 0.0 and not game_over:
		cine_t -= dt
		cine_ang += dt * 0.35
		var dist := 30.0 + cine_h * 0.9
		var cp := cine_target + Vector3(cos(cine_ang) * dist, cine_h * 0.45 + 5.0, sin(cine_ang) * dist)
		cam.global_position = cam.global_position.lerp(cp, 1.0 - exp(-3.0 * dt))
		cam.look_at(cine_target + Vector3(0, cine_h * 0.3, 0), Vector3.UP)
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var vel := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	var want := fwd
	if vel.length() > 8.0 and player.fwd_speed > 0.0:
		want = fwd.lerp(vel.normalized(), 0.45).normalized()
	cam_dir = cam_dir.lerp(want, 1.0 - exp(-4.0 * dt)).normalized()
	var spd := player.speed
	var target := player.global_position - cam_dir * (8.2 + spd * 0.05) + Vector3(0, 3.5 + spd * 0.02, 0)
	var p := cam.global_position.lerp(target, 1.0 - exp(-9.0 * dt))
	p += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake
	cam.global_position = p
	var side := cam_dir.cross(Vector3.UP)
	cam.look_at(player.global_position + cam_dir * 6.0 - side * player.input_steer * 2.5 + Vector3(0, 1.2, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 62.0 + clampf(spd, 0.0, 40.0) * 0.5 + (10.0 if player.nitro_active else 0.0), 4.0 * dt)


func _update_env(dt: float) -> void:
	tod = fposmod(tod + dt / 480.0, 1.0)
	var e := sin(tod * TAU)
	var day := clampf(e * 2.5 + 0.35, 0.0, 1.0)
	var night := 1.0 - day
	var rain_target := 1.0 if sin(tod * TAU * 2.0 + 4.0) > 0.88 else 0.0
	rain_amt = move_toward(rain_amt, rain_target, dt * 0.12)
	grip_mult = 1.0 - 0.16 * rain_amt
	var dusk := clampf(1.0 - absf(e) * 3.0, 0.0, 1.0)
	var top := Color(0.03, 0.04, 0.1).lerp(Color(0.2, 0.42, 0.78), day)
	var hor := Color(0.06, 0.07, 0.14).lerp(Color(0.66, 0.77, 0.88), day).lerp(Color(0.95, 0.55, 0.32), dusk * 0.6)
	var grey := Color(0.55, 0.58, 0.62)
	top = top.lerp(grey * (0.3 + 0.7 * day), rain_amt * 0.6)
	hor = hor.lerp(grey * (0.3 + 0.7 * day), rain_amt * 0.7)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.3)
	env.ambient_light_color = Color(0.18, 0.2, 0.32).lerp(Color(0.66, 0.7, 0.8), day)
	env.ambient_light_energy = lerpf(1.1, 0.8, day)
	env.fog_light_color = hor
	env.fog_density = lerpf(0.0018, 0.0035, rain_amt)
	sun.light_energy = lerpf(0.0, 1.2, day) * (1.0 - 0.55 * rain_amt)
	sun.light_color = Color(1, 0.96, 0.88).lerp(Color(1.0, 0.7, 0.45), dusk)
	sun.rotation_degrees = Vector3(-lerpf(6.0, 60.0, clampf(e, 0.0, 1.0)), -35.0, 0)
	world.set_night(night, rain_amt)
	player.set_headlights(night)
	rain.global_position = player.global_position + Vector3(0, 20, 0)
	rain.emitting = rain_amt > 0.2


# ------------------------------------------------------------ game events

func try_blast() -> void:
	if game_over or blast_cd > 0.0:
		return
	blast_cd = 6.0
	var f := -player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	explode_at(player.global_position + f * 14.0 + Vector3(0, 1.0, 0), 10.0, 24.0, 70.0, false)


func explode_at(pos: Vector3, radius: float, force: float, dmg: float, hurt_player: bool = true) -> void:
	world.damage_area(pos, radius, force)
	for c in _all_cars():
		if c.dead or (c.is_player and not hurt_player):
			continue
		var d := c.global_position.distance_to(pos)
		var reach := radius * 1.8
		if d < reach:
			var fall := 1.0 - d / reach
			var dirv := (c.global_position - pos).normalized() + Vector3(0, 0.5, 0)
			c.apply_central_impulse(dirv * force * c.mass * 0.09 * fall)
			c.hurt(dmg * fall)
	for n in get_tree().get_nodes_in_group("loose"):
		var rb := n as RigidBody3D
		if rb == null:
			continue
		var dd := rb.global_position.distance_to(pos)
		var rr := radius * 1.8
		if dd < rr:
			var fl := 1.0 - dd / rr
			if n is CivCar:
				(n as CivCar).knock(Vector3.ZERO)
			rb.sleeping = false
			rb.apply_central_impulse(((rb.global_position - pos).normalized() + Vector3(0, 0.6, 0)) * force * rb.mass * 0.09 * fl)
			if n.has_method("hurt"):
				n.hurt(dmg * fl * 1.3)
	fx.explosion(pos, radius)
	fx.play("explosion", pos, 3.0)
	shake_cam(0.5 + radius * 0.06)
	var now := Time.get_ticks_msec() / 1000.0
	boom_times.append(now)
	while boom_times.size() > 0 and now - boom_times[0] > 1.6:
		boom_times.remove_at(0)
	if boom_times.size() >= 3 and player.global_position.distance_to(pos) < 140.0:
		bonus += 150
		hud.banner("CHAIN REACTION x%d" % boom_times.size())
		slowmo(1.3, 0.35)


func slowmo(real_dur: float, scale: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < slowmo_cd or game_over:
		return
	slowmo_until = now + real_dur
	slowmo_cd = now + real_dur + 3.5
	Engine.time_scale = scale
	AudioServer.playback_speed_scale = maxf(scale, 0.5)


func big_boom(pos: Vector3, radius: float) -> void:
	explode_at(pos, radius, 30.0, 60.0)
	bonus += 800
	hud.banner("GAS STATION +800")
	shake_cam(1.2)
	if player.global_position.distance_to(pos) < 150.0:
		slowmo(1.8, 0.3)


func on_big_air(t: float) -> void:
	var pts := int(t * 150.0)
	bonus += pts
	hud.banner("BIG AIR +%d" % pts)


func on_drift(t: float) -> void:
	if t > 1.2:
		var pts := int(t * 60.0)
		bonus += pts
		hud.banner("DRIFT +%d" % pts)


func on_pickup(k: String, pos: Vector3) -> void:
	if k == "repair":
		player.heal(45.0)
		hud.banner("REPAIRED")
	else:
		player.nitro = 100.0
		hud.banner("NITRO FULL")
	fx.sparks(pos + Vector3(0, 1, 0), 20)


func on_prop_smash(pos: Vector3) -> void:
	bonus += 5
	fx.play("crash", pos, -8.0)


func on_civ_wreck(c: CivCar) -> void:
	bonus += 50
	heat += 1.5


func on_cells_destroyed(n: int) -> void:
	cubes += n
	heat += n * 0.012


func on_car_dead(car: Car) -> void:
	explode_at(car.global_position, 7.0 if car.is_player else 5.0, 12.0, 25.0)
	car.fire.emitting = true
	car.smoke.emitting = true
	car.engine_force = 0.0
	car.brake = 20.0
	if car.is_swat:
		bonus += 1000
		hud.banner("SWAT DOWN +1000")
		slowmo(1.6, 0.3)
	if car.is_player:
		game_over = true
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
		_save_best()
		score = int(time_alive) + cubes + wrecked * 100 + bonus
		hud.show_over("WRECKED\n\nScore  %d\nBest  %d\nPolice wrecked  %d\n\nTap to play again" % [score, best, wrecked])
	else:
		wrecked += 1
		heat += 6.0
		police.erase(car)
		blocks.erase(car)
		if not car.is_swat:
			hud.banner("WRECKED +100")
		get_tree().create_timer(14.0).timeout.connect(func():
			if is_instance_valid(car):
				car.queue_free())


func on_player_hurt(amount: float) -> void:
	hud.hurt_flash(amount * 0.012)
	shake_cam(0.25 + amount * 0.02)


func on_car_impact(car: Car, point: Vector3, total: float) -> void:
	fx.sparks(point, clampi(int(total), 6, 22))
	fx.play("crash", point, clampf(total * 0.5 - 6.0, -8.0, 2.0))
	if car.is_player:
		shake_cam(0.2 + total * 0.03)


func on_car_plow(car: Car, point: Vector3, cells: int) -> void:
	fx.play("thud", point, clampf(cells * 0.1 - 4.0, -6.0, 3.0))
	shake_cam(0.15 + cells * 0.006)
	if cells >= 30:
		hud.banner("BIG SMASH")


func on_building_collapse(b: Building) -> void:
	bonus += 500
	heat += 4.0
	hud.banner("BUILDING DOWN +500")
	var d := b.center().distance_to(player.global_position)
	if d < 170.0:
		slowmo(2.0, 0.35)
		if b.ny >= 8:
			cinematic(Vector3(b.center().x, 0.0, b.center().z), b.ny * Building.C)


func shake_cam(a: float) -> void:
	shake = maxf(shake, minf(a, 1.2))


func play_sfx(name: String, pos: Vector3, db: float = 0.0) -> void:
	fx.play(name, pos, db)


func restart() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	get_tree().reload_current_scene()


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://best2.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))


func _save_best() -> void:
	var s := int(time_alive) + cubes + wrecked * 100 + bonus
	if s > best:
		best = s
		var cf := ConfigFile.new()
		cf.set_value("score", "best", best)
		cf.save("user://best2.cfg")
