class_name RaceHud
extends Control
# The race overlay: a progress strip with the car and the train on it (so you always know who
# is ahead and by how much), the countdown and the commentary in big letters, and the result
# card at the end. It is drawn even when the video is "clean" (that mode hides the game's own
# read-outs), because here they ARE the video: without them nobody sees who won.

const CAR_COL := Color(1.0, 0.3, 0.22)
const TRAIN_COL := Color(0.35, 0.65, 1.0)

var vertical := true
var car_f := 0.0
var train_f := 0.0
var gap_m := 0.0
var leader := ""
var frozen := false          # the result card is up
var active := false          # the race has started (the strip shows the gap)
var big: Label
var big_tw: Tween
var gap_lbl: Label
var card: PanelContainer
var card_title: Label
var card_lines: Label


func _label(size: int, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func setup(is_vertical: bool) -> void:
	vertical = is_vertical
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# commentary and countdown
	big = _label(150 if vertical else 96, 18 if vertical else 12)
	big.anchor_left = 0.0
	big.anchor_right = 1.0
	big.anchor_top = 0.30 if vertical else 0.28
	big.anchor_bottom = big.anchor_top
	big.offset_bottom = 220.0 if vertical else 140.0
	big.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big.modulate.a = 0.0
	add_child(big)
	# the gap under the strip
	gap_lbl = _label(46 if vertical else 28, 9 if vertical else 6)
	gap_lbl.anchor_left = 0.0
	gap_lbl.anchor_right = 1.0
	gap_lbl.anchor_top = 0.175 if vertical else 0.19
	gap_lbl.anchor_bottom = gap_lbl.anchor_top
	gap_lbl.offset_bottom = 64.0 if vertical else 40.0
	add_child(gap_lbl)
	# result card
	card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.82)
	sb.set_corner_radius_all(26)
	sb.set_content_margin_all(34)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.42 if vertical else 0.3
	card.anchor_bottom = card.anchor_top
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card_title = _label(104 if vertical else 64, 14 if vertical else 9)
	card_lines = _label(50 if vertical else 30, 8 if vertical else 5)
	vb.add_child(card_title)
	vb.add_child(card_lines)
	card.add_child(vb)
	add_child(card)


func say(text: String, secs: float = 1.5, col: Color = Color(1, 1, 1)) -> void:
	big.text = text
	big.add_theme_color_override("font_color", col)
	if big_tw != null:
		big_tw.kill()
	big.modulate.a = 1.0
	big.pivot_offset = Vector2(size.x * 0.5, big.size.y * 0.5)
	big.scale = Vector2.ONE * 0.55
	# long phrases get a smaller font so they fit on two lines
	big.add_theme_font_size_override("font_size", int((150 if vertical else 96) * (0.62 if text.length() > 14 else 1.0)))
	big_tw = create_tween()
	big_tw.set_ignore_time_scale(true)      # slow motion must not make the words hang around
	big_tw.tween_property(big, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	big_tw.tween_interval(secs)
	big_tw.tween_property(big, "modulate:a", 0.0, 0.3)


func update(cf: float, tf: float, gap: float, lead: String, running: bool) -> void:
	if frozen:
		return          # the race is over: the strip stays as it finished
	car_f = cf
	train_f = tf
	gap_m = gap
	leader = lead
	active = running
	if running and gap_m >= 3.0:
		gap_lbl.text = "%s AHEAD BY %d m" % [leader.to_upper(), int(round(gap_m))]
		gap_lbl.add_theme_color_override("font_color", CAR_COL.lightened(0.25) if leader == "car" else TRAIN_COL.lightened(0.2))
	else:
		gap_lbl.text = "SIDE BY SIDE" if running else ""
		gap_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	queue_redraw()


func show_result(title: String, lines: Array, col: Color) -> void:
	# the card replaces any commentary still on screen
	if big_tw != null:
		big_tw.kill()
	big.modulate.a = 0.0
	gap_lbl.text = ""
	frozen = true
	card_title.text = title
	card_title.add_theme_color_override("font_color", col)
	card_lines.text = "\n".join(PackedStringArray(lines))
	card.visible = true
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * 0.8
	card.pivot_offset = card.size * 0.5
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(0.7)
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.35)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var x0 := w * (0.1 if vertical else 0.22)
	var x1 := w * (0.9 if vertical else 0.78)
	var y := h * (0.145 if vertical else 0.145)
	var th := 14.0 if vertical else 9.0
	# the strip: dark bar, start line, chequered finish
	draw_rect(Rect2(x0 - 4.0, y - th * 0.5 - 4.0, x1 - x0 + 8.0, th + 8.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x0, y - th * 0.5, x1 - x0, th), Color(0.28, 0.3, 0.36))
	var lead_x := x0 + (x1 - x0) * maxf(car_f, train_f)
	draw_rect(Rect2(x0, y - th * 0.5, lead_x - x0, th), Color(1, 1, 1, 0.18))
	var sq := th * 0.5
	for i in 4:
		for j in 2:
			var c := Color.WHITE if (i + j) % 2 == 0 else Color.BLACK
			draw_rect(Rect2(x1 + 4.0 + float(i) * sq, y - th * 0.5 + float(j) * sq, sq, sq), c)
	var r := 26.0 if vertical else 17.0
	var font := ThemeDB.fallback_font
	var fs := 30 if vertical else 20
	# car above the bar, train below, so they never cover each other
	var cx := x0 + (x1 - x0) * car_f
	var tx := x0 + (x1 - x0) * train_f
	draw_circle(Vector2(cx, y - r * 0.9), r, CAR_COL)
	draw_arc(Vector2(cx, y - r * 0.9), r, 0.0, TAU, 28, Color.WHITE, 3.0)
	draw_string(font, Vector2(cx - fs * 0.32, y - r * 0.9 + fs * 0.36), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_circle(Vector2(tx, y + r * 0.9), r, TRAIN_COL)
	draw_arc(Vector2(tx, y + r * 0.9), r, 0.0, TAU, 28, Color.WHITE, 3.0)
	draw_string(font, Vector2(tx - fs * 0.3, y + r * 0.9 + fs * 0.36), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
