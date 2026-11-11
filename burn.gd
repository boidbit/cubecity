class_name Burn
extends Node3D
# A burning vehicle: smoke, flames, embers and a flickering light, in stages.
#   level 0  nothing
#   level 1  thin smoke from the hood
#   level 2  heavy dark smoke and a glow (flames too once LEVEL2_FLAMES works, see below)
#   level 3  the car is on fire: flames at the hood, the cabin and the rear, a tall column of black
#            smoke, embers and a flickering light
# A car asks for a level from its health (Car.set_burn_level). Fx decides how much of it is shown
# (Fx.burn_budget): only the nearest few burning cars get the full fire, and only the nearest two a
# light, so a pile of burning wrecks costs about as much as four fires, however many there are.
# The shared textures, materials and colour ramps are made once in Fx.

# KNOWN ISSUE (parked, to be solved): the flames of a fire that is made fresh at level 2 draw nothing, although
# the emitters exist and say they are emitting. The same emitters draw perfectly well once they have been
# switched off and on again (or restarted) some 150 frames after they were made, and after the car has been at
# level 3. Starting them one frame later, or after 0.05 s, does not help. Level 3 is made fresh and draws fine.
# Until the cause is found level 2 is smoke and a glow only. Set this to true to try again.
const LEVEL2_FLAMES := false

var fx
var k := 1.0                 # size of the vehicle (the SWAT truck is bigger)
var level := 0               # what the car asks for
var cap := 3                 # the director can hold a car at a lower stage (a limping car in a video)
var tier := 2                # 2 full fire with a light, 1 full fire, 0 cut down to level 2 at most
var emitters := {}           # name -> CPUParticles3D, made the first time it is needed
var light: OmniLight3D
var t := 0.0
var phase := randf() * 10.0


func setup(f, size: float = 1.0) -> void:
	fx = f
	k = size
	fx.burns.append(self)


func _exit_tree() -> void:
	if fx != null:
		fx.burns.erase(self)


func set_level(l: int) -> void:
	l = clampi(l, 0, 3)
	if l == level:
		return
	level = l
	_apply()


func set_cap(c: int) -> void:
	cap = clampi(c, 0, 3)
	_apply()


func set_tier(n: int) -> void:
	if n == tier:
		return
	tier = n
	_apply()


# What is shown: the level the car asks for, held down by the cap, and cut down to flames and
# smoke only when Fx has better use for the particles (many cars burning, or this one far away).
func shown() -> int:
	var e := mini(level, cap)
	if tier == 0:
		e = mini(e, 2)
	return e


func _apply() -> void:
	var e := shown()
	_show("smoke_thin", e == 1)
	_show("smoke_mid", e == 2)
	_show("smoke_col", e == 3)
	# level 2 would be the same two flame emitters as level 3, only smaller (see LEVEL2_FLAMES)
	var flames := e >= 3 or (e == 2 and LEVEL2_FLAMES)
	_show("flame_body", flames)
	_show("flame_core", flames)
	_resize("flame_body", 0.6 if e == 2 else 1.0)
	_resize("flame_core", 0.55 if e == 2 else 1.0)
	_show("flame_cabin", e == 3)
	_show("flame_rear", e == 3)
	_show("embers", e == 3 and tier >= 1)
	var want_light := e >= 2 and tier == 2
	if want_light and light == null:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.52, 0.2)
		light.omni_range = 11.0 * k
		light.shadow_enabled = false
		light.position = Vector3(0, 1.6, -0.6) * k
		add_child(light)
	elif not want_light and light != null:
		light.queue_free()
		light = null
	set_process(light != null)


func _show(name: String, on: bool) -> void:
	if on and not emitters.has(name):
		emitters[name] = _make(name)
	if emitters.has(name):
		var p := emitters[name] as CPUParticles3D
		if on and not p.emitting:
			p.restart()          # a fresh emitter that is only switched on does not always start; restarting it does
		p.emitting = on


func _resize(name: String, f: float) -> void:
	if not emitters.has(name):
		return
	var p := emitters[name] as CPUParticles3D
	var s: Vector2 = p.get_meta("s")
	p.scale_amount_min = s.x * k * f
	p.scale_amount_max = s.y * k * f


func _process(delta: float) -> void:
	if light == null:
		return
	t += delta
	# two sines that never line up, and a little noise: a flame is never steady
	var base := 2.1 if shown() >= 3 else 0.9
	light.light_energy = base * (1.0 + 0.32 * sin(t * 21.0 + phase) * sin(t * 8.7 + phase) + randf_range(-0.12, 0.12))


# One emitter: where, what it is made of, how many, how long they live, how they move.
func _spec(name: String) -> Dictionary:
	match name:
		"smoke_thin":
			return {"pos": Vector3(0, 1.0, -1.3), "kind": "smoke", "n": 18, "life": 3.6, "s": Vector2(0.8, 1.3), "v": Vector2(1.2, 2.2),
				"spread": 12.0, "g": Vector3(0.5, 1.4, 0), "box": Vector3(0.5, 0.1, 0.3)}
		"smoke_mid":
			return {"pos": Vector3(0, 1.45, -0.9), "kind": "smoke", "n": 26, "life": 4.0, "s": Vector2(1.0, 1.7), "v": Vector2(1.6, 2.8),
				"spread": 12.0, "g": Vector3(0.8, 1.8, 0), "box": Vector3(0.5, 0.1, 0.3)}
		"smoke_col":
			return {"pos": Vector3(0, 1.5, -0.6), "kind": "smoke_dense", "n": 90, "life": 6.5, "s": Vector2(2.6, 4.6), "v": Vector2(3.0, 5.5),
				"spread": 9.0, "g": Vector3(1.2, 2.4, 0), "box": Vector3(0.6, 0.2, 0.6)}
		"flame_body":
			return {"pos": Vector3(0, 0.95, -1.4), "kind": "flame_body", "n": 16, "life": 0.7, "s": Vector2(1.0, 1.5), "v": Vector2(1.5, 3.0),
				"spread": 14.0, "g": Vector3(0, 1.6, 0), "box": Vector3(0.6, 0.05, 0.5), "quad": Vector2(1.0, 1.6)}
		"flame_core":
			return {"pos": Vector3(0, 1.0, -1.3), "kind": "flame_core", "n": 14, "life": 0.5, "s": Vector2(0.5, 0.9), "v": Vector2(1.8, 3.4),
				"spread": 12.0, "g": Vector3(0, 1.8, 0), "box": Vector3(0.45, 0.05, 0.35), "quad": Vector2(0.8, 1.3)}
		"flame_cabin":
			return {"pos": Vector3(0, 1.3, 0.1), "kind": "flame_body", "n": 12, "life": 0.6, "s": Vector2(0.8, 1.2), "v": Vector2(1.2, 2.6),
				"spread": 16.0, "g": Vector3(0, 1.5, 0), "box": Vector3(0.4, 0.05, 0.5), "quad": Vector2(0.9, 1.4)}
		"flame_rear":
			return {"pos": Vector3(0, 1.0, 1.4), "kind": "flame_body", "n": 8, "life": 0.5, "s": Vector2(0.6, 0.9), "v": Vector2(1.0, 2.0),
				"spread": 16.0, "g": Vector3(0, 1.2, 0), "box": Vector3(0.45, 0.05, 0.3), "quad": Vector2(0.8, 1.2)}
		_:   # embers
			return {"pos": Vector3(0, 1.2, -1.0), "kind": "ember", "n": 26, "life": 1.2, "s": Vector2(0.035, 0.07), "v": Vector2(2.5, 7.0),
				"spread": 55.0, "g": Vector3(0.5, -2.5, 0), "box": Vector3(0.7, 0.1, 0.6), "quad": Vector2(1, 1)}


func _make(name: String) -> CPUParticles3D:
	var sp := _spec(name)
	var kind: String = sp["kind"]
	var quad := QuadMesh.new()
	quad.size = sp.get("quad", Vector2.ONE) as Vector2
	quad.material = fx.burn_mat[kind]
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = int(sp["n"])
	p.lifetime = float(sp["life"])
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = (sp["box"] as Vector3) * k
	p.direction = Vector3.UP
	p.spread = float(sp["spread"])
	var v: Vector2 = sp["v"]
	p.initial_velocity_min = v.x
	p.initial_velocity_max = v.y
	p.gravity = sp["g"]
	var s: Vector2 = sp["s"]
	p.scale_amount_min = s.x * k
	p.scale_amount_max = s.y * k
	p.set_meta("s", s)
	p.scale_amount_curve = fx.burn_curve[kind]
	p.color_ramp = fx.burn_ramp[kind]
	p.angle_min = 0.0
	p.angle_max = 360.0 if kind.begins_with("smoke") or kind == "ember" else 0.0
	p.emitting = false
	p.position = (sp["pos"] as Vector3) * k
	add_child(p)
	return p
