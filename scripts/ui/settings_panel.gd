extends Control
## Settings, shared by Home and the pause sheet: a framed two-column panel.
##   sound (left)     VOLUME, MUSIC, SFX: 10-block meters
##   feel (right)     SCREEN SHAKE, REDUCED MOTION, HAPTICS, BUTTON SIZE
## Values live in the Game autoload and persist to user://settings.cfg.

signal closed

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")
const ROW_W := 760.0

var _first: Control
var _shake: Control


func _ready() -> void:
	# already in the tree here, so the offsets must be reset too or it stays 0x0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # nothing behind reacts while open

	var panel := W.Frame.new(40, 48)
	var col := W.vbox(24)
	panel.add_child(col)
	col.add_child(W.Text.new("SETTINGS", 48, 600, 0.25))
	col.add_child(W.Shape.new(Vector2(0, 2), func(c: Control, s: Vector2): c.draw_rect(Rect2(Vector2.ZERO, s), Color(UI.CORE, 0.4))))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)

	_first = Meter.new("VOLUME", "volume")
	_shake = Meter.new("SCREEN SHAKE", "shake")
	var back := Btn.new("BACK", Vector2(300, 100), 28)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): closed.emit())
	for row in [
		_first, _shake,
		Meter.new("MUSIC", "music_volume"), _choice("REDUCED MOTION", "reduced_motion", {"ON": true, "OFF": false}),
		Meter.new("SFX", "sfx_volume"), _choice("HAPTICS", "haptic_enabled", {"ON": true, "OFF": false}),
		back, _choice("BUTTON SIZE", "button_size", {"S": 0.9, "M": 1.0, "L": 1.2}),
	]:
		grid.add_child(row)

	add_child(W.top_centred(panel, 90))


func open() -> void:
	show()
	_first.grab_focus()


## A label and a segmented control whose buttons set `key` to their value.
func _choice(title: String, key: String, options: Dictionary) -> Control:
	var row := W.hbox(0)
	row.custom_minimum_size = Vector2(ROW_W, 100)
	var label := MarginContainer.new()
	label.add_theme_constant_override("margin_left", 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := W.Text.new(title, 28, 600, 0.2)
	text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_child(text)
	row.add_child(label)
	var buttons: Array = []
	for name in options:
		var b := Btn.new(name, Vector2(450.0 / options.size() if options.size() > 2 else 150.0, 100), 28)
		b.segment = true
		b.active = Game.get(key) == options[name]
		row.add_child(b)
		buttons.append(b)
		b.pressed.connect(func():
			for other in buttons:
				other.active = other == b
				other.queue_redraw()
			_pick(key, options[name]))
	return row


func _pick(key: String, value: Variant) -> void:
	Game.change(key, value)
	Haptics.play("toggle")       # felt only when switching on: the proof it works
	Sfx.play("toggle")
	if key == "reduced_motion":
		Game.change("shake", 0.0 if value else 1.0)
		_shake.queue_redraw()


## A named setting as ten blocks and the value. Tap or drag across the blocks to
## set it; left/right when selected.
class Meter extends Control:
	const BLOCK := Vector2(24, 40)
	const GAP := 6.0
	const WIDTH := BLOCK.x * 10 + GAP * 9

	var title := ""
	var key := ""

	func _init(t := "", k := "") -> void:
		title = t
		key = k
		custom_minimum_size = Vector2(760, 100)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _blocks_x() -> float:
		return size.x - 24.0 - 80.0 - WIDTH

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_set_value(ceilf(clampf((e.position.x - _blocks_x()) / WIDTH, 0.0, 1.0) * 10.0) / 10.0)
			accept_event()
		elif e.is_action_pressed("ui_left"):
			_set_value(float(Game.get(key)) - 0.1)
			accept_event()
		elif e.is_action_pressed("ui_right"):
			_set_value(float(Game.get(key)) + 0.1)
			accept_event()

	func _set_value(v: float) -> void:
		v = snappedf(clampf(v, 0.0, 1.0), 0.1)
		if v != Game.get(key):
			Game.change(key, v)
			Sfx.play("toggle")     # so a level can be judged while it's being set
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sel := has_focus()
		if sel:
			draw_rect(r, UI.CORE, false, UI.STROKE)
		var y := (size.y - UI.text_height(28)) * 0.5
		var x := 24.0
		if sel:
			var mk := 28 * 0.42
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y * 0.5 - mk * 0.6), Vector2(x + mk, size.y * 0.5), Vector2(x, size.y * 0.5 + mk * 0.6)]), UI.CORE)
			x += mk + 16.0
		UI.text(self, Vector2(x, y), title, 28, UI.CORE, 600, 0.2)
		var n := roundi(float(Game.get(key)) * 10.0)
		var bx := _blocks_x()
		for i in 10:
			var b := Rect2(Vector2(bx + i * (BLOCK.x + GAP), (size.y - BLOCK.y) * 0.5), BLOCK)
			if i < n:
				draw_rect(b, UI.CORE)
			else:
				draw_rect(b, Color(UI.CORE, 0.45), false, UI.STROKE)
		UI.text(self, Vector2(size.x - 24.0, y), str(n * 10), 28, UI.CORE, 600, 0.0, 1)
