extends Control
## Home (handoff screen 01): a captioned, framed title with a row of five
## diamonds, then PLAY and SETTINGS. Settings opens the shared settings
## panel (screen 02) over it. Built in code from the UI kit so it matches
## every other screen.

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")
const Settings := preload("res://scripts/ui/settings_panel.gd")
const JAIL := "res://scenes/hub.tscn"

var _menu: Control
var _play: BaseButton
var _settings: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := W.vbox(28)
	# caption flanked by two lines
	var cap := W.hbox(24, BoxContainer.ALIGNMENT_CENTER)
	cap.add_child(W.Shape.new(Vector2(120, 26), _line))
	cap.add_child(W.Text.new("A JAIL OF FIVE CELLS", 20, 400, 0.4, Color(UI.CORE, 0.75)))
	cap.add_child(W.Shape.new(Vector2(120, 26), _line))
	col.add_child(cap)
	# framed title
	var title := W.Frame.new(28, 64)
	title.fill = Color(0, 0, 0, 0)
	title.add_child(W.Text.new("GREEN SAPPHIRE", 112, 600, 0.2))
	var tc := CenterContainer.new()
	tc.add_child(title)
	col.add_child(tc)
	# five diamonds: outlines, the middle one solid and larger
	col.add_child(W.Shape.new(Vector2(0, 36), func(c: Control, s: Vector2):
		for i in 5:
			var p := Vector2(s.x * 0.5 + (i - 2) * 52.0, s.y * 0.5)
			if i == 2:
				UI.diamond(c, p, 28, UI.CORE)
			else:
				UI.diamond(c, p, 18, UI.CORE, false)))

	var buttons := W.vbox(16)
	buttons.add_theme_constant_override("separation", 16)
	_play = Btn.new("PLAY", Vector2(400, 100), 32)
	var settings := Btn.new("SETTINGS", Vector2(400, 100), 32)
	buttons.add_child(_play)
	buttons.add_child(settings)
	var bc := CenterContainer.new()
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_top", 24)
	bm.add_child(buttons)
	bc.add_child(bm)
	col.add_child(bc)

	_menu = W.top_centred(col, 150)
	add_child(_menu)

	_settings = Settings.new()
	_settings.hide()
	add_child(_settings)

	_play.pressed.connect(func(): get_tree().change_scene_to_file(JAIL))
	settings.pressed.connect(_open_settings.bind(true))
	_settings.closed.connect(_open_settings.bind(false))
	_play.grab_focus.call_deferred()


func _open_settings(on: bool) -> void:
	_menu.visible = not on
	if on:
		_settings.open()
	else:
		_settings.hide()
		_play.grab_focus()


func _line(c: Control, s: Vector2) -> void:
	c.draw_rect(Rect2(0, s.y * 0.5 - 1.0, s.x, 2.0), Color(UI.CORE, 0.75))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.MOSS)
