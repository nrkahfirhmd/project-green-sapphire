extends Control
## On-screen controls: a floating analog stick on the left, action buttons on
## the right, and a restart button once the run is over.
##
## These drive the same input actions the keyboard does, at analog strength, so
## Input.get_vector in player.gd reads the stick exactly like a gamepad and
## nothing in the gameplay scripts knows touch exists.
##
## Palette: Deep Moss and Sapphire Core only. Pale Jade stays reserved for
## "look now" moments, so a pressed button fills Sapphire Core rather than
## flashing -- a button lighting up must never read as a telegraph.

const STICK_RADIUS := 115.0
const KNOB_RADIUS := 50.0
const TOUCH_SLOP := 1.15        # thumbs are imprecise; accept a little outside the circle

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _knob := Vector2.ZERO       # knob offset from the stick origin, in pixels
var _btn_touch := {}            # touch index -> action name
var _held := {}                 # action -> frames held down
var _release_q: Array = []
var _over := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_origin = _stick_home()
	await get_tree().process_frame     # let Main spawn player/boss
	var pl := get_tree().get_first_node_in_group("player")
	var bo := get_tree().get_first_node_in_group("boss")
	if pl:
		pl.died.connect(_on_run_over)
	if bo:
		bo.died.connect(_on_run_over)


func _on_run_over() -> void:
	_over = true
	_drop_stick()
	for a in _btn_touch.values():
		Input.action_release(a)
	_btn_touch.clear()


func _stick_home() -> Vector2:
	var s := Game.safe_area(size)
	return Vector2(s.position.x + 250.0, s.end.y - 250.0)


## Buttons are anchored to the corners rather than placed at fixed coordinates,
## so the layout survives the aspect ratios that "expand" stretch allows.
func _buttons() -> Array:
	var s := Game.safe_area(size)
	if _over:
		return [{"a": "restart", "p": Vector2(s.get_center().x, s.position.y + s.size.y * 0.72),
			"r": 62.0, "t": "RESTART"}]
	return [
		{"a": "attack_heavy", "p": s.end - Vector2(160, 300), "r": 70.0, "t": "HEAVY"},
		{"a": "attack_light", "p": s.end - Vector2(310, 190), "r": 60.0, "t": "LIGHT"},
		{"a": "dodge", "p": s.end - Vector2(160, 120), "r": 58.0, "t": "DODGE"},
	]


# --- input ------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_set_knob(event.position - _stick_origin)


func _on_press(index: int, pos: Vector2) -> void:
	for b in _buttons():
		if pos.distance_to(b["p"]) <= float(b["r"]) * TOUCH_SLOP:
			_btn_touch[index] = b["a"]
			Input.action_press(b["a"])
			_held[b["a"]] = 0
			return
	# the stick is floating: it appears under the thumb instead of at a fixed
	# spot, which is the difference between usable and not on a phone
	if not _over and _stick_touch == -1 and pos.x < size.x * 0.5:
		_stick_touch = index
		_stick_origin = pos
		_set_knob(Vector2.ZERO)


func _on_release(index: int) -> void:
	if index == _stick_touch:
		_drop_stick()
	elif _btn_touch.has(index):
		var a: String = _btn_touch[index]
		if not _release_q.has(a):
			_release_q.append(a)
		_btn_touch.erase(index)


func _drop_stick() -> void:
	_stick_touch = -1
	_knob = Vector2.ZERO
	_axis("move_left", "move_right", 0.0)
	_axis("move_up", "move_down", 0.0)


func _set_knob(v: Vector2) -> void:
	_knob = v.limit_length(STICK_RADIUS)
	var n := _knob / STICK_RADIUS
	_axis("move_left", "move_right", n.x)
	_axis("move_up", "move_down", n.y)


## Feeds one action pair at analog strength. Pressing both sides of an axis at
## once would fight itself, so the opposite action is always released first.
func _axis(neg: String, pos: String, v: float) -> void:
	if v > 0.0:
		Input.action_release(neg)
		Input.action_press(pos, v)
	elif v < 0.0:
		Input.action_release(pos)
		Input.action_press(neg, -v)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _process(_delta: float) -> void:
	# A tap that starts and ends inside one frame would never be seen by
	# is_action_just_pressed, which is how every attack in player.gd fires, so
	# a release always waits until the action has been held a full frame.
	var still: Array = []
	for a in _release_q:
		if int(_held.get(a, 0)) > 0:
			Input.action_release(a)
			_held.erase(a)
		else:
			still.append(a)
	_release_q = still
	for a in _held:
		_held[a] = int(_held[a]) + 1
	queue_redraw()


# --- draw -------------------------------------------------------------
func _draw() -> void:
	var line := Color(Game.SAPPHIRE_CORE, 0.6)
	var fill := Color(Game.DEEP_MOSS, 0.45)
	var font := ThemeDB.fallback_font

	if not _over:
		var origin := _stick_origin if _stick_touch != -1 else _stick_home()
		draw_circle(origin, STICK_RADIUS, fill)
		draw_arc(origin, STICK_RADIUS, 0, TAU, 48, line, 3.0)
		var knob := origin + _knob
		var live := _stick_touch != -1
		draw_circle(knob, KNOB_RADIUS, Color(Game.SAPPHIRE_CORE, 0.55 if live else 0.3))
		draw_arc(knob, KNOB_RADIUS, 0, TAU, 32, line, 2.5)

	var pressed := _btn_touch.values()
	for b in _buttons():
		var c: Vector2 = b["p"]
		var r: float = b["r"]
		var down: bool = pressed.has(b["a"])
		draw_circle(c, r, Color(Game.SAPPHIRE_CORE, 0.5) if down else fill)
		draw_arc(c, r, 0, TAU, 40, line, 3.0)
		var fs := 16
		draw_string(font, c + Vector2(-r, fs * 0.35), b["t"],
			HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs,
			Game.DEEP_MOSS if down else Color(Game.SAPPHIRE_CORE, 0.9))
