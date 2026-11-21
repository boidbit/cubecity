extends "res://main.gd"
# The film drives the same Cube City assets on timed marks. Game traffic, scoring and AI
# stay idle while the story owns the camera and movement.

const Rig := preload("res://story/rig.gd")
const Roadster := preload("res://story/roadster.gd")
const StoryVan := preload("res://story/van.gd")
const DURATION := 28.0
const TURN_Z := -100.0
const RAIL_X := 78.0
const INK := Color("#152134")
const GOLD := Color("#ffd270")

var script_data := {}
var van: Node3D
var annex: Building
var annex_cells := 0
var barrels := {}
var bag: Node3D
var lid: Node3D
var reveal_actor: Node3D
var driver_actor: Node3D
var van_loot: Node3D
var title_label: Label
var subtitle_label: Label
var elapsed := 0.0
var previous := -1.0
var actions: Array[Dictionary] = []
var lines: Array[Dictionary] = []
var materials := {}

func _ready() -> void:
	cfg = _parse_args()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(cfg.get("story", ""))))
	if not data is Dictionary or data.get("scene") != "campus_action":
		push_error("campus_action needs a campus action screenplay")
		get_tree().quit(1)
		return
	script_data = data
	seed(int(cfg.get("seed", 7)))
	vertical = cfg.get("orientation", "") == "vertical"
	tod = {"day": 0.22, "dusk": 0.47, "night": 0.72}.get(cfg.get("time", "dusk"), 0.47)
	_make_env()
	cam.make_current()
	fx = Fx.new()
	add_child(fx)
	fx.setup(self)
	world = World.new()
	add_child(world)
	world.setup(self, fx)
	world.props.set_physics_process(false)
	_build_campus()
	world.load_around(_city(Vector3(0, 0, -35)), true)
	rail = Rail.new()
	add_child(rail)
	rail.setup(self)
	rail.set_physics_process(false)
	rail.train.sync_to_physics = false
	rail.train.visible = true
	_make_player()
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	player.contact_monitor = false
	player.set_physics_process(false)
	_make_heli()
	_make_rain()
	_update_env(0.0)
	_build_actors()
	_build_overlay()
	_frame(0.0)

# The first stretch follows the east-west road at z=0; the service turn goes north
# on x=0 to Cube City's existing railway at z=-36.
func _city(p: Vector3) -> Vector3:
	var across := p.x if p.x <= 6.0 else 6.0 + (p.x - 6.0) * (30.0 / 72.0)
	return Vector3(p.z - TURN_Z, p.y, -across)

func _group(parent: Node3D, at := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	node.position = at
	return node

func _material(color: Color, glow := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := str(color) + "/" + str(glow) + "/" + str(metal)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.78 if metal == 0.0 else 0.33
		mat.metallic = metal
		if glow > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = glow
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[key] = mat
	return materials[key]

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow := 0.0, metal := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color, glow, metal)
	parent.add_child(node)
	node.position = at
	return node

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := 0.0, metal := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, color, glow, metal)

func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, metal := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	return _mesh(parent, mesh, at, color, 0.0, metal)

func _sign(parent: Node3D, label: String, at: Vector3, width: float, height: float, color := GOLD) -> void:
	_box(parent, at, Vector3(width, height, 0.16), INK)
	var sign := Label3D.new()
	sign.text = label
	sign.font_size = 112
	sign.outline_size = 8
	sign.pixel_size = minf(height / 195.0, width / maxf(float(label.length()) * 90.0, 100.0))
	sign.modulate = color
	sign.no_depth_test = false
	parent.add_child(sign)
	sign.position = at + Vector3(0, 0, 0.096)


func _native_building(at: Vector3, width: int, depth: int, height: int, tint: Color, variant: int) -> Building:
	var b := Building.new()
	var floors := PackedInt32Array()
	floors.resize(width * depth)
	floors.fill(height)
	b.setup(world, at, width, depth, floors, tint, World.encode_style(0.15, variant))
	var block := world.block_of(at)
	world.block_buildings[block].append(b)
	world.buildings.append(b)
	return b

func _build_campus() -> void:
	# Reserve the two street-front lots for campus buildings. Keep the original road
	# surface, skyline, city blocks, roadside props, and façade material.
	var campus_block := world.block_of(Vector3(105, 0, -21))
	var annex_block := world.block_of(Vector3(30, 0, -17))
	world.block_buildings[campus_block] = []
	world.block_buildings[annex_block] = []
	_native_building(Vector3(99, 0, -28), 13, 7, 8, Color("#ad7664"), 2)
	_native_building(Vector3(77, 0, -27), 8, 7, 6, Color("#a28d77"), 1)
	annex = _native_building(Vector3(18, 0, -20), 10, 5, 6, Color("#b18770"), 2)
	annex_cells = annex.total_alive()
	_sign(self, "CUBE CITY COLLEGE", Vector3(109, 4.8, -13.82), 11.7, 1.15)
	_sign(self, "LIBRARY", Vector3(85, 4.5, -12.82), 6.7, 0.94)
	_sign(self, "CAMPUS ANNEX", Vector3(28, 5.0, -9.82), 9.2, 1.1)
	var entrance := _group(self, Vector3(119, 0, -9.0))
	for x in [-4.8, 4.8]:
		_box(entrance, Vector3(x, 1.6, 0), Vector3(0.85, 3.2, 0.85), Color("#a28d77"))
	_sign(entrance, "CAMPUS ENTRY", Vector3(0, 3.25, 0), 10.4, 0.78)
	_sign(self, "SERVICE EXIT", Vector3(9.4, 3.4, -6.7), 5.4, 0.72)
	barrels = world.props.spawn_barrels(_city(Vector3(6.3, 0, -68.6)))
	# A stock Cube City police car blocks one lane and leaves the chase lane open.
	var blocker := _make_police(Vector3(36, 0, 3.0), PI / 2 + 0.27)
	blocker.freeze = true
	blocker.collision_layer = 0
	blocker.collision_mask = 0
	blocker.set_physics_process(false)

func _build_actors() -> void:
	var paint := Color("#ff5c9a")
	var shell := player.vis.get_child(0) as MeshInstance3D
	shell.mesh = Roadster.mesh()
	player.mat_body.set_shader_parameter("color", paint)
	player.body_color = paint
	Roadster.make_cabin(player.vis, paint)
	var lead: Dictionary = script_data.get("cast", {}).get("shona", {})
	var driver := Rig.new()
	player.vis.add_child(driver)
	driver.position = Vector3(Roadster.SEAT_X, Roadster.SEAT_Y, Roadster.SEAT_Z)
	driver.build("shona", lead.get("look", {}), true, Roadster.SEAT_X)
	driver.set_state("scared", "idle", false)
	driver_actor = driver

	var pursuit := StoryVan.new()
	add_child(pursuit)
	pursuit.setup(self, Color("#26262b"))
	pursuit.set_process(false)
	pursuit.body.collision_layer = 0
	van = pursuit
	var stop := _group(self, Vector3(8.85, 0, _city(Vector3(111, 0, 0)).z))
	bag = _group(stop, Vector3(0.06, 0.82, -0.36))
	var leather := Color("#61416a")
	_box(bag, Vector3(0, -0.27, 0), Vector3(1.48, 0.12, 0.96), leather)
	for side in [-1.0, 1.0]:
		_box(bag, Vector3(side * 0.69, -0.08, 0), Vector3(0.12, 0.40, 0.96), leather)
		_box(bag, Vector3(0, -0.08, side * 0.43), Vector3(1.42, 0.40, 0.12), leather)
	_box(stop, Vector3(0, 0.37, -0.37), Vector3(1.57, 0.48, 1.02), Color("#84786c"))
	lid = _group(bag, Vector3(0, 0.12, -0.46))
	_box(lid, Vector3(0, 0, 0.47), Vector3(1.49, 0.09, 0.98), leather.lightened(0.14))
	_make_loot(bag, str(script_data.get("reveal_prop", "tiffin")))
	van_loot = _group(van, Vector3(0, 1.2, 2.80))
	_make_loot(van_loot, str(script_data.get("prize", "trophy")))
	var rig := Rig.new()
	add_child(rig)
	rig.build("shona", lead.get("look", {}), false, 0.0)
	rig.stand_at(stop.position + Vector3(-0.88, 0, 0.05), 0.9)
	rig.set_state("shock", "idle", false)
	reveal_actor = rig

func _make_loot(parent: Node3D, kind: String) -> void:
	match kind:
		"tiffin":
			for y in [-0.14, -0.01, 0.12]:
				_cylinder(parent, Vector3(0, y, 0), 0.27, 0.12, Color("#c1d6df"), 0.62)
			_box(parent, Vector3(0, 0.225, 0), Vector3(0.23, 0.073, 0.08), INK)
		"books":
			for i in range(3):
				var book := _box(parent, Vector3(0, -0.11 + 0.12 * i, 0), Vector3(0.55, 0.105, 0.60), [Color("#e16f5f"), Color("#d2ae51"), Color("#61acaf")][i])
				book.rotation.y = i * 0.17
		"medal":
			_cylinder(parent, Vector3(0, 0.12, 0), 0.31, 0.105, GOLD, 0.55).rotation.x = PI / 2
			_box(parent, Vector3(0, 0.37, -0.02), Vector3(0.2, 0.49, 0.065), Color("#d65150"))
		_:
			_cylinder(parent, Vector3(0, -0.16, 0), 0.37, 0.16, INK)
			_cylinder(parent, Vector3(0, 0.12, 0), 0.085, 0.47, GOLD, 0.46)
			var cup := CylinderMesh.new()
			cup.top_radius = 0.29
			cup.bottom_radius = 0.12
			cup.height = 0.36
			_mesh(parent, cup, Vector3(0, 0.44, 0), GOLD, 0.35, 0.48)
			for side in [-1.0, 1.0]:
				_box(parent, Vector3(side * 0.28, 0.42, 0), Vector3(0.14, 0.23, 0.083), GOLD, 0.25, 0.45)

func _label(layer: CanvasLayer, y: float, size: int) -> Label:
	var label := Label.new()
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_factor := viewport_size.y / 960.0
	label.position = Vector2(viewport_size.x * 0.07, viewport_size.y * y)
	label.size = Vector2(viewport_size.x * 0.86, viewport_size.y * 0.16)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", maxi(14, int(size * scale_factor)))
	label.add_theme_constant_override("outline_size", maxi(4, int(8 * scale_factor)))
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.10, 0.95))
	label.add_theme_color_override("font_color", Color("#fff6e6"))
	layer.add_child(label)
	return label

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	title_label = _label(layer, 0.09, 41)
	subtitle_label = _label(layer, 0.72, 36)

# Timed waypoints also drive yaw and wheel speed, so the cuts never reset travel.
func _route(t: float, keys: Array) -> Vector3:
	for i in range(1, keys.size()):
		var before: Vector3 = keys[i - 1]
		var after: Vector3 = keys[i]
		if t <= after.x:
			var k := clampf(inverse_lerp(before.x, after.x, t), 0.0, 1.0)
			return Vector3(lerpf(before.y, after.y, k), 0, lerpf(before.z, after.z, k))
	var last: Vector3 = keys.back()
	return Vector3(last.y, 0, last.z)

const HERO_PATH := [
	Vector3(2.4, 1.8, 28), Vector3(5.4, 1.8, 2), Vector3(8.3, -1.4, -28),
	Vector3(11, -1.25, -50), Vector3(12.1, 2.55, -64), Vector3(13.2, 1.4, -78),
	Vector3(14.5, 1.6, -91), Vector3(14.9, 3.6, -97), Vector3(15.4, 9.2, -101.75),
	Vector3(18, 39, -101.75), Vector3(20.8, 64, -101.75), Vector3(21.32, 69.1, -101.75), Vector3(22.2, 87.0, -101.75),
	Vector3(23.8, 104, -101.75), Vector3(24.5, 108.5, -101.6), Vector3(25.1, 110, -101.35),
	Vector3(26, 110.4, -101.05)]
const VAN_PATH := [
	Vector3(2.4, -1.6, 39), Vector3(5.4, -1.4, 10), Vector3(8.3, 1.7, -21),
	Vector3(11, 1.7, -43), Vector3(12.1, 1.15, -57), Vector3(13.05, 6.3, -68.6),
	Vector3(13.8, 3.7, -75), Vector3(15.2, 1.0, -91), Vector3(16.2, 5.5, -99.4),
	Vector3(16.7, 11.2, -98.3), Vector3(19.3, 40.8, -98.3), Vector3(21.8, 57.5, -98.3),
	Vector3(22.55, 63.0, -98.3), Vector3(23.25, 65.0, -98.3)]

func _pose_car(car: Node3D, time: float, keys: Array, bank: float) -> void:
	var now := _city(_route(time, keys))
	var heading := _city(_route(time + 0.18, keys)) - _city(_route(time - 0.14, keys))
	car.position = now
	if heading.length_squared() > 0.0001:
		car.rotation.y = atan2(-heading.x, -heading.z)
	car.rotation.z = bank


func _frame(t: float) -> void:
	var scene_time := 21.05 + t * 0.50 if t < 2.4 else t
	_pose_car(player, scene_time, HERO_PATH, -0.08 * sin(clampf((scene_time - 14.3) / 1.2, 0.0, 1.0) * PI))
	_pose_car(van, scene_time, VAN_PATH, 0.14 * sin(clampf((scene_time - 12.2) / 1.7, 0.0, 1.0) * PI))
	player.position.y = -0.16
	for wheel: VehicleWheel3D in player.wheels:
		wheel.rotation.x = -minf(scene_time, 25.1) * 20.0
	for wheel: Node3D in van.wheels:
		wheel.rotation.x = -minf(scene_time, 23.25) * 21.0
	heli.visible = scene_time >= 7.0 and scene_time < 24.5
	var target := (player.position + van.position) * 0.5
	heli.position = target + Vector3(8, 14, 4.6)
	heli.rotation.y = player.rotation.y
	heli.rotor.rotation.y = t * 44.0
	heli.tail_rotor.rotation.x = t * 54.0
	heli.spot.visible = heli.visible
	heli.spot.look_at(target + Vector3(0, 0, 0.5))
	rail.train.position = Vector3(-(scene_time - 22.4) * 21.5, 0, world.rail_z())
	rail.train.rotation.y = PI
	_crossing(scene_time)
	bag.visible = scene_time >= 24.65
	lid.rotation.x = -1.56 * smoothstep(24.77, 25.24, scene_time)
	reveal_actor.visible = bag.visible and scene_time < 26.33
	van_loot.visible = t >= 26.33
	driver_actor.update(1.0 / 30.0, null)
	if reveal_actor.visible:
		reveal_actor.update(1.0 / 30.0, null)
	_shot(t)
	_overlay(t)

func _crossing(t: float) -> void:
	var crossing: Dictionary = rail.crossings[8]
	var lowered := smoothstep(19.7, 21.0, t)
	for arm: Dictionary in crossing["arms"]:
		var pivot: Node3D = arm["pivot"]
		var side: float = arm["s"]
		var broken := side < 0.0 and t >= 21.32
		pivot.rotation.z = -side * deg_to_rad(84.0) * (1.0 - lowered) + (0.32 * smoothstep(21.32, 21.66, t) if broken else 0.0)
		pivot.rotation.y = -1.17 * smoothstep(21.32, 21.62, t) if broken else 0.0
	for i in crossing["lamps"].size():
		var lamp: MeshInstance3D = crossing["lamps"][i]
		lamp.material_override = rail.lamp_on if lowered > 0.0 and i % 2 == int(t * 6.0) % 2 else rail.lamp_off

func _set_shot(at: Vector3, aim: Vector3, width: float) -> void:
	cam.position = at
	cam.look_at(aim)
	cam.fov = width

func _shot(t: float) -> void:
	var car := player.position
	var middle := (car + van.position) * 0.5
	if t < 2.4:
		_set_shot(Vector3(-8, 7.3, -23), Vector3(0, 1.6, -37), 49)
	elif t < 5.85:
		_set_shot(Vector3(car.x + 7.3, 4.2, 5.8), Vector3(car.x - 3.3, 2.4, -8.9), 55)
	elif t < 8.45:
		_set_shot(car + Vector3(7.6, 2.1, 2.6), middle + Vector3(-1.8, 0.80, 0.0), 53)
	elif t < 11.6:
		_set_shot(middle + Vector3(24.0, 11.8, 7.7), middle + Vector3(2.3, 6.4, 1.9), 51)
	elif t < 12.88:
		_set_shot(car + Vector3(-6.7, 1.75, 2.7), car + Vector3(1.4, 0.75, 0.4), 48)
	elif t < 14.63:
		var bump := sin((t - 13.05) * 32.0) * maxf(0.0, 0.24 - absf(t - 13.05) * 0.28)
		_set_shot(Vector3(39.4, 6.6 + bump, 6.9), Vector3(28.0, 3.5, -7.4), 55)
	elif t < 17.2:
		_set_shot(car + Vector3(7.7, 4.5, 9.1), car + Vector3(-0.9, 0.78, -5.0), 56)
	elif t < 19.8:
		_set_shot(middle + Vector3(7.1, 3.5, 8.7), middle + Vector3(0.0, 0.95, -2.8), 56)
	elif t < 23.32:
		_set_shot(Vector3(-10.2, 11.7, -28.0), Vector3(0, 1.15, -36.4), 62)
	elif t < 24.65:
		_set_shot(car + Vector3(-3.9, 2.05, -5.6), car + Vector3(0, 0.95, 0), 45)
	elif t < 26.33:
		_set_shot(bag.global_position + Vector3(-0.8, 1.27, 2.40), bag.global_position + Vector3(-0.40, 0.40, 0), 35)
	else:
		_set_shot(van_loot.to_global(Vector3(-1.4, 1.1, 4.2)), van_loot.global_position + Vector3(0, 0.24, 0), 42)

func _overlay(t: float) -> void:
	title_label.text = ""
	if t < 2.4:
		title_label.text = str(script_data.get("hook", "8 SECONDS TO ESCAPE"))
	elif t >= 2.4 and t < 4.9:
		title_label.text = str(script_data.get("mission", "GET THE COLLEGE TROPHY OUT"))
	elif t >= 26.33:
		title_label.text = str(script_data.get("end_text", "THE VAN HAS IT"))
	subtitle_label.text = ""
	for beat: Dictionary in script_data.get("beats", []):
		if not beat.has("say"):
			continue
		var at := float(beat["at"])
		if t >= at and t < at + float(beat.get("dur", 1.0)):
			subtitle_label.text = str(beat.get("sub", ""))

func _event(kind: String, at: float) -> void:
	events.append({"type": kind, "t": at})
	print("CAMPUS EVENT ", kind, " at ", at)


func _process(delta: float) -> void:
	elapsed = minf(DURATION, elapsed + minf(delta, 0.2))
	clock = elapsed
	_frame(elapsed)
	for beat: Dictionary in script_data.get("beats", []):
		if not beat.has("at"):
			continue
		var at := float(beat["at"])
		if previous < at and elapsed >= at:
			if beat.has("say"):
				lines.append({"id": beat["id"], "t": at})
			elif beat.has("sfx"):
				actions.append({"do": "sfx", "type": beat["sfx"], "t": at})
			elif beat.has("music"):
				actions.append({"do": "music", "type": beat["music"], "t": at})
	if previous < 3.2 and elapsed >= 3.2 and world.loaded_blocks.size() > 0:
		_event("campus_established", 3.2)
	if previous < 9.5 and elapsed >= 9.5 and heli.visible and heli.spot.visible:
		_event("helicopter_tracks_chase", 9.5)
	if previous < 13.05 and elapsed >= 13.05 and barrels["alive"]:
		var barrel_node: Node3D = barrels["node"]
		barrels["alive"] = false
		barrel_node.hide()
		fx.explosion(barrel_node.global_position + Vector3.UP * 0.4, 11.0)
		_event("van_barrel_blast", 13.12)
	if previous < 13.35 and elapsed >= 13.35:
		annex._make_detailed()
		annex.collapsing = true
		world.register_collapse(annex)
	if previous < 14.15 and elapsed >= 14.15 and annex.total_alive() < annex_cells:
		_event("annex_facade_collapses", 14.15)
	if previous < 22.4 and elapsed >= 22.4 and player.position.z < world.rail_z() - 4.0 and absf(rail.train.position.x) < 2.0:
		_event("car_clears_before_train", 22.4)
	if previous < 23.26 and elapsed >= 23.26 and van.position.z > world.rail_z() + 4.5 and rail.train.position.x < -10.0:
		_event("train_blocks_van", 23.26)
	if previous < 25.35 and elapsed >= 25.35 and bag.visible and lid.rotation.x < -1.4:
		_event("wrong_bag_revealed", 25.35)
	if previous < 26.4 and elapsed >= 26.4 and van_loot.visible:
		_event("prize_in_van", 26.4)
	previous = elapsed
	if elapsed >= DURATION:
		_finish()

# The game normally adds a HUD message and slow motion. This scene has its own cut.
func on_building_collapse(_building: Building) -> void:
	pass

func _write(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Campus scene could not write " + path)
		return false
	file.store_string(JSON.stringify(payload))
	return true

func _finish() -> void:
	var log_ok := _write(str(cfg.get("story_log", "")), {"lines": lines, "actions": actions, "events": events,
		"ending": "cliffhanger", "end": 26.33})
	var summary_ok := _write(str(cfg.get("summary", "")), {"mode": "campus_action", "duration": DURATION, "end": "finished"})
	get_tree().quit(0 if log_ok and summary_ok else 1)
