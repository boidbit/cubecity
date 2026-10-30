extends Node3D
# Story lab: a blocky character sitting in the car. Built from boxes like everything else in
# the game, with a pixel-art face that changes with the emotion and flaps with the voice.
# Faces the front of the car (-z). Moves only by turning the head, swinging the arms and
# bobbing; it does not touch the car's physics.

const FACE_PX := 16
const SKIN_DARK := Color(0.12, 0.09, 0.1)
const PINK := Color(1.0, 0.35, 0.55)
const EMOTIONS := {
	"neutral": {"eyes": "open", "mouth": "smile"},
	"smug": {"eyes": "smug", "mouth": "smirk"},
	"love": {"eyes": "heart", "mouth": "smile", "blush": true},
	"shock": {"eyes": "wide", "mouth": "o"},
	"angry": {"eyes": "angry", "mouth": "frown"},
	"sad": {"eyes": "sad", "mouth": "frown"},
	"happy": {"eyes": "happy", "mouth": "smile", "blush": true},
	"laugh": {"eyes": "happy", "mouth": "open"},
}
static var face_cache := {}
static var heart_tex: ImageTexture

var who := ""
var seat_x := 0.4
var driver := false
var style := "boy"
var head: Node3D
var torso: Node3D
var arm_l: Node3D
var arm_r: Node3D
var face_mat: StandardMaterial3D
var hearts: CPUParticles3D
var emotion := "neutral"
var gesture := "idle"
var speaking := false
var mouth := 0.0            # 0 closed .. 1 wide open, set by the voice
var look := 0.0             # 0 = at the road, 1 = at the other character
var t := 0.0
var blink_t := 2.5
var face_key := ""
var mats := {}


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


# cfg: {"style": "boy"|"girl", "skin", "hair", "shirt"} as html colours.
func build(who_id: String, cfg: Dictionary, is_driver: bool, x: float) -> void:
	who = who_id
	driver = is_driver
	seat_x = x
	style = str(cfg.get("style", "boy"))
	var skin := Color.from_string(str(cfg.get("skin", "#f2b58f")), Color(0.95, 0.72, 0.56))
	var hair := Color.from_string(str(cfg.get("hair", "#2b1d16")), Color(0.17, 0.11, 0.09))
	var shirt := Color.from_string(str(cfg.get("shirt", "#3b7ddd")), Color(0.23, 0.49, 0.87))
	var pants := Color(0.16, 0.18, 0.28)

	torso = Node3D.new()
	add_child(torso)
	_box(torso, Vector3(0.54, 0.5, 0.3), Vector3(0, 0.25, 0), shirt)
	# thighs, hips to knees; the shins are hidden inside the car body
	for s in [-1.0, 1.0]:
		_box(self, Vector3(0.22, 0.17, 0.5), Vector3(s * 0.13, 0.04, -0.26), pants)

	head = Node3D.new()
	head.position = Vector3(0, 0.5, 0)
	torso.add_child(head)
	_box(head, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.27, 0), skin)
	_build_hair(hair)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	quad.mesh = qm
	face_mat = StandardMaterial3D.new()
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material_override = face_mat
	quad.position = Vector3(0, 0.27, -0.255)
	quad.rotation = Vector3(0, PI, 0)     # a quad faces +z; the face looks toward -z
	head.add_child(quad)
	_set_face("open", "smile", false)

	# arms hang from the shoulders; rotating about x swings them forward
	arm_l = _make_arm(-1.0, shirt, skin)
	arm_r = _make_arm(1.0, shirt, skin)

	hearts = CPUParticles3D.new()
	var hm := QuadMesh.new()
	hm.size = Vector2(0.34, 0.34)
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hmat.albedo_texture = _heart_texture()
	hm.material = hmat
	hearts.mesh = hm
	hearts.amount = 5
	hearts.lifetime = 1.1
	hearts.emitting = false
	hearts.direction = Vector3.UP
	hearts.spread = 25.0
	hearts.initial_velocity_min = 1.4
	hearts.initial_velocity_max = 2.4
	hearts.gravity = Vector3.ZERO
	hearts.local_coords = false
	hearts.position = Vector3(0, 1.15, 0)
	add_child(hearts)


func _make_arm(side: float, shirt: Color, skin: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * 0.34, 0.44, 0)
	torso.add_child(pivot)
	_box(pivot, Vector3(0.14, 0.4, 0.14), Vector3(0, -0.2, 0), shirt)
	_box(pivot, Vector3(0.15, 0.13, 0.15), Vector3(0, -0.46, 0), skin)
	return pivot


func _build_hair(hair: Color) -> void:
	_box(head, Vector3(0.56, 0.12, 0.56), Vector3(0, 0.56, 0.0), hair)        # top
	_box(head, Vector3(0.56, 0.5, 0.12), Vector3(0, 0.3, 0.28), hair)         # back
	for s in [-1.0, 1.0]:
		_box(head, Vector3(0.08, 0.34, 0.5), Vector3(s * 0.27, 0.38, 0.0), hair)   # sides
	if style == "girl":
		_box(head, Vector3(0.6, 0.12, 0.1), Vector3(0, 0.5, -0.27), hair)     # fringe
		_box(head, Vector3(0.64, 0.7, 0.12), Vector3(0, 0.0, 0.31), hair)     # long hair down the back
		for s in [-1.0, 1.0]:
			_box(head, Vector3(0.1, 0.5, 0.18), Vector3(s * 0.3, 0.12, -0.1), hair)
		_box(head, Vector3(0.18, 0.14, 0.12), Vector3(0.22, 0.62, -0.1), PINK)   # bow
		_box(head, Vector3(0.06, 0.06, 0.1), Vector3(0.22, 0.62, -0.1), Color(1, 0.8, 0.9))
	else:
		_box(head, Vector3(0.34, 0.14, 0.16), Vector3(0.05, 0.64, -0.2), hair)  # quiff


# ------------------------------------------------------------ face

func _heart_texture() -> ImageTexture:
	if heart_tex != null:
		return heart_tex
	var pat := ["01100110", "11111111", "11111111", "11111111", "01111110", "00111100", "00011000"]
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in pat.size():
		for x in 8:
			if pat[y][x] == "1":
				img.set_pixel(x, y, PINK)
	heart_tex = ImageTexture.create_from_image(img)
	return heart_tex


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < FACE_PX and y < FACE_PX:
		img.set_pixel(x, y, c)


func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)


func _eyes(img: Image, kind: String) -> void:
	for ex in [3, 10]:
		match kind:
			"open":
				_rect(img, ex, 5, 3, 4, SKIN_DARK)
			"blink":
				_rect(img, ex, 7, 3, 1, SKIN_DARK)
			"smug":
				_rect(img, ex, 6, 3, 2, SKIN_DARK)
				_rect(img, ex, 5, 3, 1, SKIN_DARK)
			"happy":
				_px(img, ex, 7, SKIN_DARK)
				_rect(img, ex + 1, 6, 1, 1, SKIN_DARK)
				_px(img, ex + 2, 7, SKIN_DARK)
			"heart":
				var pat := ["101", "111", "010"]
				for y in 3:
					for x in 3:
						if pat[y][x] == "1":
							_px(img, ex + x, 5 + y, PINK)
			"wide":
				_rect(img, ex, 4, 3, 5, Color.WHITE)
				_rect(img, ex + 1, 6, 1, 2, SKIN_DARK)
			"angry":
				_rect(img, ex, 6, 3, 3, SKIN_DARK)
			"sad":
				_rect(img, ex, 5, 3, 4, SKIN_DARK)
				_px(img, ex + 1, 9, Color(0.4, 0.7, 1.0))
				_px(img, ex + 1, 10, Color(0.4, 0.7, 1.0))
	if kind == "angry":
		for i in 3:
			_px(img, 3 + i, 4 - (i - 1) + 0, SKIN_DARK)
			_px(img, 10 + i, 4 + (i - 1) + 0, SKIN_DARK)
		_rect(img, 2, 3, 4, 1, SKIN_DARK)
		_rect(img, 10, 3, 4, 1, SKIN_DARK)
	if kind == "sad":
		_rect(img, 3, 3, 3, 1, SKIN_DARK)
		_rect(img, 10, 3, 3, 1, SKIN_DARK)


func _mouth(img: Image, kind: String) -> void:
	var red := Color(0.62, 0.12, 0.18)
	match kind:
		"smile":
			_rect(img, 5, 11, 6, 1, SKIN_DARK)
			_px(img, 4, 10, SKIN_DARK)
			_px(img, 11, 10, SKIN_DARK)
		"smirk":
			_rect(img, 6, 11, 5, 1, SKIN_DARK)
			_px(img, 11, 10, SKIN_DARK)
			_px(img, 12, 9, SKIN_DARK)
		"open":
			_rect(img, 6, 10, 4, 3, SKIN_DARK)
			_rect(img, 7, 11, 2, 1, red)
		"wide":
			_rect(img, 5, 10, 6, 4, SKIN_DARK)
			_rect(img, 6, 12, 4, 1, red)
		"o":
			_rect(img, 7, 10, 2, 3, SKIN_DARK)
		"frown":
			_rect(img, 5, 11, 6, 1, SKIN_DARK)
			_px(img, 4, 12, SKIN_DARK)
			_px(img, 11, 12, SKIN_DARK)
		_:
			_rect(img, 6, 11, 4, 1, SKIN_DARK)


func _set_face(eyes: String, mouth_kind: String, blush: bool) -> void:
	var key := "%s|%s|%s" % [eyes, mouth_kind, blush]
	if key == face_key:
		return
	face_key = key
	if not face_cache.has(key):
		var img := Image.create(FACE_PX, FACE_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		if blush:
			var bc := Color(1.0, 0.45, 0.55, 0.65)
			_rect(img, 2, 9, 2, 1, bc)
			_rect(img, 12, 9, 2, 1, bc)
		_eyes(img, eyes)
		_mouth(img, mouth_kind)
		face_cache[key] = ImageTexture.create_from_image(img)
	face_mat.albedo_texture = face_cache[key]


# ------------------------------------------------------------ state

func set_state(emo: String, gest: String, talk: bool) -> void:
	emotion = emo if EMOTIONS.has(emo) else "neutral"
	gesture = gest
	speaking = talk
	hearts.emitting = emotion == "love"


func update(dt: float, partner: Node3D) -> void:
	t += dt
	blink_t -= dt
	var emo: Dictionary = EMOTIONS[emotion]
	var eyes: String = emo["eyes"]
	if blink_t < 0.0:
		if blink_t > -0.12:
			eyes = "blink"
		else:
			blink_t = randf_range(2.0, 4.0)
	var m: String = emo["mouth"]
	if speaking:
		m = "wide" if mouth > 0.6 else ("open" if mouth > 0.22 else m)
	_set_face(eyes, m, bool(emo.get("blush", false)))

	# head: turn toward the other character while talking or listening
	var toward := 1.0 if seat_x > 0.0 else -1.0
	var yaw := look * 0.62 * toward
	var amp := mouth if speaking else 0.0
	var pitch := 0.07 * amp * sin(t * 9.0) + 0.04 * sin(t * 1.3)
	var roll := 0.0
	if emotion == "love":
		roll = 0.14 * sin(t * 1.7) * toward
	elif emotion == "angry":
		yaw += 0.12 * sin(t * 22.0)
	elif emotion == "sad":
		pitch += 0.22
	head.rotation = Vector3(pitch, yaw, roll)

	var bounce := 0.0
	if emotion in ["laugh", "happy"] and speaking:
		bounce = 0.035 * sin(t * 18.0)
	torso.position.y = bounce
	torso.rotation.z = look * 0.07 * toward

	_arms(dt, toward)


func _arms(dt: float, toward: float) -> void:
	var lx := 1.25
	var rx := 1.25
	var ry := 0.0
	var ly := 0.0
	if not driver:
		lx = 0.95
		rx = 0.95
	match gesture:
		"talk":
			if not driver:
				rx = 1.35 + 0.35 * sin(t * 5.0)
			else:
				rx = 1.25 + 0.05 * sin(t * 5.0)
		"up":
			lx = 3.0 + 0.25 * sin(t * 13.0)
			rx = 3.0 + 0.25 * sin(t * 13.0 + 1.0)
		"point":
			rx = 1.5
			ry = 0.9 * toward
			if driver:
				ry = 0.0
				rx = 1.25
		"wave":
			rx = 2.6 + 0.4 * sin(t * 10.0)
	arm_l.rotation = arm_l.rotation.lerp(Vector3(lx, ly, 0), minf(12.0 * dt, 1.0))
	arm_r.rotation = arm_r.rotation.lerp(Vector3(rx, ry, 0), minf(12.0 * dt, 1.0))
