extends BaseButton
## The design's menu button: a square, 2-unit Core frame on a 60 % Moss fill.
##   selected (has focus): a 15 % Core fill and a ▸ marker that slides in
##   pressed: solid Core fill, Moss label, scaled to 0.97
##   disabled: dashed 30 % outline and label
## Selection follows keyboard/controller focus; the primary button on a
## screen grabs focus so one is always marked. A BaseButton, so touch, mouse
## and focus all work without extra code.

const UI := preload("res://scripts/ui/ui.gd")

var label := ""
var font_size := 32
var segment := false            # segmented-control half: active = solid fill
var active := false             # for segments
var _sel := 0.0                 # 0..1 selected-marker progress, tweened
var _sel_tw: Tween
var _press_tw: Tween


func _init(text := "", size_px := Vector2(400, 100), px := 32) -> void:
	label = text
	font_size = px
	custom_minimum_size = size_px
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)
	focus_entered.connect(_select.bind(true))
	focus_exited.connect(_select.bind(false))
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))
	mouse_entered.connect(func(): if not disabled: grab_focus())


func _select(on: bool) -> void:
	if _sel_tw:
		_sel_tw.kill()
	_sel_tw = create_tween()
	_sel_tw.tween_property(self, "_sel", 1.0 if on else 0.0, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_sel_tw.tween_callback(queue_redraw)


func _press(down: bool) -> void:
	if down:
		Haptics.play("tap")
	if _press_tw:
		_press_tw.kill()
	_press_tw = create_tween()
	_press_tw.tween_property(self, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.06 if down else 0.10).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _process(_d: float) -> void:
	if _sel_tw and _sel_tw.is_running():
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c := UI.CORE
	if disabled:
		UI.dashed_rect(self, r, Color(c, 0.3))
		UI.text(self, r.get_center() - Vector2(0, UI.text_height(font_size) * 0.5), label, font_size, Color(c, 0.3), 600, 0.2, 0)
		return
	var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	var solid := down or (segment and active)
	if solid:
		draw_rect(r, c)
	else:
		draw_rect(r, Color(UI.MOSS, 0.6))
		if _sel > 0.0:
			draw_rect(r, Color(c, 0.15 * _sel))
	draw_rect(r, c if (solid or _sel > 0.5) else Color(c, 0.6), false, UI.STROKE)
	var txt := label
	var col := UI.MOSS if solid else c
	var y := r.get_center().y - UI.text_height(font_size) * 0.5
	if _sel > 0.0 and not segment:
		# a ▸ marker slides in from the left; drawn, so it never depends on a glyph
		var mk := font_size * 0.42
		var gap := font_size * 0.6
		var w := mk + gap + UI.text_width(txt, font_size, 600, 0.2)
		var x0 := r.get_center().x - w * 0.5 + (1.0 - _sel) * -8.0
		var cy := r.get_center().y
		draw_colored_polygon(PackedVector2Array([Vector2(x0, cy - mk * 0.6), Vector2(x0 + mk, cy), Vector2(x0, cy + mk * 0.6)]), Color(col, _sel))
		UI.text(self, Vector2(x0 + mk + gap, y), txt, font_size, col, 600, 0.2)
	else:
		UI.text(self, Vector2(r.get_center().x, y), txt, font_size, col, 600, 0.2, 0)
