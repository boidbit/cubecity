extends Node3D
# A staged film set. Distances and camera cuts use the same clock as the score and subtitles.

const Rig := preload("res://story/rig.gd")
const DURATION := 28.0
const TURN_Z := -100.0
const RAIL_X := 78.0
const INK := Color("#152134")
const ROAD := Color("#353e4d")
const BRICK := Color("#a14946")
const CREAM := Color("#e0be97")
const GLASS := Color("#253c53")
const GOLD := Color("#ffd270")

var args := {}
var script_data := {}
var camera: Camera3D
var hero: Node3D
var van: Node3D
var heli: Node3D
var rotor: Node3D
var beam: MeshInstance3D
var crossing_arm: Node3D
var rail_lamp: MeshInstance3D
var train: Node3D
var barrels: Node3D
var facade: Node3D
var blast_flash: OmniLight3D
var debris: Array[Dictionary] = []
var fire: Array[Dictionary] = []
var bag: Node3D
var lid: Node3D
var reveal_actor: Node3D
var van_loot: Node3D
var title_label: Label
var subtitle_label: Label
var elapsed := 0.0
var previous := -1.0
var actions: Array[Dictionary] = []
var events: Array[Dictionary] = []
var lines: Array[Dictionary] = []
var materials := {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair := arg.substr(2).split("=", true, 1)
			if pair.size() == 2:
				args[pair[0]] = pair[1]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("story", ""))))
	if not data is Dictionary or data.get("scene") != "campus_action":
		push_error("campus_action needs a campus action screenplay")
		get_tree().quit(1)
		return
	script_data = data
	rng.seed = 73
	_lighting()
	_build_campus()
	_build_crossing()
	_build_stunt()
	_build_actors()
	_build_overlay()
	camera = Camera3D.new()
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	_frame(0.0)

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

func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#536e9e")
	sky_mat.sky_horizon_color = Color("#ffb68e")
	sky_mat.ground_horizon_color = Color("#af8d89")
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8d3fa")
	env.ambient_light_energy = 0.59
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#b7a4b0")
	env.fog_density = 0.0025
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-29, -130, 0)
	sun.light_color = Color("#ffd3ac")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95
	add_child(sun)

func _building(at: Vector3, width: float, floors: int, depth: float, paint: Color) -> Node3D:
	var b := _group(self, at)
	var h := floors * 3.25
	_box(b, Vector3(0, h / 2, 0), Vector3(width, h, depth), paint)
	_box(b, Vector3(0, h + 0.22, 0), Vector3(width + 0.48, 0.42, depth + 0.4), CREAM)
	for floor_idx in range(floors):
		var y := 1.72 + floor_idx * 3.25
		_box(b, Vector3(0, y - 1.4, depth / 2 + 0.05), Vector3(width, 0.17, 0.28), CREAM)
		var count := maxi(2, int(width / 2.75))
		for i in range(count):
			var x := lerpf(-width / 2 + 1.5, width / 2 - 1.5, float(i) / float(count - 1))
			var lit := (i + 2 * floor_idx) % 4 == 0
			_box(b, Vector3(x, y, depth / 2 + 0.045), Vector3(1.68, 1.62, 0.14), CREAM)
			_box(b, Vector3(x, y, depth / 2 + 0.14), Vector3(1.43, 1.37, 0.09), GOLD if lit else GLASS, 0.22 if lit else 0.0)
			_box(b, Vector3(x, y, depth / 2 + 0.20), Vector3(0.07, 1.37, 0.06), INK)
		for side in [-1.0, 1.0]:
			for z in [-depth * 0.29, 0.0, depth * 0.29]:
				_box(b, Vector3(side * (width / 2 + 0.05), y, z), Vector3(0.13, 1.45, 1.4), GLASS)
	return b

func _tree(at: Vector3, size: float) -> void:
	var tree := _group(self, at)
	_box(tree, Vector3(0, 0.24, 0), Vector3(2.25, 0.48, 2.25), CREAM)
	_cylinder(tree, Vector3(0, size, 0), 0.23 * size, 2.0 * size, Color("#634433"))
	for i in range(3):
		var crown := SphereMesh.new()
		crown.radial_segments = 8
		crown.rings = 5
		crown.radius = size * 0.94
		crown.height = size * 1.6
		_mesh(tree, crown, Vector3((i - 1) * size * 0.58, (2.0 + (i % 2) * 0.4) * size, 0), Color("#4f725f").lightened(0.06 * i))

func _build_campus() -> void:
	_box(self, Vector3(43, -0.75, -43), Vector3(345, 1.4, 340), Color("#7a746b"))
	_box(self, Vector3(0, -0.105, -31), Vector3(12.4, 0.18, 165), ROAD)
	_box(self, Vector3(55, -0.10, TURN_Z), Vector3(123, 0.18, 12.4), ROAD)
	_box(self, Vector3(27, -0.04, 10), Vector3(44, 0.18, 106), Color("#b4a391"))
	_box(self, Vector3(33, 0.02, -47), Vector3(48, 0.15, 11), Color("#637b66"))
	for z in range(-94, 51, 7):
		_box(self, Vector3(0, 0.003, z), Vector3(0.14, 0.015, 3.0), GOLD)
	for x in range(4, 118, 7):
		_box(self, Vector3(x, 0.005, TURN_Z), Vector3(3.2, 0.015, 0.13), GOLD)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 5.55, 0.01, -33), Vector3(0.11, 0.025, 126.0), CREAM)
		_box(self, Vector3(side * 7.3, 0.01, -29), Vector3(2.0, 0.22, 137.0), Color("#c4b59f"))
		_box(self, Vector3(58, 0.01, TURN_Z + side * 5.55), Vector3(113, 0.025, 0.1), CREAM)
	for z in [-64, -49, -23, -9, 26, 42]:
		_tree(Vector3(9.4, 0, z), 1.45)
	for z in [-80, -61, -42, -20, 16, 37]:
		_cylinder(self, Vector3(-7.0, 3.25, z), 0.10, 6.5, INK)
		_box(self, Vector3(-6.36, 6.45, z), Vector3(1.3, 0.13, 0.25), INK)
		_box(self, Vector3(-5.71, 6.37, z), Vector3(0.5, 0.14, 0.44), GOLD, 0.8)
	for z in [-38, -22, 21, 37, 49]:
		_box(self, Vector3(10, 0.65, z), Vector3(0.38, 1.3, 13), BRICK)
		for i in range(7):
			_box(self, Vector3(10, 1.68, z - 6.0 + i * 2.0), Vector3(0.10, 0.8, 0.10), INK)
		_box(self, Vector3(10, 2.04, z), Vector3(0.13, 0.10, 13), INK)
	var tower := _building(Vector3(31, 0, 2), 35, 4, 16, BRICK)
	tower.rotation.y = -PI / 2
	_box(tower, Vector3(0, 1.8, 8.3), Vector3(5.2, 3.6, 0.6), INK)
	_box(tower, Vector3(0, 3.75, 8.8), Vector3(6.6, 0.45, 2.5), CREAM)
	_sign(tower, "CAMPUS  /  MAIN HALL", Vector3(0, 5.0, 8.22), 8.0, 0.95)
	var library := _building(Vector3(29, 0, -35), 23, 3, 13, Color("#a97959"))
	library.rotation.y = -PI / 2
	_sign(library, "LIBRARY", Vector3(0, 4.85, 6.65), 5.6, 0.92)
	var entrance := _group(self, Vector3(9.5, 0, 3.0))
	entrance.rotation.y = -PI / 2
	for x in [-5.7, 5.7]:
		_box(entrance, Vector3(x, 2.48, 0), Vector3(1.05, 4.96, 1.18), BRICK)
		_box(entrance, Vector3(x, 4.92, 0), Vector3(1.29, 0.26, 1.38), CREAM)
	_sign(entrance, "CUBE CITY COLLEGE", Vector3(0, 4.72, 0.6), 11.0, 1.15)
	for i in range(6):
		_box(self, Vector3(-3.2 + i * 1.3, 0.015, -8), Vector3(0.63, 0.03, 3.2), CREAM)
	var service := _group(self, Vector3(18, 0, -91))
	_sign(service, "SERVICE EXIT  /  RAIL", Vector3(0, 3, 0), 8.5, 1.05)
	for z in [-70, -48, -20, 16, 42]:
		var row := _building(Vector3(-31, 0, z), 15, 2 + abs(z) % 3, 10, Color("#676d77"))
		row.rotation.y = PI / 2
	for x in [35, 52, 103]:
		_building(Vector3(x, 0, -119), 13, 3, 10, Color("#777681"))

func _build_crossing() -> void:
	for x in [-1.42, 1.42]:
		_box(self, Vector3(RAIL_X + x, 0.1, -103), Vector3(0.13, 0.14, 145), Color("#b8c3cc"), 0, 0.44)
	for z in range(-173, -29, 2):
		_box(self, Vector3(RAIL_X, 0.05, z), Vector3(4.2, 0.11, 0.28), Color("#645346"))
	for x in [RAIL_X - 5, RAIL_X + 5]:
		_cylinder(self, Vector3(x, 1.65, TURN_Z + 5.2), 0.13, 3.3, INK)
		_box(self, Vector3(x, 3.20, TURN_Z + 5.2), Vector3(1.43, 0.48, 0.35), INK)
		for side in [-0.37, 0.37]:
			rail_lamp = _box(self, Vector3(x + side, 3.20, TURN_Z + 5.40), Vector3(0.31, 0.31, 0.08), Color("#fa5348"), 0.65)
	crossing_arm = _group(self, Vector3(RAIL_X - 4.5, 1.2, TURN_Z + 5.1))
	for i in range(10):
		_box(crossing_arm, Vector3(0, 0, -0.54 * i), Vector3(0.22, 0.18, 0.55), CREAM if i % 2 == 0 else Color("#f4443e"))
	train = _group(self)
	for i in range(6):
		var carriage := _group(train, Vector3(0, 0, 5.0 + i * 9.6))
		_box(carriage, Vector3(0, 1.66, 0), Vector3(3.28, 2.72, 9.0), Color("#d6dfed") if i != 0 else Color("#dc543a"), 0, 0.24)
		_box(carriage, Vector3(0, 0.52, 0), Vector3(3.0, 0.64, 8.5), INK)
		_box(carriage, Vector3(0, 2.4, 0), Vector3(3.32, 0.38, 9.0), Color("#e98141"))
		for side in [-1.0, 1.0]:
			for z in [-3.1, -1.0, 1.1, 3.2]:
				_box(carriage, Vector3(side * 1.67, 1.9, z), Vector3(0.06, 0.75, 1.45), GLASS, 0.14)
			if i == 0:
				_box(carriage, Vector3(side * 1.0, 1.2, -4.55), Vector3(0.65, 0.43, 0.06), GOLD, 2.8)

func _vehicle(color: Color, tall: bool) -> Node3D:
	var body := _group(self)
	var length := 5.0 if tall else 4.2
	var width := 2.06 if tall else 1.86
	_box(body, Vector3(0, 0.55, 0), Vector3(width, 0.53, length), color, 0, 0.36)
	_box(body, Vector3(0, 0.4, 0), Vector3(width + 0.06, 0.16, length + 0.12), INK)
	var cabin_y := 1.16 if tall else 1.02
	var cabin_h := 1.13 if tall else 0.64
	var cabin_length := 3.7 if tall else 2.06
	_box(body, Vector3(0, cabin_y, 0.27), Vector3(width - 0.26, cabin_h, cabin_length), GLASS, 0, 0.31)
	_box(body, Vector3(0, cabin_y + cabin_h / 2, 0.27), Vector3(width - 0.22, 0.13, cabin_length), color, 0, 0.36)
	_box(body, Vector3(0, cabin_y, 0.43), Vector3(width - 0.20, cabin_h, 0.11), color)
	if not tall:
		_box(body, Vector3(0, 0.79, -1.36), Vector3(0.22, 0.03, 1.25), CREAM)
		_box(body, Vector3(0, 0.76, 1.80), Vector3(width - 0.20, 0.13, 0.32), INK)
	else:
		_box(body, Vector3(0, 1.04, 2.78), Vector3(width - 0.12, 0.77, 0.18), color.darkened(0.2))
		for side in [-1.0, 1.0]:
			_box(body, Vector3(side * width * 0.51, 0.93, 0.92), Vector3(0.08, 0.15, 2.48), Color("#e08b39"))
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * width * 0.34, 0.61, -length / 2 - 0.025), Vector3(0.48, 0.20, 0.09), Color("#ddf2ff"), 2.2)
		_box(body, Vector3(side * width * 0.35, 0.68, length / 2 + 0.025), Vector3(0.38, 0.22, 0.08), Color("#fc332b"), 1.7)
		for axle in [-0.31, 0.31]:
			var mount := _group(body, Vector3(side * width / 2, 0.37, length * axle))
			var tire := _cylinder(mount, Vector3.ZERO, 0.37, 0.24, Color("#101824"))
			tire.rotation.z = PI / 2
			var rim := _cylinder(mount, Vector3(side * 0.135, 0, 0), 0.22, 0.03, Color("#b3c7d6"), 0.54)
			rim.rotation.z = PI / 2
			for spoke in range(3):
				var strip := _box(mount, Vector3(side * 0.158, 0, 0), Vector3(0.02, 0.35, 0.045), INK)
				strip.rotation.x = spoke * PI / 3.0
			mount.add_to_group("van_wheel" if tall else "hero_wheel")
	return body

func _build_stunt() -> void:
	barrels = _group(self, Vector3(6.3, 0, -68.6))
	for a in range(5):
		var at := Vector3(0.72 * (a % 2), 0.45, (a - 2) * 0.86)
		_cylinder(barrels, at, 0.36, 0.90, Color("#c94631"))
		for y in [-0.21, 0.21]:
			_cylinder(barrels, at + Vector3(0, y, 0), 0.372, 0.06, GOLD)
	for x in [-4.5, -2.6, -0.7]:
		var roadblock := _group(self, Vector3(x, 0, -64.0))
		_box(roadblock, Vector3(0, 0.31, 0), Vector3(1.69, 0.62, 0.62), Color("#c5bcb0"))
		for a in range(4):
			_box(roadblock, Vector3(-0.62 + a * 0.40, 0.42, 0.33), Vector3(0.18, 0.30, 0.05), Color("#e27a40"))
		_box(roadblock, Vector3(0, 0.68, 0), Vector3(0.21, 0.13, 0.21), GOLD, 1.8)
	var annex := _building(Vector3(16.5, 0, -75.5), 12.0, 3, 12.0, Color("#846e67"))
	annex.rotation.y = -PI / 2
	facade = _group(self, Vector3(9.95, 0, -75.5))
	var plaque := _group(facade, Vector3(0, 0, -0.5))
	plaque.rotation.y = -PI / 2
	_sign(plaque, "CAMPUS ANNEX", Vector3(0, 4.96, 0.68), 6.1, 0.86)
	for row in range(5):
		for col in range(7):
			var at := Vector3(9.7, 0.66 + row * 1.27, -79.4 + col * 1.31)
			var piece := _box(self, at, Vector3(0.69, 1.22, 1.26), BRICK.lightened(0.06 * (col % 3)))
			if row % 2 == 1:
				_box(piece, Vector3(-0.35, 0, 0), Vector3(0.08, 0.79, 0.92), GLASS)
			debris.append({
				"node": piece, "start": at,
				"drift": Vector3(rng.randf_range(-7.9, -2.7), 0, rng.randf_range(-3.0, 2.0)),
				"spin": Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-2.6, 2.6), rng.randf_range(-2.3, 2.3))
			})
	blast_flash = OmniLight3D.new()
	blast_flash.position = barrels.position + Vector3(0, 2.8, 0)
	blast_flash.light_color = Color("#ffac5a")
	blast_flash.omni_range = 28.0
	blast_flash.light_energy = 0.0
	add_child(blast_flash)
	for i in range(24):
		var sphere := SphereMesh.new()
		sphere.radial_segments = 10
		sphere.rings = 6
		sphere.radius = 1.0
		sphere.height = 2.0
		var color: Color = [Color("#ffedba"), Color("#ffa045"), Color("#f05325"), Color("#594454")][i % 4]
		var bit := _mesh(self, sphere, barrels.position, color, 0.9 if i % 4 != 3 else 0.0)
		bit.visible = false
		fire.append({
			"node": bit, "delay": rng.randf_range(0.0, 0.29),
			"velocity": Vector3(rng.randf_range(-7.0, 4.0), rng.randf_range(3.5, 9.0), rng.randf_range(-6.0, 4.0)),
			"smoke": i % 4 == 3
		})

func _build_actors() -> void:
	hero = _vehicle(Color("#b91d67"), false)
	van = _vehicle(Color("#243146"), true)
	heli = _group(self)
	_box(heli, Vector3(0, 0, 0), Vector3(2.3, 1.56, 4.35), Color("#496475"), 0, 0.28)
	_box(heli, Vector3(0, 0.11, -2.10), Vector3(1.95, 1.16, 0.45), Color("#94b9cb"), 0.13, 0.4)
	_box(heli, Vector3(0, 0.32, 3.1), Vector3(0.58, 0.52, 3.8), Color("#496475"))
	_box(heli, Vector3(0, 0.82, 4.73), Vector3(0.27, 1.36, 0.74), INK)
	for side in [-1.0, 1.0]:
		_box(heli, Vector3(side * 0.82, -1.03, -0.2), Vector3(0.12, 0.16, 4.0), INK)
		_box(heli, Vector3(side * 1.19, -0.16, 0.22), Vector3(0.14, 0.28, 0.21), Color("#ff4243") if side < 0 else Color("#65ffd0"), 2.0)
	rotor = _group(heli, Vector3(0, 1.04, 0))
	for a in [0.0, PI / 2]:
		var blade := _box(rotor, Vector3.ZERO, Vector3(9, 0.045, 0.24), INK)
		blade.rotation.y = a
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = 4.8
	cone.height = 1.0
	cone.cap_bottom = false
	cone.cap_top = false
	beam = _mesh(self, cone, Vector3.ZERO, Color(0.76, 0.87, 1.0, 0.10))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stop := _group(self, Vector3(111, 0, TURN_Z + 2.9))
	bag = _group(stop, Vector3(0.06, 0.82, -0.36))
	var leather := Color("#61416a")
	_box(bag, Vector3(0, -0.27, 0), Vector3(1.48, 0.12, 0.96), leather)
	for side in [-1.0, 1.0]:
		_box(bag, Vector3(side * 0.69, -0.08, 0), Vector3(0.12, 0.40, 0.96), leather)
		_box(bag, Vector3(0, -0.08, side * 0.43), Vector3(1.42, 0.40, 0.12), leather)
	_box(stop, Vector3(0, 0.37, -0.37), Vector3(1.57, 0.48, 1.02), Color("#b19d8b"))
	lid = _group(bag, Vector3(0, 0.12, -0.46))
	_box(lid, Vector3(0, 0, 0.47), Vector3(1.49, 0.09, 0.98), leather.lightened(0.14))
	_make_loot(bag, str(script_data.get("reveal_prop", "tiffin")))
	van_loot = _group(van, Vector3(0, 1.05, 2.78))
	_make_loot(van_loot, str(script_data.get("prize", "trophy")))
	var lead: Dictionary = script_data.get("cast", {}).get("shona", {})
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
	Vector3(18, 39, -101.75), Vector3(20.8, 70, -101.75), Vector3(22.2, 87.0, -101.75),
	Vector3(23.8, 104, -101.75), Vector3(24.5, 108.5, -101.6), Vector3(25.1, 110, -101.35),
	Vector3(26, 110.4, -101.05)]
const VAN_PATH := [
	Vector3(2.4, -1.6, 39), Vector3(5.4, -1.4, 10), Vector3(8.3, 1.7, -21),
	Vector3(11, 1.7, -43), Vector3(12.1, 1.15, -57), Vector3(13.05, 6.3, -68.6),
	Vector3(13.8, 3.7, -75), Vector3(15.2, 1.0, -91), Vector3(16.2, 5.5, -99.4),
	Vector3(16.7, 11.2, -98.3), Vector3(19.3, 40.8, -98.3), Vector3(21.8, 65.5, -98.3),
	Vector3(22.55, 72.0, -98.3), Vector3(23.25, 73.6, -98.3)]

func _pose_car(car: Node3D, time: float, keys: Array, bank: float) -> void:
	var now := _route(time, keys)
	var heading := _route(time + 0.18, keys) - _route(time - 0.14, keys)
	car.position = now
	if heading.length_squared() > 0.0001:
		car.rotation.y = atan2(-heading.x, -heading.z)
	car.rotation.z = bank

func _frame(t: float) -> void:
	var scene_time := 21.05 + t * 0.50 if t < 2.4 else t
	_pose_car(hero, scene_time, HERO_PATH, -0.13 * sin(clampf((scene_time - 14.3) / 1.2, 0.0, 1.0) * PI))
	_pose_car(van, scene_time, VAN_PATH, 0.21 * sin(clampf((scene_time - 12.2) / 1.7, 0.0, 1.0) * PI))
	for node in get_tree().get_nodes_in_group("hero_wheel"):
		node.rotation.x = -scene_time * 23.0 if scene_time < 25.1 else -25.1 * 23.0
	for node in get_tree().get_nodes_in_group("van_wheel"):
		node.rotation.x = -minf(scene_time, 23.25) * 24.0

	heli.visible = scene_time >= 7.0 and scene_time < 24.5
	heli.position = (hero.position + van.position) * 0.5 + Vector3(-6.5, 13.0, 8.0)
	heli.rotation.y = hero.rotation.y
	rotor.rotation.y = t * 44.0
	var ground_target := (hero.position + van.position) * 0.5 + Vector3(0, 0.04, 0)
	var light_origin := heli.position + Vector3(0, -0.7, 0)
	beam.visible = heli.visible
	beam.position = (light_origin + ground_target) * 0.5
	var beam_axis := light_origin - ground_target
	beam.basis = Basis(Quaternion(Vector3.UP, beam_axis.normalized())).scaled_local(Vector3(1, beam_axis.length(), 1))

	var rail_time := scene_time - 22.40
	train.position = Vector3(RAIL_X, 0, TURN_Z - rail_time * 21.5 - 0.50)
	crossing_arm.rotation.x = lerpf(PI / 2, 0.0, smoothstep(19.7, 21.0, scene_time))
	if scene_time >= 21.22:
		crossing_arm.rotation.y = -1.15 * smoothstep(21.22, 21.46, scene_time)
		crossing_arm.rotation.z = 0.32 * smoothstep(21.22, 21.5, scene_time)
	else:
		crossing_arm.rotation.y = 0.0
		crossing_arm.rotation.z = 0.0
	rail_lamp.visible = int(scene_time * 7.0) % 2 == 0

	_update_destruction(scene_time)
	bag.visible = scene_time >= 24.65
	lid.rotation.x = -1.56 * smoothstep(24.77, 25.24, scene_time)
	reveal_actor.visible = bag.visible and scene_time < 26.33
	van_loot.visible = t >= 26.33
	if reveal_actor.visible:
		reveal_actor.update(1.0 / 30.0, null)
	_shot(t, scene_time)
	_overlay(t)

func _update_destruction(t: float) -> void:
	var blast_time := t - 13.05
	barrels.visible = blast_time < 0.0
	blast_flash.light_energy = 7.5 * exp(-blast_time * 6.0) if blast_time >= 0.0 else 0.0
	for bit: Dictionary in fire:
		var node: MeshInstance3D = bit["node"]
		var flight: float = blast_time - float(bit["delay"])
		var lifetime := 2.7 if bit["smoke"] else 0.9
		node.visible = flight >= 0.0 and flight < lifetime
		if node.visible:
			var velocity: Vector3 = bit["velocity"]
			node.position = barrels.position + Vector3(0, 0.75, 0) + velocity * flight - Vector3.UP * flight * flight * (0.7 if bit["smoke"] else 3.1)
			var fire_size := (0.40 + flight * 1.55) * (1.0 - smoothstep(lifetime * 0.64, lifetime, flight))
			node.scale = Vector3.ONE * maxf(0.01, fire_size)
	var fall_time := clampf(t - 13.35, 0.0, 1.7)
	facade.visible = fall_time < 0.2
	for block: Dictionary in debris:
		var node: MeshInstance3D = block["node"]
		var start: Vector3 = block["start"]
		var drift: Vector3 = block["drift"]
		var travel := minf(fall_time, sqrt(maxf(0.0, start.y - 0.28) / 5.6) + 0.29)
		node.position = start + drift * travel - Vector3.UP * travel * travel * 5.6
		node.position.y = maxf(0.32, node.position.y)
		node.rotation = (block["spin"] as Vector3) * travel

func _set_shot(at: Vector3, aim: Vector3, fov: float) -> void:
	camera.position = at
	camera.look_at(aim)
	camera.fov = fov

func _shot(t: float, scene_time: float) -> void:
	var car := hero.position
	var pursuer := van.position
	var middle := (car + pursuer) * 0.5
	if t < 2.4:
		# Cold open: show both paths that are about to intersect.
		_set_shot(Vector3(64.3, 9.4, -84.0), Vector3(78.4, 0.7, -98.0), 59)
	elif t < 5.8:
		_set_shot(Vector3(-15.2 + (t - 2.4), 8.5, 14.5 - (t - 2.4) * 6.0),
			Vector3(8.5, 2.4, car.z - 2.8), 53)
	elif t < 8.5:
		_set_shot(car + Vector3(-4.4, 1.8, 4.9), middle + Vector3(0.2, 0.75, -0.3), 61)
	elif t < 11.6:
		_set_shot(middle + Vector3(-12.4, 7.0, 14.6), middle + Vector3(-2.0, 5.5, 0.8), 60)
	elif t < 12.88:
		_set_shot(car + Vector3(-2.8, 1.45, -7.4), car + Vector3(0, 0.60, 0.8), 52)
	elif t < 14.48:
		var shake := sin((scene_time - 13.05) * 32.0) * maxf(0.0, 0.28 - absf(scene_time - 13.05) * 0.31)
		_set_shot(Vector3(-12.3 + shake, 5.8 + shake, -62.2), Vector3(6.0, 1.9, -73.7), 56)
	elif t < 17.2:
		_set_shot(car + Vector3(-7.0, 5.5, 8.8), car + Vector3(6.0, 0.25, -2.6), 58)
	elif t < 19.8:
		_set_shot(middle + Vector3(4.7, 3.4, 12.9), middle + Vector3(5.3, 0.9, -0.7), 57)
	elif t < 22.98:
		_set_shot(Vector3(66.3, 7.7, -91.0), Vector3(78.4, 0.7, -100.8), 57)
	elif t < 24.65:
		_set_shot(car + Vector3(4.3, 1.85, 4.6), car + Vector3(0, 0.87, -0.15), 48)
	elif t < 26.33:
		_set_shot(bag.global_position + Vector3(-0.8, 1.27, 2.40), bag.global_position + Vector3(-0.40, 0.40, 0), 48)
	else:
		_set_shot(van_loot.global_position + Vector3(1.25, 0.83, 3.85), van_loot.global_position + Vector3(0, 0.24, 0), 44)

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
	# Record observed scene state, including the rail clearance, rather than just requested cues.
	if previous < 3.2 and elapsed >= 3.2:
		_event("campus_established", 3.2)
	if previous < 9.5 and elapsed >= 9.5 and heli.visible and beam.visible:
		_event("helicopter_tracks_chase", 9.5)
	if previous < 13.12 and elapsed >= 13.12 and not barrels.visible and blast_flash.light_energy > 0.5:
		_event("van_barrel_blast", 13.12)
	if previous < 14.15 and elapsed >= 14.15 and (debris.back()["node"] as Node3D).position.x < 8.0:
		_event("annex_facade_collapses", 14.15)
	if previous < 22.4 and elapsed >= 22.4 and hero.position.x > RAIL_X + 5.0 and absf(train.position.z - TURN_Z) < 2.0:
		_event("car_clears_before_train", 22.4)
	if previous < 23.26 and elapsed >= 23.26 and van.position.x < RAIL_X - 3.0 and train.position.z < TURN_Z - 10.0:
		_event("train_blocks_van", 23.26)
	if previous < 25.35 and elapsed >= 25.35 and bag.visible and lid.rotation.x < -1.4:
		_event("wrong_bag_revealed", 25.35)
	if previous < 26.4 and elapsed >= 26.4 and van_loot.visible:
		_event("prize_in_van", 26.4)
	previous = elapsed
	if elapsed >= DURATION:
		_finish()

func _write(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Campus scene could not write " + path)
		return false
	file.store_string(JSON.stringify(payload))
	return true

func _finish() -> void:
	var log_ok := _write(str(args.get("story_log", "")), {"lines": lines, "actions": actions, "events": events,
		"ending": "cliffhanger", "end": 26.33})
	var summary_ok := _write(str(args.get("summary", "")), {"mode": "campus_action", "duration": DURATION, "end": "finished"})
	get_tree().quit(0 if log_ok and summary_ok else 1)
