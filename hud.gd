class_name Hud
extends CanvasLayer
# HUD, minimap and multi-touch pads. Recorded runs (bot mode) get a clean video
# overlay instead: hook title, stats line, stars and BUSTED meter, no buttons.

class MiniMap extends Control:
	var main
	const RANGE := 170.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _to_map(p: Vector3) -> Vector2:
		var pl: Node3D = main.player
		var d := Vector2(p.x - pl.global_position.x, p.z - pl.global_position.z)
		var fwd3: Vector3 = -pl.global_transform.basis.z
		var f := Vector2(fwd3.x, fwd3.z).normalized()
		var r := Vector2(-f.y, f.x)
		var s := size.x * 0.5 / RANGE
		return size * 0.5 + Vector2(d.dot(r), -d.dot(f)) * s

	func _draw() -> void:
		if main == null or main.player == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1, 0.62))
		var w = main.world
		var pp: Vector3 = main.player.global_position
		var road_col := Color(0.62, 0.66, 0.72, 0.8)
		for k in range(0, World.N + 1):
			var lx: float = w.line(k)
			if absf(lx - pp.x) < RANGE * 1.5:
				draw_line(_to_map(Vector3(lx, 0, pp.z - RANGE * 1.6)), _to_map(Vector3(lx, 0, pp.z + RANGE * 1.6)), road_col, 3.0)
			if absf(lx - pp.z) < RANGE * 1.5:
				draw_line(_to_map(Vector3(pp.x - RANGE * 1.6, 0, lx)), _to_map(Vector3(pp.x + RANGE * 1.6, 0, lx)), road_col, 3.0)
		for c in main.police:
			if is_instance_valid(c) and not c.dead:
				draw_circle(_to_map(c.global_position), 4.0, Color(1.0, 0.25, 0.25))
		for c in main.blocks:
			if is_instance_valid(c):
				draw_circle(_to_map(c.global_position), 3.5, Color(1.0, 0.65, 0.1))
		if main.heli != null and main.heli.visible:
			draw_circle(_to_map(main.heli.global_position), 5.0, Color(0.35, 0.6, 1.0))
		var c0 := size * 0.5
		draw_colored_polygon(PackedVector2Array([c0 + Vector2(0, -9), c0 + Vector2(6, 7), c0 + Vector2(-6, 7)]), Color(0.4, 1.0, 0.55))


# Filled triangle pointing left (dir -1) or right (dir 1), drawn inside a steering pad.
class Arrow extends Control:
	var dir := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var w := minf(size.x, size.y) * 0.28
		draw_colored_polygon(PackedVector2Array([c + Vector2(w * dir, 0), c + Vector2(-w * 0.75 * dir, -w), c + Vector2(-w * 0.75 * dir, w)]), Color(1, 1, 1, 0.9))


# Five wanted-level stars for the video overlay.
class Stars extends Control:
	var level := 0
	var r := 30.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := r * 2.4
		var x0 := size.x * 0.5 - gap * 2.0
		for i in 5:
			var c := Vector2(x0 + gap * i, size.y * 0.5)
			var pts := PackedVector2Array()
			for k in 10:
				var rr := r if k % 2 == 0 else r * 0.45
				var a := -PI * 0.5 + k * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			var on := i < level
			draw_colored_polygon(pts, Color(1.0, 0.82, 0.2) if on else Color(0, 0, 0, 0.35))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.85) if on else Color(1, 1, 1, 0.5), 3.0)


# Thin streaks flying out from the edges of the screen: the feeling of speed.
class SpeedLines extends Control:
	var intensity := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if intensity < 0.02:
			return
		var c := size * 0.5
		var rmax := c.length()
		for i in 34:
			var a := (float(i) + randf()) * TAU / 34.0
			var d := Vector2(cos(a), sin(a))
			var r0 := rmax * randf_range(0.55, 0.8)
			var r1 := r0 + rmax * randf_range(0.12, 0.3) * (0.5 + intensity)
			draw_line(c + d * r0, c + d * r1, Color(1, 1, 1, 0.22 * intensity), 3.0)


var main
var video := false
var speed_lines: SpeedLines
var progress: ColorRect
var progress_bg: ColorRect
var lbl_caption: Label
var cap_tw: Tween
var flash_rect: ColorRect
var in_gas := 0.0
var in_steer := 0.0
var in_hb := 0.0
var in_nitro := false
var nitro_bar: ProgressBar
var touch_map := {}
var pads := {}
var lbl_speed: Label
var lbl_score: Label
var lbl_stars: Label
var lbl_info: Label
var lbl_banner: Label
var lbl_hint: Label
var lbl_over: Label
var lbl_title: Label
var lbl_hook: Label
var lbl_stats: Label
var stars: Stars
var hp_bar: ProgressBar
var hp_fill: StyleBoxFlat
var busted_box: Control
var busted_bar: ProgressBar
var busted_fill: StyleBoxFlat
var over_panel: ColorRect
var hurt_rect: ColorRect
var minimap: MiniMap
var banner_tw: Tween
var over_t := 0.0


func _label(text: String, size: int, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Full-width strip at a fraction `y` of the screen height, `h` units tall.
func _at(c: Control, y: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = y
	c.anchor_bottom = y
	c.offset_left = 30.0
	c.offset_right = -30.0
	c.offset_top = 0.0
	c.offset_bottom = h
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _bar(h: float, fill: Color) -> Array:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, h)
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := StyleBoxFlat.new()
	sf.bg_color = fill
	sf.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", sf)
	bar.add_theme_stylebox_override("background", bg)
	return [bar, sf]


func _pad(id: String, text: String, anchor: Vector2, off: Vector2, sz: Vector2, fill: Color, fc: Color) -> Panel:
	var p := Panel.new()
	p.anchor_left = anchor.x
	p.anchor_right = anchor.x
	p.anchor_top = anchor.y
	p.anchor_bottom = anchor.y
	p.offset_left = off.x
	p.offset_top = off.y
	p.offset_right = off.x + sz.x
	p.offset_bottom = off.y + sz.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.3)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", fc)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	add_child(p)
	pads[id] = p
	return p


func setup(main_node) -> void:
	main = main_node
	layer = 10
	video = main.director != null
	if video:
		_build_video()
	else:
		_build_play()
	_build_common()


func _build_play() -> void:
	lbl_speed = _label("0", 54)
	lbl_speed.position = Vector2(24, 6)
	add_child(lbl_speed)
	var kmh := _label("km/h", 18)
	kmh.position = Vector2(150, 36)
	add_child(kmh)

	minimap = MiniMap.new()
	minimap.main = main
	minimap.position = Vector2(24, 80)
	minimap.size = Vector2(170, 170)
	minimap.custom_minimum_size = Vector2(170, 170)
	add_child(minimap)

	lbl_score = _label("0", 44)
	lbl_score.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.offset_top = 4
	add_child(lbl_score)
	lbl_stars = _label("", 34)
	lbl_stars.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_stars.offset_top = 56
	lbl_stars.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	add_child(lbl_stars)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	vb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb: Array = _bar(22, Color(0.25, 0.85, 0.4))
	hp_bar = hb[0]
	hp_fill = hb[1]
	vb.add_child(hp_bar)
	nitro_bar = _bar(12, Color(0.3, 0.6, 1.0))[0]
	vb.add_child(nitro_bar)
	lbl_info = _label("", 20)
	lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(lbl_info)
	add_child(vb)

	lbl_hint = _label("Arrows to steer, GAS and BRAKE on the right. Drift to fill NITRO.\nSmash buildings, hit red barrels and gas stations. Don't get boxed in by police!", 20)
	lbl_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.offset_top = -330
	add_child(lbl_hint)
	get_tree().create_timer(10.0).timeout.connect(func(): lbl_hint.visible = false)

	var dark := Color(0.05, 0.07, 0.1, 0.55)
	for a in [["left", -1.0, 24.0], ["right", 1.0, 196.0]]:
		var p := _pad(str(a[0]), "", Vector2(0, 1), Vector2(float(a[2]), -170.0), Vector2(150, 146), dark, Color.WHITE)
		var arrow := Arrow.new()
		arrow.dir = float(a[1])
		arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.add_child(arrow)
	_pad("brake", "BRAKE", Vector2(1, 1), Vector2(-330, -150), Vector2(146, 130), dark, Color.WHITE)
	_pad("gas", "GAS", Vector2(1, 1), Vector2(-170, -150), Vector2(146, 130), dark, Color.WHITE)
	_pad("hb", "DRIFT", Vector2(1, 1), Vector2(-330, -284), Vector2(146, 120), dark, Color.WHITE)
	_pad("nitro", "NITRO", Vector2(1, 1), Vector2(-170, -284), Vector2(146, 120), Color(0.15, 0.4, 0.95, 0.8), Color.WHITE)


# Video overlay. Text stays in the top third: YouTube Shorts covers the bottom
# fifth and the right edge with its own buttons.
func _build_video() -> void:
	var v: bool = main.vertical
	var vs := get_viewport().get_visible_rect().size
	lbl_title = _label(main.director.title, 64 if v else 40, 14 if v else 10)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.2))
	_at(lbl_title, 0.045 if v else 0.025, 90.0 if v else 56.0)
	lbl_title.modulate.a = 0.0
	add_child(lbl_title)

	lbl_stats = _label("", 44 if v else 28, 10 if v else 7)
	_at(lbl_stats, 0.105 if v else 0.115, 60.0 if v else 40.0)
	add_child(lbl_stats)

	stars = Stars.new()
	stars.r = 26.0 if v else 17.0
	_at(stars, 0.14 if v else 0.18, 70.0 if v else 44.0)
	add_child(stars)

	var hb: Array = _bar(16 if v else 12, Color(0.25, 0.85, 0.4))
	hp_bar = hb[0]
	hp_fill = hb[1]
	hp_bar.anchor_left = 0.5
	hp_bar.anchor_right = 0.5
	hp_bar.anchor_top = 0.172 if v else 0.245
	hp_bar.anchor_bottom = hp_bar.anchor_top
	hp_bar.offset_left = -200.0 if v else -140.0
	hp_bar.offset_right = -hp_bar.offset_left
	add_child(hp_bar)

	minimap = MiniMap.new()
	minimap.main = main
	var ms := 220.0 if v else 160.0
	minimap.position = Vector2(24, vs.y * 0.19) if v else Vector2(24, 24)
	minimap.size = Vector2(ms, ms)
	minimap.custom_minimum_size = Vector2(ms, ms)
	add_child(minimap)

	# retention extras: thin progress strip on top, speed lines, vignette, caption line
	progress_bg = ColorRect.new()
	progress_bg.color = Color(0, 0, 0, 0.35)
	progress_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	progress_bg.offset_bottom = 10.0 if v else 6.0
	progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress_bg)
	progress = ColorRect.new()
	progress.color = Color(1.0, 0.82, 0.2)
	progress.set_anchors_preset(Control.PRESET_TOP_LEFT)
	progress.offset_bottom = progress_bg.offset_bottom
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress)

	speed_lines = SpeedLines.new()
	speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(speed_lines)

	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0))
	vg.set_color(1, Color(0, 0, 0, 0.6))
	vg.add_point(0.55, Color(0, 0, 0, 0.0))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 0.5)
	vt.width = 256
	vt.height = 256
	var vr := TextureRect.new()
	vr.texture = vt
	vr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vr.stretch_mode = TextureRect.STRETCH_SCALE
	vr.set_anchors_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vr)

	lbl_caption = _label("", 84 if v else 52, 18 if v else 12)
	lbl_caption.add_theme_color_override("font_color", Color.WHITE)
	lbl_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_at(lbl_caption, 0.52 if v else 0.62, 260.0 if v else 130.0)
	lbl_caption.pivot_offset = Vector2((vs.x - 60.0) * 0.5, (260.0 if v else 130.0) * 0.5)
	lbl_caption.modulate.a = 0.0
	add_child(lbl_caption)

	# the hook: big title in the middle for the first seconds, then it moves up
	lbl_hook = _label(main.director.title, 112 if v else 72, 22 if v else 16)
	lbl_hook.add_theme_color_override("font_color", Color(1.0, 0.86, 0.2))
	lbl_hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_at(lbl_hook, 0.26 if v else 0.3, 300.0 if v else 180.0)
	lbl_hook.pivot_offset = Vector2((vs.x - 60.0) * 0.5, (300.0 if v else 180.0) * 0.5)
	lbl_hook.scale = Vector2.ONE * 0.5
	add_child(lbl_hook)
	var tw := create_tween()
	tw.tween_property(lbl_hook, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(lbl_hook, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(lbl_title, "modulate:a", 1.0, 0.3)


func _build_common() -> void:
	var v: bool = video and main.vertical
	lbl_banner = _label("", 64 if v else (44 if video else 40), 12 if video else 0)
	if video:
		_at(lbl_banner, 0.24 if v else 0.33, 90.0 if v else 60.0)
	else:
		lbl_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
		lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_banner.offset_top = 112
	lbl_banner.modulate.a = 0.0
	add_child(lbl_banner)

	# BUSTED meter: shows up only while you are boxed in
	busted_box = VBoxContainer.new()
	busted_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busted_box.anchor_left = 0.5
	busted_box.anchor_right = 0.5
	busted_box.anchor_top = (0.195 if v else 0.27) if video else 0.0
	busted_box.anchor_bottom = busted_box.anchor_top
	var bw := 260.0 if v else 190.0
	busted_box.offset_left = -bw
	busted_box.offset_right = bw
	busted_box.offset_top = 0.0 if video else 170.0
	var lb := _label("BUSTED", 40 if v else 28, 8)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	busted_box.add_child(lb)
	var bb: Array = _bar(22 if v else 16, Color(0.95, 0.15, 0.15))
	busted_bar = bb[0]
	busted_fill = bb[1]
	busted_bar.value = 0
	busted_box.add_child(busted_bar)
	busted_box.visible = false
	add_child(busted_box)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 0.95, 0.85, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt_rect)

	over_panel = ColorRect.new()
	over_panel.color = Color(0, 0, 0, 0.55 if video else 0.65)
	over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_panel.visible = false
	lbl_over = _label("", 60 if v else 40, 12 if video else 0)
	lbl_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	over_panel.add_child(lbl_over)
	add_child(over_panel)


func _pad_at(pos: Vector2) -> String:
	for id in pads:
		var p := pads[id] as Control
		if p.get_global_rect().grow(12.0).has_point(pos):
			return id
	return ""


func is_down(id: String) -> bool:
	for v in touch_map.values():
		if v == id:
			return true
	return false


func _input(event: InputEvent) -> void:
	if video:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if main.game_over:
				if over_t > 0.9:
					main.restart()
				return
			touch_map[t.index] = _pad_at(t.position)
		else:
			touch_map.erase(t.index)
	elif event is InputEventScreenDrag:
		# sliding a thumb from one arrow to the other switches direction
		var d := event as InputEventScreenDrag
		touch_map[d.index] = _pad_at(d.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R:
			main.restart()


func _process(delta: float) -> void:
	if main.game_over:
		over_t += delta
	hurt_rect.color.a = move_toward(hurt_rect.color.a, 0.0, delta * 1.4)
	flash_rect.color.a = move_toward(flash_rect.color.a, 0.0, delta * 2.2)
	if video:
		return
	var gas := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or is_down("gas"):
		gas += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) or is_down("brake"):
		gas -= 1.0
	var st := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) or is_down("left"):
		st += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) or is_down("right"):
		st -= 1.0
	in_gas = gas
	in_steer = st
	in_nitro = Input.is_physical_key_pressed(KEY_N) or Input.is_physical_key_pressed(KEY_Q) or is_down("nitro")
	in_hb = 1.0 if (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_E) or is_down("hb")) else 0.0
	for id in pads:
		(pads[id] as Control).modulate.a = 1.0 if is_down(id) else 0.72


func update_hud() -> void:
	var p: Car = main.player
	hp_bar.value = maxf(p.hp, 0.0)
	var f := clampf(p.hp / p.max_hp, 0.0, 1.0)
	hp_fill.bg_color = Color(0.9, 0.25, 0.2).lerp(Color(0.25, 0.85, 0.4), f)
	if video:
		lbl_stats.text = main.director.overlay_line()
		if stars.level != main.level:
			stars.level = main.level
			stars.queue_redraw()
		progress.offset_right = get_viewport().get_visible_rect().size.x * clampf(main.clock / main.director.duration, 0.0, 1.0)
		var kmh := absf(p.fwd_speed) * 3.6
		speed_lines.intensity = clampf((kmh - 90.0) / 70.0, 0.0, 1.0) * (1.0 if p.airtime < 0.2 else 0.5) + (0.4 if p.nitro_active else 0.0)
		speed_lines.queue_redraw()
	else:
		lbl_speed.text = str(int(absf(p.fwd_speed) * 3.6))
		lbl_score.text = str(main.score)
		var s := ""
		for i in 5:
			s += "*" if i < main.level else "-"
		lbl_stars.text = s + ("   HELI" if main.heli != null and main.heli.visible else "")
		lbl_info.text = "Police wrecked %d   Cubes %d" % [main.wrecked, main.cubes]
		nitro_bar.value = p.nitro
	busted_box.visible = main.busted > 0.01 and not main.game_over
	if busted_box.visible:
		busted_bar.value = main.busted * 100.0
		var flash := fmod(main.clock * 4.0, 1.0) < 0.5
		busted_fill.bg_color = Color(0.95, 0.15, 0.15) if flash else Color(0.2, 0.4, 1.0)


func banner(text: String) -> void:
	lbl_banner.text = text
	if banner_tw != null:
		banner_tw.kill()
	lbl_banner.modulate.a = 1.0
	banner_tw = create_tween()
	banner_tw.tween_interval(1.1)
	banner_tw.tween_property(lbl_banner, "modulate:a", 0.0, 0.6)


# Big story line in the middle of the screen (video runs only).
func caption(text: String, secs: float = 1.7) -> void:
	if lbl_caption == null:
		return
	lbl_caption.text = text
	if cap_tw != null:
		cap_tw.kill()
	lbl_caption.modulate.a = 1.0
	lbl_caption.scale = Vector2.ONE * 0.6
	cap_tw = create_tween()
	cap_tw.tween_property(lbl_caption, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cap_tw.tween_interval(secs)
	cap_tw.tween_property(lbl_caption, "modulate:a", 0.0, 0.25)


func flash(a: float) -> void:
	flash_rect.color.a = clampf(maxf(flash_rect.color.a, a), 0.0, 0.5)


func hurt_flash(a: float) -> void:
	hurt_rect.color.a = clampf(hurt_rect.color.a + a, 0.0, 0.28)


func show_over(text: String) -> void:
	lbl_over.text = text
	over_panel.visible = true
	over_t = 0.0
