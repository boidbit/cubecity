extends Node3D
# Story lab: a blocky character. Built from boxes like everything else in the game, with a
# pixel-art face that changes with the emotion and flaps with the voice. Faces -z.
#
# In the car (seated) it only turns its head, swings its arms and bobs. Out of the car it
# stands, walks or runs along a list of points (walk_to), sits on the ground, falls over or
# hugs; the legs and arms swing procedurally. It has no physics body: the story keeps it on
# the pavement and clears the traffic around it.

const FACE_PX := 16
const SKIN_DARK := Color(0.12, 0.09, 0.1)
const PINK := Color(1.0, 0.35, 0.55)
const EMOTIONS := {
	"neutral": {"eyes": "open", "mouth": "smile", "brows": "flat"},
	"smug": {"eyes": "smug", "mouth": "smirk", "brows": "one"},
	"love": {"eyes": "heart", "mouth": "smile", "blush": true, "brows": "soft"},
	"shock": {"eyes": "wide", "mouth": "o", "brows": "up"},
	"angry": {"eyes": "angry", "mouth": "frown", "brows": "angry"},
	"sad": {"eyes": "sad", "mouth": "frown", "brows": "sad"},
	"happy": {"eyes": "happy", "mouth": "smile", "blush": true, "brows": "soft"},
	"laugh": {"eyes": "happy", "mouth": "open", "brows": "up"},
	"cry": {"eyes": "cry", "mouth": "cry", "brows": "sad"},
	"shy": {"eyes": "shy", "mouth": "small", "blush": true, "brows": "soft"},
	"scared": {"eyes": "scared", "mouth": "wavy", "brows": "up"},
	"think": {"eyes": "think", "mouth": "flat", "brows": "one"},
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
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
# out of the car
const LEG := 0.93           # hip height when standing
const WALK_SPEED := 1.7
const RUN_SPEED := 4.6
var size := 1.0            # overall scale (kids are smaller); LEG is scaled by it
var seated := true
var pose := "seated"        # seated, stand, sit, bench, kneel, fall, dance, cheer,
                            # fight (fists up), punch, hit, ko, carried
var path: Array[Vector3] = []
var running := false
var pace := 1.0             # walking speed multiplier (brisk walk to and from the car)
var speed_now := 0.0
var stride := 0.0
var face_point := Vector3.INF    # stand facing this (and look at it); INF = no target
var hug := false
var fall_t := 0.0
var pose_t := 0.0            # time in the current pose (cheer ends by itself)
var seat_h := 0.45           # bench: seat height
var then_pose := ""          # take this pose (facing then_yaw) when the walk ends
var then_yaw := 0.0
# something in the right hand (an ice cream, a glass of chai, flowers ...)
var held: Node3D = null
var reach_t := 0.0           # arm stretched out (giving or taking) while > 0
var bite_t := 3.0            # food: next bite or sip
var t := 0.0
var emo_t := 0.0             # time since the emotion changed (poses ease in)
var glance_t := 3.0          # eyes dart somewhere now and then
var gaze := Vector2i.ZERO
var phase := randf() * 10.0  # so two people do not breathe in step
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


# cfg ("look" in the screenplay's cast), colours as html strings:
#   style: boy | girl | man | woman | oldman | oldwoman | kid
#   skin, hair, shirt, pants
#   hair_style: short | long | bald | spiky | bun | ponytail (default from the style)
#   build: slim | normal | big        height: 0.8 - 1.15
#   acc: any of cap, hat, glasses, sunglasses, mustache, beard, mask, tie, scarf, bindi
func build(who_id: String, cfg: Dictionary, is_driver: bool, x: float) -> void:
	who = who_id
	driver = is_driver
	seat_x = x
	style = str(cfg.get("style", "boy"))
	var female: bool = style in ["girl", "woman", "oldwoman"]
	var old: bool = style.begins_with("old")
	var skin := Color.from_string(str(cfg.get("skin", "#f2b58f")), Color(0.95, 0.72, 0.56))
	var hair := Color.from_string(str(cfg.get("hair", "#9a9a9a" if old else "#2b1d16")), Color(0.17, 0.11, 0.09))
	var shirt := Color.from_string(str(cfg.get("shirt", "#3b7ddd")), Color(0.23, 0.49, 0.87))
	var pants := Color.from_string(str(cfg.get("pants", "#29304a")), Color(0.16, 0.18, 0.28))
	var build_k: float = {"slim": 0.88, "big": 1.3}.get(str(cfg.get("build", "normal")), 1.0)
	size = clampf(float(cfg.get("height", 0.8 if style == "kid" else 1.0)), 0.75, 1.2)
	scale = Vector3.ONE * size
	# slim, Roblox-like proportions: narrow shoulders, long legs
	var tw := (0.38 if female else 0.42) * build_k
	var td := 0.24 * maxf(build_k, 1.0)

	torso = Node3D.new()
	add_child(torso)
	_box(torso, Vector3(tw, 0.5, td), Vector3(0, 0.25, 0), shirt)
	if female:
		# a kurti / dress flaring out over the hips
		_box(torso, Vector3(tw + 0.08, 0.18, td + 0.06), Vector3(0, 0.04, 0), shirt.darkened(0.08))
	# legs: hip and knee pivots; rotating about x swings them forward. Seated, the thighs point
	# forward and the shins down (hidden inside the car body).
	var legs := []
	var lw := tw * 0.42
	for sd in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(sd * tw * 0.25, 0.02, 0)
		add_child(hip)
		_box(hip, Vector3(lw, 0.47, 0.2), Vector3(0, -0.22, 0), pants)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.45, 0)
		hip.add_child(knee)
		_box(knee, Vector3(lw * 0.92, 0.42, 0.18), Vector3(0, -0.21, 0), pants)
		_box(knee, Vector3(lw, 0.09, 0.28), Vector3(0, -0.44, -0.05), Color(0.12, 0.1, 0.1))
		legs.append([hip, knee])
	hip_l = legs[0][0]
	knee_l = legs[0][1]
	hip_r = legs[1][0]
	knee_r = legs[1][1]
	for hip: Node3D in [hip_l, hip_r]:
		hip.rotation.x = PI * 0.5
	for knee: Node3D in [knee_l, knee_r]:
		knee.rotation.x = -PI * 0.5

	head = Node3D.new()
	head.position = Vector3(0, 0.5, 0)
	head.scale = Vector3.ONE * 0.9       # the head is built at 0.5 m and shown a little smaller
	torso.add_child(head)
	_box(head, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.27, 0), skin)
	var hs := str(cfg.get("hair_style", "long" if female else ("bald" if style == "oldman" else "short")))
	_build_hair(hair, hs, female)
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
	var acc: Array = cfg.get("acc", [])
	_accessories(acc, hair, shirt)

	# arms hang from the shoulders; rotating about x swings them forward
	arm_l = _make_arm(-1.0, tw, shirt, skin)
	arm_r = _make_arm(1.0, tw, shirt, skin)

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


func _make_arm(side: float, tw: float, shirt: Color, skin: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * (tw * 0.5 + 0.06), 0.44, 0)
	torso.add_child(pivot)
	_box(pivot, Vector3(0.12, 0.4, 0.12), Vector3(0, -0.2, 0), shirt)
	_box(pivot, Vector3(0.13, 0.12, 0.13), Vector3(0, -0.46, 0), skin)
	return pivot


func _build_hair(hair: Color, hs: String, female: bool) -> void:
	if hs == "bald":
		_box(head, Vector3(0.52, 0.2, 0.2), Vector3(0, 0.3, 0.2), hair)      # a fringe round the back
		return
	_box(head, Vector3(0.56, 0.12, 0.56), Vector3(0, 0.56, 0.0), hair)        # top
	_box(head, Vector3(0.56, 0.5, 0.12), Vector3(0, 0.3, 0.28), hair)         # back
	for s in [-1.0, 1.0]:
		_box(head, Vector3(0.08, 0.34, 0.5), Vector3(s * 0.27, 0.38, 0.0), hair)   # sides
	match hs:
		"long":
			_box(head, Vector3(0.6, 0.12, 0.1), Vector3(0, 0.5, -0.27), hair)     # fringe
			_box(head, Vector3(0.64, 0.7, 0.12), Vector3(0, 0.0, 0.31), hair)     # long hair down the back
			for s in [-1.0, 1.0]:
				_box(head, Vector3(0.1, 0.5, 0.18), Vector3(s * 0.3, 0.12, -0.1), hair)
		"bun":
			_box(head, Vector3(0.6, 0.1, 0.1), Vector3(0, 0.52, -0.27), hair)
			_box(head, Vector3(0.24, 0.2, 0.24), Vector3(0, 0.7, 0.12), hair)
		"ponytail":
			_box(head, Vector3(0.6, 0.1, 0.1), Vector3(0, 0.52, -0.27), hair)
			_box(head, Vector3(0.14, 0.5, 0.14), Vector3(0, 0.25, 0.4), hair)
		"spiky":
			for i in 4:
				_box(head, Vector3(0.12, 0.16, 0.12), Vector3(-0.18 + i * 0.12, 0.66, -0.1 + (i % 2) * 0.14), hair)
		_:
			_box(head, Vector3(0.34, 0.14, 0.16), Vector3(0.05, 0.64, -0.2), hair)  # quiff
	if female:
		_box(head, Vector3(0.18, 0.14, 0.12), Vector3(0.22, 0.62, -0.1), PINK)   # bow
		_box(head, Vector3(0.06, 0.06, 0.1), Vector3(0.22, 0.62, -0.1), Color(1, 0.8, 0.9))


# Caps, glasses, moustaches ... built on the head (in its 0.5 m space) and the torso.
func _accessories(acc: Array, hair: Color, shirt: Color) -> void:
	var dark := Color(0.08, 0.08, 0.1)
	for a in acc:
		match str(a):
			"cap":
				var c := shirt.lerp(Color(0.85, 0.15, 0.15), 0.6)
				_box(head, Vector3(0.58, 0.14, 0.58), Vector3(0, 0.6, 0.0), c)
				_box(head, Vector3(0.44, 0.04, 0.24), Vector3(0, 0.55, -0.38), c)
			"hat":
				_box(head, Vector3(0.78, 0.04, 0.78), Vector3(0, 0.6, 0.0), dark)
				_box(head, Vector3(0.5, 0.22, 0.5), Vector3(0, 0.73, 0.0), dark)
				_box(head, Vector3(0.51, 0.05, 0.51), Vector3(0, 0.64, 0.0), Color(0.6, 0.1, 0.1))
			"glasses", "sunglasses":
				for s in [-1.0, 1.0]:
					if str(a) == "sunglasses":
						_box(head, Vector3(0.17, 0.11, 0.03), Vector3(s * 0.11, 0.3, -0.27), dark)
					else:
						# just the frame, the eyes show through
						for e in [-1.0, 1.0]:
							_box(head, Vector3(0.17, 0.02, 0.02), Vector3(s * 0.11, 0.3 + e * 0.06, -0.27), dark)
							_box(head, Vector3(0.02, 0.12, 0.02), Vector3(s * 0.11 + e * 0.085, 0.3, -0.27), dark)
				_box(head, Vector3(0.06, 0.03, 0.03), Vector3(0, 0.32, -0.27), dark)
				for s in [-1.0, 1.0]:
					_box(head, Vector3(0.03, 0.03, 0.3), Vector3(s * 0.25, 0.32, -0.12), dark)
			"mustache":
				_box(head, Vector3(0.24, 0.05, 0.03), Vector3(0, 0.2, -0.27), hair.darkened(0.3))
			"beard":
				_box(head, Vector3(0.5, 0.14, 0.06), Vector3(0, 0.07, -0.26), hair.darkened(0.2))
				for s in [-1.0, 1.0]:
					_box(head, Vector3(0.06, 0.22, 0.3), Vector3(s * 0.25, 0.13, -0.12), hair.darkened(0.2))
			"mask":
				# a bandit's bandana over nose and mouth
				_box(head, Vector3(0.54, 0.22, 0.04), Vector3(0, 0.13, -0.27), Color(0.12, 0.12, 0.14))
				_box(head, Vector3(0.54, 0.22, 0.04), Vector3(0, 0.13, 0.27), Color(0.12, 0.12, 0.14))
			"tie":
				_box(torso, Vector3(0.07, 0.32, 0.02), Vector3(0, 0.28, -0.13), Color(0.7, 0.1, 0.12))
			"scarf":
				_box(torso, Vector3(0.48, 0.1, 0.3), Vector3(0, 0.46, 0), shirt.lerp(Color(1, 0.8, 0.2), 0.7))
			"bindi":
				_box(head, Vector3(0.04, 0.04, 0.01), Vector3(0, 0.39, -0.258), Color(0.85, 0.05, 0.1))


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


# Eyes are 4 px wide with a white and a 2 px pupil that can look left / right (gx) and
# up / down (gy); brows sit on row 3.
func _eyes(img: Image, kind: String, gx: int, gy: int, frame: int) -> void:
	var white := Color(0.97, 0.97, 0.97)
	var tear := Color(0.45, 0.75, 1.0)
	for ex in [3, 9]:
		var px: int = ex + 1 + gx
		match kind:
			"open":
				_rect(img, ex, 5, 4, 4, white)
				_rect(img, px, 6 + gy, 2, 3 - absi(gy), SKIN_DARK)
			"blink":
				_rect(img, ex, 7, 4, 1, SKIN_DARK)
			"smug":
				_rect(img, ex, 6, 4, 2, white)
				_rect(img, px, 6, 2, 2, SKIN_DARK)
				_rect(img, ex, 5, 4, 1, SKIN_DARK)
			"happy":
				_px(img, ex, 7, SKIN_DARK)
				_rect(img, ex + 1, 6, 2, 1, SKIN_DARK)
				_px(img, ex + 3, 7, SKIN_DARK)
			"heart":
				var pat := ["1001", "1111", "0110"]
				for y in 3:
					for x in 4:
						if pat[y][x] == "1":
							_px(img, ex + x, 5 + y, PINK)
			"wide":
				_rect(img, ex, 4, 4, 5, white)
				_rect(img, px, 6, 2, 2, SKIN_DARK)
			"scared":
				_rect(img, ex, 4, 4, 5, white)
				_px(img, ex + 1 + (frame % 2), 6, SKIN_DARK)
			"angry":
				_rect(img, ex, 6, 4, 3, white)
				_rect(img, px, 6, 2, 3, SKIN_DARK)
			"sad":
				_rect(img, ex, 5, 4, 4, white)
				_rect(img, px, 7, 2, 2, SKIN_DARK)
				_px(img, ex + 1, 9, tear)
			"cry":
				# squeezed shut, tears running down (two frames)
				_rect(img, ex, 7, 4, 1, SKIN_DARK)
				_px(img, ex, 6, SKIN_DARK)
				_px(img, ex + 3, 6, SKIN_DARK)
				for y in range(8, 14):
					if (y + frame) % 2 == 0:
						_px(img, ex + 1, y, tear)
			"shy":
				_rect(img, ex, 6, 4, 3, white)
				_rect(img, ex + 2, 7, 2, 2, SKIN_DARK)
			"think":
				_rect(img, ex, 5, 4, 4, white)
				_rect(img, ex + 2, 5, 2, 2, SKIN_DARK)


func _brows(img: Image, kind: String) -> void:
	match kind:
		"flat":
			_rect(img, 3, 3, 4, 1, SKIN_DARK)
			_rect(img, 9, 3, 4, 1, SKIN_DARK)
		"soft":
			_rect(img, 4, 3, 3, 1, SKIN_DARK)
			_rect(img, 9, 3, 3, 1, SKIN_DARK)
		"up":
			_rect(img, 3, 2, 4, 1, SKIN_DARK)
			_rect(img, 9, 2, 4, 1, SKIN_DARK)
		"one":
			_rect(img, 3, 4, 4, 1, SKIN_DARK)
			_rect(img, 9, 2, 4, 1, SKIN_DARK)
		"angry":
			for i in 4:
				_px(img, 3 + i, 2 + i / 2, SKIN_DARK)
				_px(img, 12 - i, 2 + i / 2, SKIN_DARK)
		"sad":
			for i in 4:
				_px(img, 3 + i, 4 - i / 2, SKIN_DARK)
				_px(img, 12 - i, 4 - i / 2, SKIN_DARK)


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
		"cry":
			_rect(img, 5, 11, 6, 2, SKIN_DARK)
			_rect(img, 6, 12, 4, 1, red)
			_px(img, 4, 13, SKIN_DARK)
			_px(img, 11, 13, SKIN_DARK)
		"wavy":
			for i in 6:
				_px(img, 5 + i, 11 + (i % 2), SKIN_DARK)
		"small":
			_rect(img, 7, 11, 2, 1, SKIN_DARK)
			_px(img, 6, 10, SKIN_DARK)
			_px(img, 9, 10, SKIN_DARK)
		"flat":
			_rect(img, 6, 11, 4, 1, SKIN_DARK)
		_:
			_rect(img, 6, 11, 4, 1, SKIN_DARK)


func _set_face(eyes: String, mouth_kind: String, blush: bool, brows := "flat", gx := 0, gy := 0, frame := 0) -> void:
	var key := "%s|%s|%s|%s|%d|%d|%d" % [eyes, mouth_kind, blush, brows, gx, gy, frame]
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
		_eyes(img, eyes, gx, gy, frame)
		if eyes != "blink":
			_brows(img, brows)
		_mouth(img, mouth_kind)
		face_cache[key] = ImageTexture.create_from_image(img)
	face_mat.albedo_texture = face_cache[key]


# ------------------------------------------------------------ state

func set_state(emo: String, gest: String, talk: bool) -> void:
	var e := emo if EMOTIONS.has(emo) else "neutral"
	if e != emotion:
		blink_t = 0.0          # a blink hides the change of face
		emo_t = 0.0
	emotion = e
	gesture = gest
	speaking = talk
	hearts.emitting = emotion == "love"


# ------------------------------------------------------------ out of the car

# Leaves the seat: from now on the rig lives in the world, standing at `at` facing `yaw`.
func stand_at(at: Vector3, yaw: float) -> void:
	seated = false
	pose = "stand"
	global_position = Vector3(at.x, at.y + LEG * size, at.z)
	rotation = Vector3(0, yaw, 0)
	path.clear()


# Back in the seat (the story has already made the car the parent).
func sit_in_car(seat: Vector3) -> void:
	seated = true
	pose = "seated"
	path.clear()
	speed_now = 0.0
	position = seat
	rotation = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	for hip: Node3D in [hip_l, hip_r]:
		hip.rotation.x = PI * 0.5
	for knee: Node3D in [knee_l, knee_r]:
		knee.rotation.x = -PI * 0.5


func walk_to(points: Array, run := false, brisk := 1.0) -> void:
	path.clear()
	then_pose = ""
	for p in points:
		path.append(Vector3(p.x, 0.0, p.z))
	running = run
	pace = brisk
	if pose != "stand":
		pose = "stand"
		rotation.x = 0.0


func arrived() -> bool:
	return path.is_empty()


func sit_down() -> void:
	path.clear()
	pose = "sit"


# Walks to a bench seat (the last point), turns to face `yaw` and sits down on it.
func sit_on(points: Array, yaw: float, height: float) -> void:
	walk_to(points)
	seat_h = height
	then_pose = "bench"
	then_yaw = yaw


func dance() -> void:
	path.clear()
	pose = "dance"
	pose_t = 0.0


func cheer() -> void:
	path.clear()
	pose = "cheer"
	pose_t = 0.0


# Fighting: a stance, a punch, being hit (back to the stance), knocked out (stays down).
func set_pose(p: String) -> void:
	if p != "fight":
		path.clear()
	pose = p
	pose_t = 0.0
	rotation.x = 0.0 if p in ["fight", "punch"] else rotation.x


# Carried off over somebody's shoulder (the story makes the carrier the parent).
func be_carried() -> void:
	path.clear()
	seated = false
	pose = "carried"
	pose_t = 0.0
	position = Vector3(-0.3, 0.68, 0.0)
	rotation = Vector3(0, 0, -PI * 0.5)
	set_state("shock", "idle", speaking)


func hold(prop: Node3D) -> void:
	if held != null and is_instance_valid(held):
		held.queue_free()
	held = prop
	if prop.get_parent() != null:
		prop.reparent(arm_r, false)
	else:
		arm_r.add_child(prop)
	prop.position = Vector3(0, -0.56, -0.06)
	prop.scale = Vector3.ONE * 0.85
	bite_t = 2.5


# Lets go of the held thing (the caller takes it). null if the hand is empty.
func let_go() -> Node3D:
	var p := held
	held = null
	return p if p != null and is_instance_valid(p) else null


func kneel() -> void:
	path.clear()
	pose = "kneel"


func stand_up() -> void:
	pose = "stand"
	rotation.x = 0.0


func fall_down() -> void:
	path.clear()
	pose = "fall"
	fall_t = 0.0


func _yaw_to(p: Vector3) -> float:
	var d := p - global_position
	return atan2(-d.x, -d.z)


func _locomotion(dt: float) -> void:
	if pose == "carried":
		pose_t += dt
		# kicking and waving
		var k := sin(pose_t * 11.0)
		hip_l.rotation.x = 0.5 + 0.5 * k
		hip_r.rotation.x = 0.5 - 0.5 * k
		knee_l.rotation.x = -0.6
		knee_r.rotation.x = -0.6
		return
	var ground := 0.0
	var want_speed := 0.0
	if not path.is_empty():
		var tgt := path[0]
		var here := Vector3(global_position.x, 0.0, global_position.z)
		var d := tgt - here
		if d.length() < 0.25:
			path.pop_front()
			if path.is_empty() and then_pose != "":
				pose = then_pose
				rotation.y = then_yaw
				then_pose = ""
		else:
			want_speed = RUN_SPEED if running else WALK_SPEED * pace
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(10.0 * dt, 1.0))
			var step := minf(speed_now * dt, d.length())
			global_position += d.normalized() * step
	elif face_point != Vector3.INF and pose in ["stand", "dance", "cheer", "fight"]:
		rotation.y = lerp_angle(rotation.y, _yaw_to(face_point), minf(5.0 * dt, 1.0))
	speed_now = move_toward(speed_now, want_speed, 9.0 * dt)
	stride += dt * speed_now * (2.3 if running else 3.4)
	var sw := sin(stride)
	var amp := clampf(speed_now / WALK_SPEED, 0.0, 1.0) * (0.95 if running else 0.55)
	var hl := sw * amp
	var hr := -sw * amp
	var kl := -maxf(0.0, -sw) * amp * 1.4
	var kr := -maxf(0.0, sw) * amp * 1.4
	var lift := LEG
	var tilt := 0.0
	pose_t += dt
	match pose:
		"sit":
			hl = 1.45
			hr = 1.45
			kl = -0.15
			kr = -0.15
			lift = 0.3
		"bench":
			hl = 1.5
			hr = 1.5
			kl = -1.45
			kr = -1.45
			lift = seat_h + 0.12
		"dance":
			# knees bounce to the beat, one leg then the other
			var b := sin(pose_t * 7.0)
			hl = maxf(b, 0.0) * 0.45
			hr = maxf(-b, 0.0) * 0.45
			kl = -hl * 1.3
			kr = -hr * 1.3
			lift = LEG - 0.06 + absf(b) * 0.05
		"cheer":
			# little jumps for joy
			lift = LEG + absf(sin(pose_t * 8.0)) * 0.28
			hl = 0.2
			hr = 0.2
			kl = -0.35
			kr = -0.35
			if pose_t > 2.2:
				pose = "stand"
		"fight", "punch":
			# knees bent, weight forward, a little bounce
			var b := absf(sin(pose_t * 7.0))
			hl = 0.35
			hr = -0.1
			kl = -0.55
			kr = -0.3
			lift = LEG - 0.07 + b * 0.03
			if pose == "punch" and pose_t > 0.45:
				pose = "fight"
		"hit":
			# knocked back a step, then back into the stance
			tilt = 0.45 * maxf(0.0, 1.0 - pose_t / 0.6)
			hl = 0.2
			hr = -0.2
			kl = -0.3
			kr = -0.3
			if pose_t < 0.25:
				global_position -= -global_transform.basis.z * 2.2 * dt
			if pose_t > 0.7:
				pose = "fight"
		"ko":
			# flat on the back
			tilt = minf(pose_t / 0.4, 1.0) * 1.45
			lift = lerpf(LEG, 0.3, minf(pose_t / 0.4, 1.0))
			hl = 0.25
			hr = 0.1
			if pose_t < 0.35:
				global_position -= -global_transform.basis.z * 3.0 * dt
		"kneel":
			# one knee down (proposal style)
			hl = 1.5
			kl = -1.5
			hr = -0.15
			kr = -1.45
			lift = 0.55
		"fall":
			fall_t += dt
			tilt = -minf(fall_t / 0.35, 1.0) * 1.45
			lift = lerpf(LEG, 0.32, minf(fall_t / 0.35, 1.0))
			hl = 0.3
			hr = -0.2
	hip_l.rotation.x = lerpf(hip_l.rotation.x, hl, minf(14.0 * dt, 1.0))
	hip_r.rotation.x = lerpf(hip_r.rotation.x, hr, minf(14.0 * dt, 1.0))
	knee_l.rotation.x = lerpf(knee_l.rotation.x, kl, minf(14.0 * dt, 1.0))
	knee_r.rotation.x = lerpf(knee_r.rotation.x, kr, minf(14.0 * dt, 1.0))
	global_position.y = lerpf(global_position.y, ground + (lift + absf(sw) * 0.05 * amp) * size, minf(12.0 * dt, 1.0))
	rotation.x = lerpf(rotation.x, tilt, minf(10.0 * dt, 1.0))
	var lean := 0.0
	if running and speed_now > 1.0:
		lean = -0.22
	elif pose == "stand" and path.is_empty():
		lean = {"sad": -0.1, "cry": -0.14, "angry": -0.1, "shock": 0.12, "scared": 0.1, "laugh": -0.08 + 0.08 * sin(t * 9.0),
			"shy": -0.05, "smug": 0.06}.get(emotion, 0.0)
	torso.rotation.x = lerpf(torso.rotation.x, lean, minf(6.0 * dt, 1.0))
	var twist := 0.0
	if pose == "dance":
		twist = 0.35 * sin(pose_t * 3.5)
	elif pose == "punch":
		twist = 0.45 if pose_t > 0.13 and pose_t < 0.35 else -0.2
	if pose == "stand" and path.is_empty() and emotion == "shy":
		twist = 0.18 * sin(t * 1.6 + phase)      # swaying, embarrassed
	torso.rotation.y = twist if pose == "dance" else lerpf(torso.rotation.y, twist, minf(14.0 * dt, 1.0))


func update(dt: float, partner: Node3D) -> void:
	t += dt
	emo_t += dt
	if not seated:
		_locomotion(dt)
	blink_t -= dt
	var emo: Dictionary = EMOTIONS[emotion]
	var eyes: String = emo["eyes"]
	if blink_t < 0.0:
		if blink_t > -0.12:
			eyes = "blink"
		else:
			blink_t = randf_range(2.0, 4.5)
	# the eyes look about now and then (not while talking: then they look at whoever listens)
	glance_t -= dt
	if glance_t < 0.0:
		if glance_t < -0.6 or speaking:
			gaze = Vector2i.ZERO
			glance_t = randf_range(1.8, 4.0)
		elif gaze == Vector2i.ZERO:
			gaze = Vector2i([-1, 1][randi() % 2], [0, 0, 1][randi() % 3])
	var m: String = emo["mouth"]
	if speaking:
		m = "wide" if mouth > 0.6 else ("open" if mouth > 0.22 else m)
	_set_face(eyes, m, bool(emo.get("blush", false)), str(emo.get("brows", "flat")), gaze.x, gaze.y, int(t * 6.0) % 2)

	# head: turn toward the other character while talking or listening
	var toward := 1.0 if seat_x > 0.0 else -1.0
	var yaw := look * 0.62 * toward
	if not seated:
		yaw = 0.0
		if face_point != Vector3.INF and path.is_empty():
			yaw = clampf(wrapf(_yaw_to(face_point) - rotation.y, -PI, PI), -0.9, 0.9) * look
	var amp := mouth if speaking else 0.0
	var pitch := 0.07 * amp * sin(t * 9.0) + 0.03 * sin(t * 1.3 + phase)
	yaw += 0.03 * sin(t * 0.8 + phase)
	var roll := 0.0
	# listening: a little nod now and then
	if not speaking and look > 0.5 and emotion in ["neutral", "happy", "love", "smug"]:
		pitch += 0.06 * maxf(0.0, sin(t * 3.0 + phase)) * maxf(0.0, sin(t * 0.7 + phase))
	match emotion:
		"love":
			roll = 0.14 * sin(t * 1.7) * toward
		"angry":
			yaw += 0.06 * sin(t * 20.0) * (1.0 if speaking else 0.3)
			pitch -= 0.08
		"sad":
			pitch += 0.22
		"cry":
			pitch += 0.3 + 0.04 * sin(t * 14.0)
		"shy":
			pitch += 0.18
			roll = 0.12 * toward
		"scared":
			yaw += 0.03 * sin(t * 30.0)
		"think":
			roll = -0.12 * toward
			pitch -= 0.1
		"shock":
			pitch -= 0.12 * maxf(0.0, 1.0 - emo_t * 2.0)
	head.rotation = head.rotation.lerp(Vector3(pitch, yaw, roll), minf(10.0 * dt, 1.0))

	var bounce := 0.0
	if emotion in ["laugh", "happy"] and speaking:
		bounce = 0.035 * sin(t * 18.0)
	elif emotion == "cry":
		bounce = 0.012 * sin(t * 16.0)      # sobbing
	# breathing (the head moves with the chest), slower when sad
	var breath := 1.0 + 0.016 * sin(t * (1.1 if emotion in ["sad", "cry"] else 1.7) + phase)
	torso.scale = Vector3(1.0, breath, 1.0)
	torso.position.y = bounce
	torso.rotation.z = look * 0.07 * toward if seated else 0.012 * sin(t * 0.6 + phase)

	_arms(dt, toward)


# Arms for how they feel, while standing still (or sitting next to the driver):
# [left x, left y, right x, right y]. Rotating x swings an arm forward, y turns it in.
func _feeling_arms() -> Array:
	var w := sin(t * 2.0 + phase)
	match emotion:
		"sad":
			return [0.15, 0.15, 0.15, -0.15]
		"angry":
			return [0.5, 0.3, 0.5, -0.3]
		"shock":
			# hands fly up, then come down a little
			var k := clampf(emo_t * 3.0, 0.0, 1.0)
			return [lerpf(1.0, 2.2, k) - maxf(emo_t - 1.2, 0.0) * 0.5, 0.5, lerpf(1.0, 2.2, k) - maxf(emo_t - 1.2, 0.0) * 0.5, -0.5]
		"love":
			return [1.25, -0.6, 1.25, 0.6]
		"laugh":
			return [0.9, -0.35 + 0.1 * w, 0.4, 0.0]
		"smug":
			return [1.2, -1.0, 1.25, 1.0]
		"cry":
			return [2.45, -0.55, 2.45, 0.55]
		"shy":
			return [-0.45, 0.0, -0.45, 0.0]
		"scared":
			return [1.7 + 0.08 * sin(t * 25.0), 0.35, 1.7 + 0.08 * sin(t * 25.0 + 1.0), -0.35]
		"think":
			return [1.0, -0.6, 2.35, -0.75]
		"happy":
			return [0.25 + 0.1 * w, 0.1, 0.25 - 0.1 * w, -0.1]
	return []


func _arms(dt: float, toward: float) -> void:
	var lx := 1.25
	var rx := 1.25
	var ry := 0.0
	var ly := 0.0
	if not seated:
		# hanging, swinging against the legs while walking
		var sw := sin(stride) * clampf(speed_now / WALK_SPEED, 0.0, 1.0) * (0.9 if running else 0.5)
		lx = 0.08 - sw
		rx = 0.08 + sw
		if pose in ["sit", "bench"]:
			lx = 0.7
			rx = 0.7
		elif pose == "fall":
			lx = 2.6
			rx = 2.4
		elif pose == "dance":
			lx = 2.3 + 0.6 * sin(pose_t * 7.0)
			rx = 2.3 + 0.6 * sin(pose_t * 7.0 + PI)
			ly = -0.3
			ry = 0.3
		elif pose == "cheer":
			lx = 3.0 + 0.2 * sin(pose_t * 16.0)
			rx = 3.0 + 0.2 * sin(pose_t * 16.0 + 1.0)
		elif pose in ["fight", "punch", "hit"]:
			# fists up in front of the face
			lx = 1.7
			rx = 1.55
			ly = 0.35
			ry = -0.35
			if pose == "punch":
				# wind up, then a straight right
				var k := pose_t / 0.45
				rx = 1.2 if k < 0.3 else 1.62
				ry = 0.25 if k < 0.3 else 0.0
			elif pose == "hit":
				lx = 2.3
				rx = 2.4
		elif pose == "ko":
			lx = 2.9
			rx = 2.9
		elif pose == "carried":
			lx = 2.4 + 0.6 * sin(t * 12.0)
			rx = 2.4 + 0.6 * sin(t * 12.0 + 2.0)
	elif not driver:
		lx = 0.95
		rx = 0.95
	# how they feel shows in the arms when they are not busy walking, fighting or dancing
	var still := (not seated and pose == "stand" and path.is_empty()) or (seated and not driver)
	var feel := _feeling_arms() if still else []
	if not feel.is_empty():
		lx = feel[0]
		ly = feel[1]
		rx = feel[2]
		ry = feel[3]
	# talking adds hands on top of the feeling (bigger when excited)
	var big := emotion in ["angry", "shock", "laugh", "happy"]
	match gesture:
		"talk":
			if not seated:
				if feel.is_empty() or emotion in ["neutral", "happy", "sad"]:
					rx = (0.6 if feel.is_empty() else rx + 0.3) + (0.45 if big else 0.3) * sin(t * 5.0 + phase)
					lx = lx + 0.12 * sin(t * 3.7 + phase)
				else:
					rx += 0.12 * sin(t * 5.0)
			elif not driver:
				if feel.is_empty():
					rx = 1.35 + 0.35 * sin(t * 5.0)
				else:
					rx += 0.15 * sin(t * 5.0)
			else:
				rx = 1.25 + 0.05 * sin(t * 5.0)
		"up":
			lx = 3.0 + 0.25 * sin(t * 13.0)
			rx = 3.0 + 0.25 * sin(t * 13.0 + 1.0)
		"point":
			rx = 1.5
			ry = 0.9 * toward if seated else 0.0
			if driver and seated:
				ry = 0.0
				rx = 1.25
		"wave":
			rx = 2.6 + 0.4 * sin(t * 10.0)
	if held != null and is_instance_valid(held) and pose not in ["fall", "dance", "cheer"]:
		# holding it up in front; food goes to the mouth now and then
		rx = 0.95
		ry = 0.0
		if str(held.name) in ["icecream", "chai"] and not speaking:
			bite_t -= dt
			if bite_t < 0.0:
				rx = 2.05
				ry = -0.35
				if bite_t < -0.8:
					bite_t = randf_range(2.5, 4.0)
	if reach_t > 0.0:
		reach_t -= dt
		rx = 1.45
		ry = 0.0
	if hug:
		lx = 1.35
		rx = 1.35
		ly = -0.55
		ry = 0.55
	# eased: quick for walking and fighting, softer for feelings
	var k := 12.0 if (pose in ["fight", "punch", "hit", "ko", "carried"] or not path.is_empty()) else 7.0
	arm_l.rotation = arm_l.rotation.lerp(Vector3(lx, ly, 0), minf(k * dt, 1.0))
	arm_r.rotation = arm_r.rotation.lerp(Vector3(rx, ry, 0), minf(k * dt, 1.0))
	if held != null and is_instance_valid(held):
		held.global_rotation = Vector3(0, global_rotation.y, 0)     # keep it upright
