extends Control
## Settings, shared by Home and the pause sheet: a framed 960-wide panel with
## a 10-block VOLUME meter, a HAPTICS ON/OFF segmented control, and BACK.
## Values live in the Game autoload and persist to user://settings.cfg.

signal closed

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")

var _back: BaseButton
var _volume: Control
var _on: BaseButton
var _off: BaseButton


func _ready() -> void:
	# already in the tree here, so the offsets must be reset too or it stays 0x0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # nothing behind reacts while open

	var panel := W.Frame.new(48, 64)
	panel.custom_minimum_size.x = 960
	var col := W.vbox(32)
	panel.add_child(col)
	col.add_child(W.Text.new("SETTINGS", 48, 600, 0.25))
	col.add_child(W.Shape.new(Vector2(0, 2), func(c: Control, s: Vector2): c.draw_rect(Rect2(Vector2.ZERO, s), Color(UI.CORE, 0.4))))

	_volume = VolumeRow.new()
	col.add_child(_volume)

	var hap := W.hbox(0)
	hap.custom_minimum_size.y = 100
	hap.add_child(_left(W.Text.new("HAPTICS", 28, 600, 0.2)))
	_on = Btn.new("ON", Vector2(150, 100), 28)
	_off = Btn.new("OFF", Vector2(150, 100), 28)
	for b in [_on, _off]:
		b.segment = true
		hap.add_child(b)
	_on.pressed.connect(_set_haptic.bind(true))
	_off.pressed.connect(_set_haptic.bind(false))
	col.add_child(hap)
	_set_haptic(Game.haptic_enabled, false)

	_back = Btn.new("BACK", Vector2(300, 100), 28)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(func(): closed.emit())
	col.add_child(_back)

	add_child(W.top_centred(panel, 120))


func open() -> void:
	show()
	_volume.grab_focus()


func _set_haptic(on: bool, save := true) -> void:
	_on.active = on
	_off.active = not on
	_on.queue_redraw()
	_off.queue_redraw()
	if save:
		Game.set_haptic(on)
		Haptics.play("toggle")       # felt only when switching on: the proof it works


## A label left-aligned in a row that otherwise centres its text.
func _left(t: Control) -> Control:
	var c := MarginContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.add_child(t)
	return c


## VOLUME, ten blocks and the value. Tap or drag across the blocks to set it;
## left/right when selected.
class VolumeRow extends Control:
	const BLOCK := Vector2(32, 40)
	const GAP := 8.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 100)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _blocks_x() -> float:
		return size.x - 24.0 - 80.0 - (BLOCK.x * 10 + GAP * 9)

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var f := clampf((e.position.x - _blocks_x()) / (BLOCK.x * 10 + GAP * 9), 0.0, 1.0)
			_set_volume(ceilf(f * 10.0) / 10.0)
			accept_event()
		elif e.is_action_pressed("ui_left"):
			_set_volume(Game.volume - 0.1)
			accept_event()
		elif e.is_action_pressed("ui_right"):
			_set_volume(Game.volume + 0.1)
			accept_event()

	func _set_volume(v: float) -> void:
		Game.set_volume(snappedf(clampf(v, 0.0, 1.0), 0.1))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sel := has_focus()
		if sel:
			draw_rect(r, Color(UI.CORE, 0.15))
			draw_rect(r, UI.CORE, false, UI.STROKE)
		var y := (size.y - UI.text_height(28)) * 0.5
		var x := 24.0
		if sel:
			var mk := 28 * 0.42
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y * 0.5 - mk * 0.6), Vector2(x + mk, size.y * 0.5), Vector2(x, size.y * 0.5 + mk * 0.6)]), UI.CORE)
			x += mk + 16.0
		UI.text(self, Vector2(x, y), "VOLUME", 28, UI.CORE, 600, 0.2)
		var n := roundi(Game.volume * 10.0)
		var bx := _blocks_x()
		for i in 10:
			var b := Rect2(Vector2(bx + i * (BLOCK.x + GAP), (size.y - BLOCK.y) * 0.5), BLOCK)
			if i < n:
				draw_rect(b, UI.CORE)
			else:
				draw_rect(b, Color(UI.CORE, 0.45), false, UI.STROKE)
		UI.text(self, Vector2(size.x - 24.0, y), str(n * 10), 28, UI.CORE, 600, 0.0, 1)
