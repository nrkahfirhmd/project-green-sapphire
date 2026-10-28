extends RefCounted
## Small Controls for building the handoff's screens out of containers:
## letter-spaced text, a framed panel, and a free-drawn shape. Each reports a
## minimum size so VBox/HBox containers can lay them out.
##
##   const W := preload("res://scripts/ui/ui_widgets.gd")
##   box.add_child(W.Text.new("PAUSED", 48))

const UI := preload("res://scripts/ui/ui.gd")


## One line of uppercase Plex Mono, letter-spaced.
class Text extends Control:
	var text := ""
	var px := 24
	var weight := 600
	var em := 0.2
	var color := UI.CORE

	func _init(t := "", size_px := 24, w := 600, spacing := 0.2, col := UI.CORE) -> void:
		text = t
		px = size_px
		weight = w
		em = spacing
		color = col
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fit()

	func set_text(t: String) -> void:
		text = t
		_fit()
		queue_redraw()

	func _fit() -> void:
		custom_minimum_size = Vector2(UI.text_width(text, px, weight, em), UI.text_height(px, weight))

	func _draw() -> void:
		UI.text(self, Vector2(size.x * 0.5, (size.y - UI.text_height(px, weight)) * 0.5), text, px, color, weight, em, 0)


## Anything drawn by a callable taking (control, size). For ornaments,
## dividers and emblems.
class Shape extends Control:
	var painter: Callable

	func _init(min_size: Vector2, p: Callable) -> void:
		custom_minimum_size = min_size
		painter = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		painter.call(self, size)


## A framed panel (Moss 90 %, Core outline, corner ticks) around its single
## child, with padding.
class Frame extends MarginContainer:
	var fill := Color(UI.MOSS, 0.9)

	func _init(pad_v := 48, pad_h := 64) -> void:
		add_theme_constant_override("margin_top", pad_v)
		add_theme_constant_override("margin_bottom", pad_v)
		add_theme_constant_override("margin_left", pad_h)
		add_theme_constant_override("margin_right", pad_h)

	func _draw() -> void:
		UI.frame(self, Rect2(Vector2.ZERO, size), UI.CORE, fill)


static func vbox(gap: int, align := BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	b.alignment = align
	return b


static func hbox(gap: int, align := BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	b.alignment = align
	return b


## A full-screen control that places `child` centred horizontally, `top`
## units below the top of the safe area.
static func top_centred(child: Control, top: float) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_TOP_WIDE)
	c.offset_top = top
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c
