extends Control
## Home screen: Play / Settings. Settings holds volume and a haptic toggle,
## both stored in the Game autoload (persisted to user://settings.cfg).
## Native Control nodes so touch, mouse, and keyboard focus all work for free.

@onready var _menu: Control = $Menu
@onready var _settings: Control = $Settings


func _ready() -> void:
	$Menu/VBox/Play.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	$Menu/VBox/Settings.pressed.connect(_open_settings.bind(true))
	$Settings/VBox/Back.pressed.connect(_open_settings.bind(false))

	var slider: HSlider = $Settings/VBox/Volume/Slider
	var haptic: CheckButton = $Settings/VBox/Haptic
	slider.value = Game.volume
	haptic.button_pressed = Game.haptic_enabled
	slider.value_changed.connect(func(v): Game.set_volume(v))
	haptic.toggled.connect(func(on): Game.set_haptic(on))

	_open_settings(false)


func _open_settings(on: bool) -> void:
	_settings.visible = on
	_menu.visible = not on
