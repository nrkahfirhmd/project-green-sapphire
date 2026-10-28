extends Control
## Pause (handoff screen 07), shared by the jail and every fight: an 82 % Moss
## overlay and a framed 640-wide panel with PAUSED, a caption, and RESUME /
## BACK TO JAIL (HOME in the jail) / SETTINGS. Toggled by the "pause" action,
## which the touch controls' pause button and Esc both press.
##
## Pauses the scene tree, so this node and everything it opens run with
## PROCESS_MODE_ALWAYS.

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")
const Settings := preload("res://scripts/ui/settings_panel.gd")

var enabled := true             # the fight turns this off once the run is over
var caption: Callable           # -> String, read each time the sheet opens
var _panel: Control
var _sheet: Control
var _caption: Control
var _resume: BaseButton
var _settings: Control
var _fade := 0.0
var _tw: Tween
const TOP := 120.0


## `back_label`/`back_scene`: where the second button goes.
func setup(back_label: String, back_scene: String, caption_fn: Callable) -> void:
	caption = caption_fn
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

	var col := W.vbox(16)
	col.add_child(W.Text.new("PAUSED", 48, 600, 0.25))
	_caption = W.Text.new("", 16, 400, 0.2, Color(UI.CORE, 0.75))
	col.add_child(_caption)
	col.add_child(W.Shape.new(Vector2(0, 8), func(_c: Control, _s: Vector2): pass))
	_resume = Btn.new("RESUME", Vector2(480, 100), 28)
	var back := Btn.new(back_label, Vector2(480, 100), 28)
	var settings := Btn.new("SETTINGS", Vector2(480, 100), 28)
	for b in [_resume, back, settings]:
		col.add_child(b)
	var frame := W.Frame.new(48, 48)
	frame.custom_minimum_size.x = 640
	frame.add_child(col)
	_panel = frame
	_sheet = W.top_centred(frame, TOP)
	add_child(_sheet)

	_settings = Settings.new()
	_settings.hide()
	add_child(_settings)

	_resume.pressed.connect(close)
	back.pressed.connect(func():
		get_tree().paused = false
		Game.go(back_scene))
	settings.pressed.connect(func():
		_sheet.hide()
		_settings.open())
	_settings.closed.connect(func():
		_settings.hide()
		_sheet.show()
		_resume.grab_focus())


func _process(_d: float) -> void:
	if Input.is_action_just_pressed("pause"):
		if visible:
			close()
		elif enabled:
			open()
	if visible:
		queue_redraw()


func open() -> void:
	Haptics.play("tap")
	Sfx.play("pause_open")
	get_tree().paused = true
	_caption.set_text(caption.call() if caption.is_valid() else "")
	show()
	_sheet.show()
	_settings.hide()
	# overlay fades in; the panel rises 24 units into place
	_fade = 0.0
	_sheet.offset_top = TOP + 24.0
	_sheet.modulate.a = 0.0
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel()
	_tw.tween_property(self, "_fade", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_sheet, "offset_top", TOP, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_property(_sheet, "modulate:a", 1.0, 0.18)
	_resume.grab_focus()


## The sheet drops back 24 units as the overlay fades, then play resumes.
func close() -> void:
	Sfx.play("pause_close")
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel()
	_tw.tween_property(self, "_fade", 0.0, 0.14).set_ease(Tween.EASE_IN)
	_tw.tween_property(_sheet, "offset_top", TOP + 24.0, 0.14).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_property(_sheet, "modulate:a", 0.0, 0.14)
	_tw.chain().tween_callback(func():
		hide()
		get_tree().paused = false)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.82 * _fade))
