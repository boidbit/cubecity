extends Node3D
# Cube City Chase 2: big city, real car physics, destruction, wanted level.
# Started with "-- --bot=chase" (see tools/record.sh) a bot drives the car and a
# director stages the run for a recorded video.

const HEAT_MAX := 100.0
const LEVEL_HEAT := [1.0, 12.0, 30.0, 55.0, 85.0]   # heat needed for 1..5 stars
const POLICE_CAP := [0, 3, 5, 6, 8, 10]              # by wanted level
const BUSTED_TIME := 7.0                             # seconds boxed in before you are busted

var world: World
var fx: Fx
var hud: Hud
var player: Car
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var rain: CPUParticles3D
var heli: Heli
var heli_forced := false   # director: the helicopter is out from the start
var police: Array[Car] = []
var blocks: Array[Car] = []
var bot: Bot = null
var stunts: Stunts = null
var director: Director = null
var cfg := {}
var vertical := false

var game_over := false
var end_title := ""
var over_time := -1.0
var clock := 0.0          # real seconds since start; slow motion does not slow it
var time_alive := 0.0
var score := 0
var bonus := 0
var cubes := 0
var cells_down := 0
var wrecked := 0
var heat := 0.0
var level := 0
var busted := 0.0
var busted_peak := 0.0
var protect := false      # director only: the run cannot end yet
var cap_bonus := 0
var spawn_gap := Vector2(2.5, 4.5)
var spawn_t := 2.5
var block_t := 22.0
var shake := 0.0
var cam_dir := Vector3(0, 0, -1)
var cam_mode := "chase"
var cam_cut := false
var cam_steer := 0.0
var cam_cop_back := 0.0
var fov_kick := 0.0
var tod := 0.22
var tod_rate := 1.0 / 480.0
var rain_amt := 0.0
var grip_mult := 1.0
var escape_t := 0.0
var best := 0
var heli_t := 0.0
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
var events: Array = []
var stats := {"collapses": 0, "chains": 0, "gas": 0, "big_air": 0, "drifts": 0, "smash": 0,
	"cops_spawned": 0, "max_cops": 0, "mega_jump": 0, "near_miss": 0, "heli_down": 0}
var cam_anchor := Vector3.ZERO
var traffic_cap := 12          # director: rush hour has far more cars
var traffic_ahead := false     # ... and puts them on the roads ahead of the player
var cam_focus_heli := false   # the anchor camera looks between the car and the helicopter


func _ready() -> void:
	cfg = _parse_args()
	if str(cfg.get("seed", "")) != "":
		seed(int(cfg["seed"]))
	else:
		randomize()
	vertical = cfg.get("orientation", "") == "vertical"
	tod = {"day": 0.22, "dusk": 0.47, "night": 0.72}.get(cfg.get("time", ""), 0.22)
	_load_best()
	_make_env()
	fx = Fx.new()
	add_child(fx)
	fx.setup(self)
	world = World.new()
	add_child(world)
	world.setup(self, fx)
	_make_player()
	if cfg.has("bot"):
		bot = Bot.new()
		bot.setup(self)
		stunts = Stunts.new()
		add_child(stunts)
		stunts.setup(self)
		director = Director.new()
		add_child(director)
		director.setup(self, cfg)
	world.load_around(player.global_position, true)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_make_heli()
	_make_rain()
	cam.global_position = player.global_position + Vector3(0, 4, 9)
	if director != null:
		director.start()


# Arguments after "--" on the command line, as --key=value.
func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


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
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
	if vertical:
		# portrait video: keep the horizontal view wide, let the vertical one grow
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 56.0
	else:
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
	heli = Heli.new()
	add_child(heli)
	heli.setup(self)


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
	clock += delta / maxf(Engine.time_scale, 0.01)
	delta = minf(delta, 0.05)
	if Engine.time_scale < 1.0 and clock >= slowmo_until:
		_set_time_scale(1.0)
	_update_traffic(delta)
	if not game_over:
		time_alive += delta
		if bot != null:
			bot.drive(delta)
		else:
			player.input_gas = hud.in_gas
			player.input_steer = hud.in_steer
			player.input_hb = hud.in_hb
			player.input_nitro = hud.in_nitro
		_update_police(delta)
		_update_wanted(delta)
		_update_busted(delta)
	score = int(time_alive) + cubes + wrecked * 100 + bonus
	world.load_around(player.global_position, false)
	if director != null:
		director.tick(delta)
	_update_heli(delta)
	_update_cam(delta)
	_update_env(delta)
	shake = maxf(0.0, shake - delta * 1.8)
	fov_kick = move_toward(fov_kick, 0.0, delta * 14.0)
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


func alive_police() -> int:
	var n := 0
	for c in police:
		if is_instance_valid(c) and not c.dead:
			n += 1
	return n


# ------------------------------------------------------------ police

func _make_police(pos: Vector3, yaw: float) -> Car:
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
	c.add_siren()
	police.append(c)
	stats["cops_spawned"] += 1
	return c


# Director only: a police car already driving at `spd` along `yaw`.
func spawn_police_at(pos: Vector3, yaw: float, spd: float) -> Car:
	var c := _make_police(pos, yaw)
	c.linear_velocity = Vector3(-sin(yaw), 0, -cos(yaw)) * spd
	return c


func _spawn_police() -> void:
	if director != null and director.spawn_police():
		return
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
		_make_police(pos, yaw)
		return


func spawn_swat() -> void:
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
	c.add_siren()
	police.append(c)
	stats["cops_spawned"] += 1
	swat = c
	swat_t = 40.0
	hud.banner("SWAT TRUCK INCOMING")
	log_event("swat")


func _update_traffic(dt: float) -> void:
	civ_t -= dt
	for c in civs.duplicate():
		if not is_instance_valid(c):
			civs.erase(c)
		elif c.global_position.distance_to(player.global_position) > 240.0:
			civs.erase(c)
			c.queue_free()
	if civ_t <= 0.0 and civs.size() < traffic_cap:
		civ_t = 0.5 if traffic_cap <= 12 else 0.15
		var centre := player.global_position
		var dmin := 70.0
		var dmax := 170.0
		if traffic_ahead:
			var fv := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
			if fv.length() < 5.0:
				fv = -player.global_transform.basis.z
			centre += fv.normalized() * 80.0
			dmin = 5.0
			dmax = 95.0
		var r: Dictionary = world.road_spawn(centre, dmin, dmax)
		if traffic_ahead and (r["pos"] as Vector3).distance_to(player.global_position) < 40.0:
			return
		var yaw: float = r["yaw"]
		var d := Vector3(roundf(-sin(yaw)), 0, roundf(-cos(yaw)))
		var c := CivCar.new()
		add_child(c)
		var kinds := ["sedan", "sedan", "suv", "van", "taxi"]
		var ck: String = kinds[randi() % kinds.size()]
		c.build(self, CivCar.TAXI if ck == "taxi" else CivCar.palette(randi()), true, ck)
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
	spawn_roadblock_at(r["center"], r["yaw"])


# Two police cars parked across the road at `center`, leaving a narrow gap in the middle.
func spawn_roadblock_at(center: Vector3, yaw: float) -> void:
	var along := Vector3(-sin(yaw), 0, -cos(yaw))
	var across := along.cross(Vector3.UP)
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
	var cap: int = POLICE_CAP[level] + (cap_bonus if level > 0 else 0)
	spawn_t -= dt
	if spawn_t <= 0.0 and police.size() < cap:
		spawn_t = randf_range(spawn_gap.x, spawn_gap.y)
		_spawn_police()
	_assign_attackers()
	for c in police.duplicate():
		if not is_instance_valid(c):
			police.erase(c)
		elif c.global_position.distance_to(player.global_position) > 320.0:
			police.erase(c)
			c.queue_free()
		elif not c.is_swat:
			c.top_speed = 25.0 + level * 2.2
			if director != null:
				# video runs: rubber-band the pack so it stays close enough to be filmed
				var gap: float = c.global_position.distance_to(player.global_position)
				c.top_speed = maxf(c.top_speed, player.speed + clampf((gap - 18.0) * 0.12, 0.0, 12.0))
				c.vmax = c.top_speed + 6.0
	for c in blocks.duplicate():
		if not is_instance_valid(c):
			blocks.erase(c)
		elif c.global_position.distance_to(player.global_position) > 280.0:
			blocks.erase(c)
			c.queue_free()
	stats["max_cops"] = maxi(stats["max_cops"], alive_police())
	if level >= 3 and (swat == null or not is_instance_valid(swat) or swat.dead):
		swat_t -= dt
		if swat_t <= 0.0:
			spawn_swat()
	if level >= 2 and (director == null or director.auto_roadblocks):
		block_t -= dt
		if block_t <= 0.0 and blocks.size() < 4:
			block_t = maxf(10.0, 30.0 - level * 3.0)
			_spawn_roadblock()


# At most two police cars press the player at once. The rest shadow at a distance and
# take over when one is wrecked or backs off: this stops a pack boxing the player in.
func _assign_attackers() -> void:
	var live: Array[Car] = []
	for c in police:
		if is_instance_valid(c) and not c.dead and not c.is_swat:
			live.append(c)
	var pp := player.global_position
	live.sort_custom(func(a: Car, b: Car) -> bool: return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	for i in live.size():
		live[i].hold = i >= 2


# Every crime adds heat. The first one puts you on the police radar.
func add_heat(a: float) -> void:
	heat = minf(heat + a, HEAT_MAX)
	if a > 0.0:
		escape_t = 0.0
		if level == 0:
			heat = maxf(heat, LEVEL_HEAT[0])


func _update_wanted(dt: float) -> void:
	var nearest := 1e9
	for c in police:
		if is_instance_valid(c) and not c.dead:
			nearest = minf(nearest, c.global_position.distance_to(player.global_position))
	if nearest < 45.0:
		add_heat(dt * 0.35)
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
	if director != null:
		heat = maxf(heat, director.heat_floor)
	var nl := level_for(heat)
	if nl != level:
		if nl > level:
			hud.banner("WANTED LEVEL %d" % nl)
		elif nl == 0:
			hud.banner("ESCAPED")
			_call_off_police()
		else:
			hud.banner("HEAT DOWN")
		level = nl


func level_for(h: float) -> int:
	var n := 0
	for t in LEVEL_HEAT:
		if h >= t:
			n += 1
	return n


# Heat is gone: the units still out there (all far away by now) go home.
func _call_off_police() -> void:
	for c in police.duplicate():
		if is_instance_valid(c) and not c.dead:
			police.erase(c)
			c.queue_free()


# Nearly stopped with police right next to you fills the meter; driving away drains it.
func _update_busted(dt: float) -> void:
	var boxed := false
	if level > 0 and player.speed < 2.5:
		for c in cars_near(player.global_position, 7.5):
			if not c.is_player:
				boxed = true
				break
	if boxed:
		busted = minf(1.0, busted + dt / BUSTED_TIME)
	else:
		busted = maxf(0.0, busted - dt / 2.5)
	if protect:
		busted = minf(busted, 0.92)
	busted_peak = maxf(busted_peak, busted)
	if busted >= 1.0:
		player.engine_force = 0.0
		player.brake = 20.0
		_end_game("BUSTED")


func _update_heli(dt: float) -> void:
	var on := (level >= 4 or heli_forced) and not game_over and not heli.down
	if on and not heli.visible:
		heli.summon()
		log_event("heli")
	elif not on and heli.visible and heli.state in ["chase", "intercept"]:
		heli.visible = false
		heli.chop.stop()
	if heli.visible:
		heli.tick(dt)


# ------------------------------------------------------------ camera and environment

func cinematic(target: Vector3, height: float) -> void:
	cine_t = 2.6
	cine_target = target
	cine_h = height
	var away := player.global_position - target
	cine_ang = atan2(away.z, away.x)


func _update_cam(dt: float) -> void:
	if game_over and director != null:
		# recorded runs: slow orbit around the wreck for the rest of the clip
		cine_ang += dt * 0.3
		var c := player.global_position
		var cp := c + Vector3(cos(cine_ang) * 15.0, 8.0, sin(cine_ang) * 15.0)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3(0, 2.0, 0), cp, 1))
		if not hit.is_empty():
			cp = (hit["position"] as Vector3) + (c - cp).normalized() * 1.0
		cam.global_position = cam.global_position.lerp(cp, 1.0 - exp(-2.0 * dt))
		cam.look_at(c + Vector3(0, 1.0, 0), Vector3.UP)
		return
	if cine_t > 0.0 and not game_over:
		cine_t -= dt
		cine_ang += dt * 0.35
		var dist := 24.0 + cine_h * 0.9
		var cp := cine_target + Vector3(cos(cine_ang) * dist, maxf(cine_h * 0.45 + 5.0, 12.0), sin(cine_ang) * dist)
		# stay out of buildings: pull in toward the target if a wall is in the way
		var from := cine_target + Vector3(0, 3.0, 0)
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, cp, 1))
		if not hit.is_empty():
			cp = (hit["position"] as Vector3) + (from - cp).normalized() * 1.0
		cam.global_position = cam.global_position.lerp(cp, 1.0 - exp(-3.0 * dt))
		cam.look_at(cine_target + Vector3(0, cine_h * 0.3, 0), Vector3.UP)
		return
	match cam_mode:
		"anchor":
			_cam_anchor(dt)
		"front":
			_cam_front(dt)
		"heli":
			_cam_heli(dt)
		_:
			_cam_chase(dt)
	cam_cut = false


func _cam_chase(dt: float) -> void:
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var vel := Vector3(player.linear_velocity.x, 0, player.linear_velocity.z)
	var want := fwd
	if vel.length() > 8.0 and player.fwd_speed > 0.0:
		want = fwd.lerp(vel.normalized(), 0.45).normalized()
	cam_dir = cam_dir.lerp(want, 1.0 - exp(-4.0 * dt)).normalized()
	cam_steer = lerpf(cam_steer, player.steer_smooth, 1.0 - exp(-5.0 * dt))
	var spd := player.speed
	var back := 8.2 + spd * 0.05
	var up := 3.5 + spd * 0.02
	var ahead := 6.0
	var cop_back := 0.0
	if director != null:
		# keep the nearest police behind the player in the frame: the camera backs up
		# to stay behind them (the longer the gap, the further back and higher)
		var sideways := fwd.cross(Vector3.UP)
		for c in police:
			if not is_instance_valid(c) or c.dead:
				continue
			var rel := c.global_position - player.global_position
			rel.y = 0.0
			var behind := -rel.dot(fwd)
			if behind > 0.0 and behind < 38.0 and absf(rel.dot(sideways)) < 14.0:
				cop_back = maxf(cop_back, behind)
		cam_cop_back = lerpf(cam_cop_back, minf(cop_back, 24.0), 1.0 - exp(-2.5 * dt))
	if vertical:
		# higher and steeper, so the police behind the car stay in the frame
		back = 6.5 + spd * 0.05
		up = 4.8 + spd * 0.03
		ahead = 5.0
	back += cam_cop_back * 0.75
	up += cam_cop_back * 0.3
	var target := _cam_clear(player.global_position - cam_dir * back + Vector3(0, up, 0))
	var p := target if cam_cut else cam.global_position.lerp(target, 1.0 - exp(-9.0 * dt))
	p += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake
	cam.global_position = p + _intro_off()
	var side := cam_dir.cross(Vector3.UP)
	cam.look_at(player.global_position + cam_dir * ahead - side * cam_steer * 2.5 + Vector3(0, 1.2, 0), Vector3.UP)
	var base := 56.0 if vertical else 62.0
	var fov := base + clampf(spd, 0.0, 40.0) * (0.2 if vertical else 0.5) + ((5.0 if vertical else 8.0) if player.nitro_active else 0.0) + fov_kick
	cam.fov = lerpf(cam.fov, fov, 4.0 * dt)


# Ahead of the car looking back: the car coming at you with the police behind it.
func _cam_front(dt: float) -> void:
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var ahead := 8.0 + player.speed * 0.18 if vertical else 11.0 + player.speed * 0.25
	var target := _cam_clear(player.global_position + fwd * ahead + side * 1.6 + Vector3(0, 2.6 if vertical else 3.2, 0))
	cam.global_position = (target if cam_cut else cam.global_position.lerp(target, 1.0 - exp(-10.0 * dt))) + _intro_off()
	cam.look_at(player.global_position - fwd * 5.0 + Vector3(0, 0.8, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, 58.0 + fov_kick, 6.0 * dt)


# A fixed camera beside the action that turns to follow the car (stunt photographer).
func _cam_anchor(dt: float) -> void:
	var p := cam_anchor + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake
	cam.global_position = p
	var focus := player.global_position + Vector3(0, 1.5, 0)
	if heli.visible and heli.state in ["crash", "wreck"]:
		focus = heli.global_position
	elif cam_focus_heli and heli.visible:
		focus = (player.global_position + heli.global_position) * 0.5
	cam.look_at(focus, Vector3.UP)
	cam.fov = lerpf(cam.fov, 52.0 + fov_kick, 6.0 * dt)


# Drone shot at the start of a video run: the camera comes down from above the city.
func _intro_off() -> Vector3:
	if director == null or clock > 2.6:
		return Vector3.ZERO
	return Vector3(0, 34.0 * (1.0 - smoothstep(0.0, 2.6, clock)), 0)


# High above and behind: shows the whole pack of police.
func _cam_heli(dt: float) -> void:
	var target := player.global_position - cam_dir * 12.0 + Vector3(0, 22.0, 0)
	cam.global_position = target if cam_cut else cam.global_position.lerp(target, 1.0 - exp(-4.0 * dt))
	cam.look_at(player.global_position + cam_dir * 6.0, Vector3.UP)
	cam.fov = lerpf(cam.fov, 62.0 + fov_kick, 4.0 * dt)


# Pulls the camera in front of any wall between it and the car.
func _cam_clear(want: Vector3) -> Vector3:
	var from := player.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, want, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return want
	return (r["position"] as Vector3) + (from - want).normalized() * 0.6


func _update_env(dt: float) -> void:
	tod = fposmod(tod + dt * tod_rate, 1.0)
	var e := sin(tod * TAU)
	var day := clampf(e * 2.5 + 0.35, 0.0, 1.0)
	var night := 1.0 - day
	var rain_target := 1.0 if sin(tod * TAU * 2.0 + 4.0) > 0.88 else 0.0
	if cfg.get("weather", "") == "rain":
		rain_target = 1.0
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

func log_event(kind: String) -> void:
	events.append({"t": snappedf(clock, 0.01), "type": kind})


# kick > 1 throws cars harder and sets them tumbling (director traps).
func explode_at(pos: Vector3, radius: float, force: float, dmg: float, hurt_player: bool = true, kick: float = 1.0) -> void:
	world.damage_area(pos, radius, force)
	for c in _all_cars():
		if c.dead or (c.is_player and not hurt_player):
			continue
		var d := c.global_position.distance_to(pos)
		var reach := radius * 1.8
		if d < reach:
			var fall := 1.0 - d / reach
			var dirv := (c.global_position - pos).normalized() + Vector3(0, 0.5, 0)
			c.apply_central_impulse(dirv * force * c.mass * 0.09 * fall * kick)
			if kick > 1.0:
				c.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * c.mass * 1.5 * kick * fall)
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
	fov_kick = maxf(fov_kick, 4.0 + radius * 0.5)
	if radius >= 6.5 and director != null and player.global_position.distance_to(pos) < 60.0:
		hud.flash(0.28)
	boom_times.append(clock)
	while boom_times.size() > 0 and clock - boom_times[0] > 1.6:
		boom_times.remove_at(0)
	if boom_times.size() >= 3 and player.global_position.distance_to(pos) < 140.0:
		bonus += 150
		hud.banner("CHAIN REACTION x%d" % boom_times.size())
		if boom_times.size() == 3:
			stats["chains"] += 1
			log_event("chain")
		slowmo(1.3, 0.35)


func slowmo(real_dur: float, scale: float) -> void:
	if clock < slowmo_cd or game_over:
		return
	slowmo_until = clock + real_dur
	slowmo_cd = clock + real_dur + 3.5
	_set_time_scale(scale)


func _set_time_scale(s: float) -> void:
	Engine.time_scale = s
	# more physics steps per game second while slowed, so there is still one step
	# per rendered frame and slow motion stays smooth instead of stepping
	Engine.physics_ticks_per_second = roundi(60.0 / s)
	AudioServer.playback_speed_scale = maxf(s, 0.5)


func big_boom(pos: Vector3, radius: float) -> void:
	explode_at(pos, radius, 30.0, 60.0)
	bonus += 800
	stats["gas"] += 1
	log_event("gas")
	hud.banner("GAS STATION +800")
	shake_cam(1.2)
	if player.global_position.distance_to(pos) < 150.0:
		slowmo(1.8, 0.3)
		if director != null:
			cinematic(pos, 12.0)


func on_big_air(t: float) -> void:
	var pts := int(t * 150.0)
	bonus += pts
	stats["big_air"] += 1
	log_event("big_air")
	if t > 0.8 and bot != null and bot.plan_name == "mega":
		stats["mega_jump"] += 1
		bonus += 500
		log_event("mega_jump")
		hud.banner("MEGA JUMP +%d" % (pts + 500))
	else:
		hud.banner("BIG AIR +%d" % pts)


func on_drift(t: float) -> void:
	if t > 1.2:
		var pts := int(t * 60.0)
		bonus += pts
		stats["drifts"] += 1
		log_event("drift")
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
	if player.global_position.distance_to(pos) < 12.0:
		add_heat(0.3)


func on_civ_wreck(c: CivCar) -> void:
	bonus += 50
	add_heat(1.5)


func on_cells_destroyed(n: int) -> void:
	cubes += n
	cells_down += n
	add_heat(n * 0.012)


func on_car_dead(car: Car) -> void:
	explode_at(car.global_position, 7.0 if car.is_player else 5.0, 12.0, 25.0)
	car.fire.emitting = true
	car.smoke.emitting = true
	car.engine_force = 0.0
	car.brake = 20.0
	if car.is_swat:
		bonus += 1000
		hud.banner("SWAT DOWN +1000")
		log_event("swat_down")
		slowmo(1.6, 0.3)
	if car.is_player:
		_end_game("WRECKED")
	else:
		wrecked += 1
		add_heat(6.0)
		log_event("cop_wrecked")
		police.erase(car)
		blocks.erase(car)
		if not car.is_swat:
			hud.banner("WRECKED +100")
		get_tree().create_timer(14.0).timeout.connect(func():
			if is_instance_valid(car):
				car.queue_free())


func _end_game(title: String) -> void:
	if game_over:
		return
	game_over = true
	end_title = title
	over_time = clock
	_set_time_scale(1.0)
	_save_best()
	score = int(time_alive) + cubes + wrecked * 100 + bonus
	log_event("game_over")
	if director != null:
		hud.show_over(director.end_text(title))
	else:
		hud.show_over("%s\n\nScore  %d\nBest  %d\nPolice wrecked  %d\n\nTap to play again" % [title, score, best, wrecked])


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
		stats["smash"] += 1
		log_event("smash")
		hud.banner("BIG SMASH")


func on_building_collapse(b: Building) -> void:
	bonus += 500
	add_heat(4.0)
	stats["collapses"] += 1
	log_event("collapse")
	hud.banner("BUILDING DOWN +500")
	var d := b.center().distance_to(player.global_position)
	if d < 170.0:
		slowmo(2.0, 0.35)
		if b.ny >= 8 or director != null:
			cinematic(Vector3(b.center().x, 0.0, b.center().z), b.ny * Building.C)


func shake_cam(a: float) -> void:
	shake = maxf(shake, minf(a, 1.2))


func play_sfx(name: String, pos: Vector3, db: float = 0.0) -> void:
	fx.play(name, pos, db)


func restart() -> void:
	_set_time_scale(1.0)
	get_tree().reload_current_scene()


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://best2.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))


func _save_best() -> void:
	if director != null:
		return
	var s := int(time_alive) + cubes + wrecked * 100 + bonus
	if s > best:
		best = s
		var cf := ConfigFile.new()
		cf.set_value("score", "best", best)
		cf.save("user://best2.cfg")
