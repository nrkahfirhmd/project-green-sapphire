extends Control
## On-screen controls (handoff screen 05): a floating analog stick on the
## left, HEAVY / LIGHT / DODGE on the right, and the square pause button at
## the top left. Every position is an offset from a safe-area corner.
##
## These drive the same input actions the keyboard does, at analog strength, so
## Input.get_vector in player.gd reads the stick exactly like a gamepad and
## nothing in the gameplay scripts knows touch exists.
##
## States per the spec: idle, pressed (scale 0.94, solid), disabled (dashed,
## while `locked`, e.g. during a boss intro), and dodge cooldown (a ring that
## sweeps round over the 0.5 s cooldown). Pale Jade never appears here: a
## button lighting up must never read as a telegraph.
##
## Hidden once the run ends (the result screen has its own buttons) and while
## the game is paused.

const UI := preload("res://scripts/ui/ui.gd")

const STICK_RADIUS := 115.0
const KNOB_RADIUS := 50.0
const TOUCH_SLOP := 1.15        # thumbs are imprecise; accept a little outside the circle
const PAUSE := Vector2(100, 100)
const COOLDOWN_R := 53.0

var locked := false             # set while input must not reach the game
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _knob := Vector2.ZERO       # knob offset from the stick origin, in pixels
var _btn_touch := {}            # touch index -> action name
var _held := {}                 # action -> frames held down
var _release_q: Array = []
var _over := false
var _scale := {}                # action -> drawn scale, eased toward its target
var _was_cooling := false
var _ready_pop := 0.0           # dodge "ready" pop, 1 -> 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS    # so a release still lands if a press pauses the game
	_stick_origin = _stick_home()
	await get_tree().process_frame     # current_scene isn't set yet during a scene change
	# the jail has no run to end, so it has no run_over and the controls never close
	var scene := get_tree().current_scene
	if scene and scene.has_signal("run_over"):
		scene.run_over.connect(_on_run_over)


func _on_run_over(_win: bool) -> void:
	_over = true
	_drop_stick()
	for a in _btn_touch.values():
		Input.action_release(a)
	_btn_touch.clear()


func _stick_home() -> Vector2:
	var s := Game.safe_area(size)
	return Vector2(s.position.x + 150.0, s.end.y - 170.0)


## The action buttons, anchored to the bottom-right of the safe area.
func _buttons() -> Array:
	var s := Game.safe_area(size)
	return [
		{"a": "attack_heavy", "p": s.end - Vector2(130, 150), "r": 70.0, "t": "HEAVY"},
		{"a": "attack_light", "p": s.end - Vector2(295, 77), "r": 60.0, "t": "LIGHT"},
		{"a": "dodge", "p": s.end - Vector2(160, 322), "r": 58.0, "t": "DODGE"},
	]


func _pause_rect() -> Rect2:
	return Rect2(Game.safe_area(size).position + Vector2(24, 24), PAUSE)


func _active() -> bool:
	return not _over and not locked and not get_tree().paused and visible


# --- input ------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active():
				_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_set_knob(event.position - _stick_origin)


func _on_press(index: int, pos: Vector2) -> void:
	if _pause_rect().grow(10).has_point(pos):
		_tap(index, "pause")
		return
	for b in _buttons():
		if pos.distance_to(b["p"]) <= float(b["r"]) * TOUCH_SLOP:
			_tap(index, b["a"])
			return
	# the stick is floating: it appears under the thumb instead of at a fixed
	# spot, which is the difference between usable and not on a phone
	if _stick_touch == -1 and pos.x < size.x * 0.5:
		_stick_touch = index
		_stick_origin = pos
		_set_knob(Vector2.ZERO)


func _tap(index: int, action: String) -> void:
	_btn_touch[index] = action
	Input.action_press(action)
	_held[action] = 0


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


func _process(delta: float) -> void:
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

	# pressed buttons ease to 0.94 (0.06 s down, 0.10 s back up)
	var pressed := _btn_touch.values()
	for b in _buttons():
		var a: String = b["a"]
		var target := 0.94 if pressed.has(a) else 1.0
		# 0.06 of scale over 0.06 s down, over 0.10 s back up
		_scale[a] = move_toward(float(_scale.get(a, 1.0)), target, delta * (1.0 if target < 1.0 else 0.6))
	# dodge pops when its cooldown runs out
	var cooling := _dodge_cd() > 0.0
	if _was_cooling and not cooling:
		_ready_pop = 1.0
	_was_cooling = cooling
	_ready_pop = maxf(0.0, _ready_pop - delta / 0.12)
	queue_redraw()


func _dodge_cd() -> float:
	var pl := get_tree().get_first_node_in_group("player")
	return float(pl._dodge_cd) if pl and "_dodge_cd" in pl else 0.0


# --- draw -------------------------------------------------------------
func _draw() -> void:
	if _over or get_tree().paused:
		return
	var c := UI.CORE
	var pressed := _btn_touch.values()

	# pause: 100x100 square with two bars
	var pr := _pause_rect()
	var pdown := pressed.has("pause")
	if locked:
		UI.dashed_rect(self, pr, Color(c, 0.3))
	else:
		draw_rect(pr, Color(c, 0.5) if pdown else Color(UI.MOSS, 0.6))
		if not pdown:
			draw_rect(pr, Color(c, 0.6), false, UI.STROKE)
	var bar_col := UI.MOSS if pdown else Color(c, 0.3 if locked else 1.0)
	for x in [-11.0, 11.0]:
		draw_rect(Rect2(pr.get_center() + Vector2(x - 5.0, -18.0), Vector2(10, 36)), bar_col)

	# stick: a resting hint, or live under the thumb
	var live := _stick_touch != -1
	var origin := _stick_origin if live else _stick_home()
	var ring_a := 0.6 if live else 0.35
	draw_arc(origin, STICK_RADIUS, 0, TAU, 64, Color(c, ring_a * (0.5 if locked else 1.0)), UI.STROKE)
	var knob := origin + _knob
	draw_circle(knob, KNOB_RADIUS, Color(c, 0.5 if live else 0.2))
	if not live:
		draw_arc(knob, KNOB_RADIUS, 0, TAU, 48, Color(c, 0.35), UI.STROKE)

	for b in _buttons():
		var a: String = b["a"]
		var p: Vector2 = b["p"]
		var r: float = b["r"]
		var down := pressed.has(a)
		var sc := float(_scale.get(a, 1.0))
		if a == "dodge" and _ready_pop > 0.0:
			sc *= 1.0 + 0.08 * _ready_pop
		r *= sc
		var label_col := c
		if locked:
			_dashed_circle(p, r, Color(c, 0.3))
			label_col = Color(c, 0.3)
		elif down:
			draw_circle(p, r, Color(c, 0.5))
			label_col = UI.MOSS
		elif a == "dodge" and _dodge_cd() > 0.0:
			# cooldown: dim ring, and an arc sweeping clockwise from 12 o'clock
			draw_circle(p, r, Color(UI.MOSS, 0.45))
			draw_arc(p, r, 0, TAU, 48, Color(c, 0.25), UI.STROKE)
			var done := 1.0 - _dodge_cd() / 0.5
			draw_arc(p, COOLDOWN_R * sc, -PI * 0.5, -PI * 0.5 + TAU * done, 48, c, 6.0)
			label_col = Color(c, 0.4)
		else:
			draw_circle(p, r, Color(UI.MOSS, 0.45))
			draw_arc(p, r, 0, TAU, 48, Color(c, 0.6), UI.STROKE)
		UI.text(self, p - Vector2(0, UI.text_height(18) * 0.5), b["t"], 18, label_col, 600, 0.12, 0)


func _dashed_circle(p: Vector2, r: float, col: Color) -> void:
	for k in 24:
		var a0 := TAU * k / 24.0
		draw_arc(p, r, a0, a0 + TAU / 48.0, 4, col, UI.STROKE)
