class_name Hud
extends CanvasLayer
# HUD, minimap and multi-touch pads.

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


var main
var in_gas := 0.0
var in_steer := 0.0
var in_hb := 0.0
var in_nitro := false
var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy: Control
var nitro_bar: ProgressBar
var touch_map := {}
var pads := {}
var pad_labels := {}
var lbl_speed: Label
var lbl_score: Label
var lbl_stars: Label
var lbl_info: Label
var lbl_banner: Label
var lbl_hint: Label
var lbl_over: Label
var hp_bar: ProgressBar
var hp_fill: StyleBoxFlat
var over_panel: ColorRect
var hurt_rect: ColorRect
var minimap: MiniMap
var banner_tw: Tween
var over_t := 0.0


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _pad(id: String, text: String, anchor: Vector2, off: Vector2, sz: Vector2, fill: Color, fc: Color) -> void:
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
	pad_labels[id] = l


func setup(main_node) -> void:
	main = main_node
	layer = 10

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
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(250, 22)
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.25, 0.85, 0.4)
	hp_fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_bar.add_theme_stylebox_override("background", bg)
	vb.add_child(hp_bar)
	nitro_bar = ProgressBar.new()
	nitro_bar.custom_minimum_size = Vector2(250, 12)
	nitro_bar.max_value = 100
	nitro_bar.show_percentage = false
	nitro_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nf := StyleBoxFlat.new()
	nf.bg_color = Color(0.3, 0.6, 1.0)
	nf.set_corner_radius_all(5)
	nitro_bar.add_theme_stylebox_override("fill", nf)
	nitro_bar.add_theme_stylebox_override("background", bg)
	vb.add_child(nitro_bar)
	lbl_info = _label("", 20)
	lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(lbl_info)
	add_child(vb)

	lbl_banner = _label("", 40)
	lbl_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_banner.offset_top = 112
	lbl_banner.modulate.a = 0.0
	add_child(lbl_banner)

	lbl_hint = _label("Drag on the left side to steer. Smash buildings, drift to fill NITRO, hit red barrels and gas stations.", 20)
	lbl_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.offset_top = -330
	add_child(lbl_hint)
	get_tree().create_timer(10.0).timeout.connect(func(): lbl_hint.visible = false)

	var dark := Color(0.05, 0.07, 0.1, 0.55)
	_pad("brake", "BRAKE", Vector2(1, 1), Vector2(-330, -150), Vector2(146, 130), dark, Color.WHITE)
	_pad("gas", "GAS", Vector2(1, 1), Vector2(-170, -150), Vector2(146, 130), dark, Color.WHITE)
	_pad("hb", "DRIFT", Vector2(1, 1), Vector2(-330, -284), Vector2(146, 120), dark, Color.WHITE)
	_pad("nitro", "NITRO", Vector2(1, 1), Vector2(-170, -284), Vector2(146, 120), Color(0.15, 0.4, 0.95, 0.8), Color.WHITE)
	_pad("blast", "BLAST", Vector2(1, 1), Vector2(-330, -398), Vector2(306, 100), Color(1.0, 0.42, 0.12, 0.85), Color(0.1, 0.05, 0.02))
	joy = Control.new()
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy.draw.connect(_draw_joy)
	add_child(joy)

	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt_rect)

	over_panel = ColorRect.new()
	over_panel.color = Color(0, 0, 0, 0.65)
	over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_panel.visible = false
	lbl_over = _label("", 40)
	lbl_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	over_panel.add_child(lbl_over)
	add_child(over_panel)


func _pad_at(pos: Vector2) -> String:
	for id in pads:
		var p := pads[id] as Control
		if p.get_global_rect().grow(18.0).has_point(pos):
			return id
	return ""


func is_down(id: String) -> bool:
	for v in touch_map.values():
		if v == id:
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if main.game_over:
				if over_t > 0.9:
					main.restart()
				return
			var id := _pad_at(t.position)
			var vs := get_viewport().get_visible_rect().size
			if id == "" and joy_index < 0 and t.position.x < vs.x * 0.45 and t.position.y > vs.y * 0.35:
				joy_index = t.index
				joy_origin = t.position
				joy_pos = t.position
				joy.queue_redraw()
				return
			touch_map[t.index] = id
			if id == "blast":
				main.try_blast()
		else:
			if t.index == joy_index:
				joy_index = -1
				joy.queue_redraw()
			touch_map.erase(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == joy_index:
			joy_pos = d.position
			joy.queue_redraw()
			return
		touch_map[d.index] = _pad_at(d.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_SPACE:
				main.try_blast()
			elif k.keycode == KEY_R:
				main.restart()


func _process(delta: float) -> void:
	var gas := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or is_down("gas"):
		gas += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) or is_down("brake"):
		gas -= 1.0
	var st := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		st += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		st -= 1.0
	if joy_index >= 0:
		var dx := joy_pos.x - joy_origin.x
		var a := clampf(dx / 85.0, -1.0, 1.0)
		st = -signf(a) * pow(absf(a), 1.3)
	in_gas = gas
	in_steer = st
	in_nitro = Input.is_physical_key_pressed(KEY_N) or Input.is_physical_key_pressed(KEY_Q) or is_down("nitro")
	in_hb = 1.0 if (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_E) or is_down("hb")) else 0.0
	for id in pads:
		(pads[id] as Control).modulate.a = 1.0 if is_down(id) else 0.72
	if main.game_over:
		over_t += delta
	hurt_rect.color.a = move_toward(hurt_rect.color.a, 0.0, delta * 1.4)


func update_hud() -> void:
	var p: Car = main.player
	lbl_speed.text = str(int(absf(p.fwd_speed) * 3.6))
	lbl_score.text = str(main.score)
	var s := ""
	for i in 5:
		s += "*" if i < main.level else "-"
	lbl_stars.text = s + ("   HELI" if main.heli != null and main.heli.visible else "")
	hp_bar.value = maxf(p.hp, 0.0)
	var f := clampf(p.hp / p.max_hp, 0.0, 1.0)
	hp_fill.bg_color = Color(0.9, 0.25, 0.2).lerp(Color(0.25, 0.85, 0.4), f)
	lbl_info.text = "Police wrecked %d   Cubes %d" % [main.wrecked, main.cubes]
	nitro_bar.value = p.nitro
	var cd: float = main.blast_cd
	(pad_labels["blast"] as Label).text = "BLAST" if cd <= 0.0 else "%.1f" % cd


func _draw_joy() -> void:
	var vs := get_viewport().get_visible_rect().size
	if joy_index >= 0:
		joy.draw_circle(joy_origin, 90.0, Color(1, 1, 1, 0.12))
		joy.draw_arc(joy_origin, 90.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		var k := joy_origin + Vector2(clampf(joy_pos.x - joy_origin.x, -90.0, 90.0), 0.0)
		joy.draw_circle(k, 38.0, Color(1, 1, 1, 0.55))
	else:
		var c := Vector2(170.0, vs.y - 140.0)
		joy.draw_arc(c, 90.0, 0.0, TAU, 40, Color(1, 1, 1, 0.22), 3.0)
		joy.draw_circle(c, 34.0, Color(1, 1, 1, 0.2))
		joy.draw_string(ThemeDB.fallback_font, c + Vector2(-46, 8), "< STEER >", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.55))


func banner(text: String) -> void:
	lbl_banner.text = text
	if banner_tw != null:
		banner_tw.kill()
	lbl_banner.modulate.a = 1.0
	banner_tw = create_tween()
	banner_tw.tween_interval(1.1)
	banner_tw.tween_property(lbl_banner, "modulate:a", 0.0, 0.6)


func hurt_flash(a: float) -> void:
	hurt_rect.color.a = clampf(hurt_rect.color.a + a, 0.0, 0.28)


func show_over(text: String) -> void:
	lbl_over.text = text
	over_panel.visible = true
	over_t = 0.0
