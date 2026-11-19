extends "res://main.gd"
# A single-shot recording of an actual VehicleBody3D run. Only the starting grid
# position and the bot route are authored. The car's motion is owned by physics.

const Roadster := preload("res://story/roadster.gd")
const RAMP_START := Vector3(-69.0, 0.0, -3.0)
const FORWARD := Vector3.LEFT
const RUN_SECONDS := 11.0
var ramp_lip: Vector3
var pursuer: Car
var samples: Array[Dictionary] = []
var next_sample := 0.0

func _parse_args() -> Dictionary:
	var options := super._parse_args()
	options.erase("bot")  # use the bot controls without the video's automatic cuts and slow motion
	return options

func _ready() -> void:
	super._ready()
	rail.auto = false
	traffic_cap = 0
	spawn_t = INF
	block_t = INF
	protect = true
	hud.hide()
	player.global_position = Vector3(3.5, 0.9, 43.0)
	var roadster := player.vis.get_child(0) as MeshInstance3D
	roadster.mesh = Roadster.mesh()
	var pink := Color("#ff5c9a")
	player.mat_body.set_shader_parameter("color", pink)
	player.body_color = pink
	Roadster.make_cabin(player.vis, pink)

	bot = Bot.new()
	bot.setup(self)
	bot.external = true
	bot.cruise = 30.0
	stunts = Stunts.new()
	add_child(stunts)
	stunts.setup(self)
	var ramp := stunts.build_kicker(RAMP_START, FORWARD)
	ramp_lip = ramp["lip"]
	var approach := [
		Vector3(3.5, 0, 16.0), Vector3(2.7, 0, 5.0),
		Vector3(-2.0, 0, -0.7), Vector3(-10.0, 0, -3.0)
	]
	var kinds := ["road", "road", "road", "road"]
	approach.append_array(ramp["pts"])
	kinds.append_array(ramp["kinds"])
	approach.append(Vector3(-220.0, 0, -3.0))
	kinds.append("road")
	bot.set_plan(approach, kinds, "physics_preview")
	pursuer = spawn_police_at(Vector3(3.4, 0.9, 57.0), 0.0, 1.5)
	pursuer.dmg_scale = 0.3
	cam_cut = true

func _process(delta: float) -> void:
	super._process(delta)
	if clock >= next_sample:
		next_sample = clock + 0.049
		var contacts := 0
		for wheel: VehicleWheel3D in player.wheels:
			if wheel.is_in_contact():
				contacts += 1
		var p := player.global_position
		var velocity := player.linear_velocity
		samples.append({
			"t": snappedf(clock, 0.001),
			"position": [p.x, p.y, p.z],
			"velocity": [velocity.x, velocity.y, velocity.z],
			"contacts": contacts,
			"airtime": player.airtime,
			"time_scale": Engine.time_scale,
			"in_frame": cam.is_position_in_frustum(player.global_position + Vector3.UP * 0.7),
			"police_in_frame": is_instance_valid(pursuer) and cam.is_position_in_frustum(pursuer.global_position + Vector3.UP * 0.7),
		})
	if clock >= RUN_SECONDS:
		var result := {
			"ramp_start": [RAMP_START.x, RAMP_START.y, RAMP_START.z],
			"ramp_lip": [ramp_lip.x, ramp_lip.y, ramp_lip.z],
			"samples": samples
		}
		var out := FileAccess.open(str(cfg.get("summary", "")), FileAccess.WRITE)
		if out == null:
			push_error("Physics preview needs a writable --summary file")
			get_tree().quit(1)
			return
		out.store_string(JSON.stringify(result))
		out.close()
		get_tree().quit()
