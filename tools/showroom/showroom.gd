extends Node3D
# Look-dev only (not part of the game): the car bodies and kit wheels side by side under the
# game's own lighting, with a slowly turning camera, so a model can be judged from a render.
# godot --path . tools/showroom/showroom.tscn --write-movie out.avi --fixed-fps 10 --quit-after 80 -- --night

var cam: Camera3D
var t := 0.0
var spin := 0.0
var look_at_y := 0.8


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var night := "--night" in args
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	Look.setup(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	var e := -0.9 if night else 0.9
	Look.apply(env, sky_mat, sun, 0.0 if night else 1.0, 0.0, 0.0, e)
	RenderingServer.global_shader_parameter_set(&"night_amount", 1.0 if night else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.31, 0.34)
	ground.material_override = gm
	add_child(ground)
	var kinds := ["sport", "sedan", "suv", "van", "swat"]
	var colors := [Color(0.85, 0.14, 0.1), Color(0.2, 0.45, 0.9), Color(0.95, 0.72, 0.1), Color(0.9, 0.9, 0.92), Color(0.12, 0.12, 0.14)]
	var only := ""
	for a in args:
		if a.begins_with("--car="):
			only = a.substr(6)
	for i in kinds.size():
		if only != "" and kinds[i] != only:
			continue
		var car := Node3D.new()
		car.position = Vector3.ZERO if only != "" else Vector3((i - 2) * 5.2, 0, 0)
		add_child(car)
		var mat := ShaderMaterial.new()
		mat.shader = Shaders.get_shader(Shaders.CAR)
		mat.set_shader_parameter("color", colors[i])
		var mi := MeshInstance3D.new()
		mi.mesh = CarMesh.body(kinds[i])
		mi.material_override = mat
		if "--debug" in args:
			# classification view: paint white, trim black, glass blue, lamps yellow/red
			var dm := ShaderMaterial.new()
			dm.shader = Shader.new()
			dm.shader.code = "shader_type spatial; render_mode unshaded; void fragment(){ float a=COLOR.a; vec3 c=vec3(1.0); if(a>0.25) c=vec3(0.0); if(a>0.65) c=vec3(1.0,0.9,0.1); if(a>0.75) c=vec3(1.0,0.1,0.1); if(a>0.9) c=vec3(0.1,0.3,1.0); ALBEDO=c; }"
			mi.material_override = dm
		mi.position = Vector3.ZERO
		car.add_child(mi)
		var wz := 1.3 if kinds[i] != "swat" else 1.85
		var wx := 0.86 if kinds[i] != "swat" else 1.06
		var wr := 0.4 if kinds[i] != "swat" else 0.56
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var w := Kit.wheel(wr, 0.3)
				w.position = Vector3(sx * wx, wr, sz * wz)
				car.add_child(w)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)


func _process(dt: float) -> void:
	t += dt
	# one slow turn around the car
	var ang := TAU * t / 8.0
	cam.position = Vector3(sin(ang) * 6.5, 2.0, cos(ang) * 6.5)
	cam.look_at(Vector3(0, look_at_y, 0))
