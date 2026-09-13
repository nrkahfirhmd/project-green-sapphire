extends Node
## Smoke check for the on-screen controls: feeds synthetic touch events through
## the real input pipeline and asserts the game-facing actions actually fire.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/touch_check.tscn
##
## Worth having because none of this is visible: the controls talk to the rest
## of the game only through Input actions, so a broken mapping looks like a
## dead button rather than an error.


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var tc: Control = main.get_node("UI/TouchControls")
	assert(tc != null, "TouchControls missing from the scene")

	# landscape-only, both ways up (DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	assert(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == 4,
		"handheld orientation should be sensor landscape")

	await _buttons_fire_their_actions(tc)
	await _a_one_frame_tap_still_registers(tc)
	await _stick_reads_as_an_analog_vector(tc)

	print("touch_check: stick and buttons drive the game's input actions")
	get_tree().quit()


func _buttons_fire_their_actions(tc) -> void:
	for b in tc._buttons():
		var action: String = b["a"]
		_touch(0, b["p"], true)
		await get_tree().process_frame
		assert(Input.is_action_pressed(action), "button did not press %s" % action)
		_touch(0, b["p"], false)
		# the release is deliberately deferred a frame, so it takes two to settle
		await get_tree().process_frame
		await get_tree().process_frame
		assert(not Input.is_action_pressed(action), "button did not release %s" % action)


## Pressing and releasing inside a single frame must still be seen, since every
## attack in player.gd fires on is_action_just_pressed.
func _a_one_frame_tap_still_registers(tc) -> void:
	var b: Dictionary = tc._buttons()[0]
	_touch(0, b["p"], true)
	_touch(0, b["p"], false)
	await get_tree().process_frame
	assert(Input.is_action_just_pressed(b["a"]), "a same-frame tap was swallowed")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not Input.is_action_pressed(b["a"]), "tap never released")


func _stick_reads_as_an_analog_vector(tc) -> void:
	var origin := Vector2(300, 600)
	_touch(1, origin, true)
	await get_tree().process_frame
	_drag(1, origin + Vector2(tc.STICK_RADIUS, 0))
	await get_tree().process_frame
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	assert(v.x > 0.9 and absf(v.y) < 0.1, "stick pushed right but read %s" % v)

	_drag(1, origin + Vector2(0, -tc.STICK_RADIUS * 0.5))
	await get_tree().process_frame
	v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	assert(v.y < -0.2 and v.x < 0.1, "stick pushed up but read %s" % v)

	_touch(1, origin, false)
	await get_tree().process_frame
	v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	assert(v == Vector2.ZERO, "stick still reading %s after release" % v)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Input.parse_input_event(e)
