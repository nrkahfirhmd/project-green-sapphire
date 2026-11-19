extends Control
## On-screen controls (handoff screen 05): a floating analog stick on the
## left, HEAVY / LIGHT / DODGE on the right with the three abilities (RICOCHET,
## BLINK, ULT) around them, and the square pause button at the top left. Every
## position is an offset from a safe-area corner.
##
## RICOCHET is aimed like a slingshot: hold it and drag away from where you
## want to go; the drag feeds the aim_* actions and letting go launches.
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
##
## Each button carries an icon over its name (a blade for the thrusts, chevrons
## for the dodge) so what it does reads before the word does. With `editing`
## set (Settings > ARRANGE BUTTONS) it becomes the layout editor instead: drag
## a button to move it, saved to Game.button_layout. `hidden_buttons` lets the
## prologue bring each one in only as it is taught.

const UI := preload("res://scripts/ui/ui.gd")

const STICK_RADIUS := 115.0
const KNOB_RADIUS := 50.0
const TOUCH_SLOP := 1.3         # thumbs are imprecise; accept a little outside the circle
const PAUSE := Vector2(100, 100)
const COOLDOWN_R := 53.0
const DRAG_FULL := 90.0         # drag this far for a full-strength aim
const COOLING := ["dodge", "ricochet", "blink"]   # buttons with a cooldown ring

var locked := false             # set while input must not reach the game
var highlight := ""             # an action (or "move", the stick) the tutorial is pointing at
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _knob := Vector2.ZERO       # knob offset from the stick origin, in pixels
var _btn_touch := {}            # touch index -> action name
var _held := {}                 # action -> frames held down
var _release_q: Array = []
var _over := false
var _scale := {}                # action -> drawn scale, eased toward its target
var _was_cooling := {}          # action -> was it cooling last frame
var _pop := {}                  # action -> "ready" pop, 1 -> 0
var _drag_touch := -1           # the touch dragging back on RICOCHET
var _drag := Vector2.ZERO
var _was_ult_ready := false
var _deny := {}                 # action -> 1 -> 0 shake when pressed but not ready
var hidden_buttons: Array = []  # actions not drawn or pressable yet
var editing := false            # layout editor mode, see the header
var _edit_touch := -1
var _edit_a := ""
var _edit_grab := Vector2.ZERO

signal edit_done

## Where each button sits by default, as an offset from the safe area's
## bottom-right at button size 1, and its radius.
const LAYOUT := {
	"attack_heavy": [Vector2(130, 150), 70.0, "HEAVY"],
	"attack_light": [Vector2(295, 77), 60.0, "LIGHT"],
	"dodge": [Vector2(160, 322), 58.0, "DODGE"],
	"blink": [Vector2(330, 250), 52.0, "BLINK"],
	"ricochet": [Vector2(460, 120), 52.0, "RICOCHET"],
	"ultimate": [Vector2(150, 480), 52.0, "ULT"],
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS    # so a release still lands if a press pauses the game
	_stick_origin = _stick_home()
	if editing:
		return
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
	create_tween().tween_property(self, "modulate:a", 0.0, 0.25)   # out of the result screen's way


func _stick_home() -> Vector2:
	var s := Game.safe_area(size)
	return Vector2(s.position.x + 150.0, s.end.y - 170.0)


## The action buttons, anchored to the bottom-right of the safe area.
func _buttons() -> Array:
	var s := Game.safe_area(size)
	var k := Game.button_size
	var out := []
	for a in LAYOUT:
		if hidden_buttons.has(a):
			continue
		var d: Array = LAYOUT[a]
		var off: Vector2 = Game.button_layout.get(a, d[0])
		var r: float = d[1] * k
		# clamped on read too, so a layout saved at a smaller size never falls off the screen
		var p := (s.end - off * k).clamp(s.position + Vector2(r, r), s.end - Vector2(r, r))
		out.append({"a": a, "p": p, "r": r, "t": d[2]})
	return out


## The button under a touch: the nearest one in reach, so the generous
## slop round each never steals a press meant for its neighbour.
func _hit(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in _buttons():
		var d := pos.distance_to(b["p"]) / float(b["r"])
		if d <= TOUCH_SLOP and d < best_d:
			best = b
			best_d = d
	return best


func _pause_rect() -> Rect2:
	return Rect2(Game.safe_area(size).position + Vector2(24, 24), PAUSE)


func _active() -> bool:
	return not _over and not locked and not get_tree().paused and visible


# --- input ------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if editing:
		_edit_input(event)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active():
				_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag and event.index == _stick_touch:
		_set_knob(event.position - _stick_origin)
	elif event is InputEventScreenDrag and event.index == _drag_touch:
		_set_drag(event.position)


func _on_press(index: int, pos: Vector2) -> void:
	if _pause_rect().grow(10).has_point(pos):
		_tap(index, "pause")
		return
	var hit := _hit(pos)
	if not hit.is_empty():
		_tap(index, hit["a"])
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
	# pressed too early: the button shakes its head, and the phone says no
	var not_ready := (action != "dodge" and COOLING.has(action) and _cd(action).x > 0.0) or (action == "ultimate" and _ult().y < 1.0)
	if not_ready and _player() != null:
		_deny[action] = 1.0
		Haptics.play("denied")
		Sfx.play("denied")
	if action == "ricochet":
		_drag_touch = index
		_drag = Vector2.ZERO


## Pulling back aims the other way, like a slingshot.
func _set_drag(pos: Vector2) -> void:
	var centre: Vector2 = _button("ricochet")["p"]
	_drag = pos - centre
	var aim := -_drag / DRAG_FULL
	aim = aim.limit_length(1.0) if _drag.length() > 20.0 else Vector2.ZERO
	_axis("aim_left", "aim_right", aim.x)
	_axis("aim_up", "aim_down", aim.y)


func _button(action: String) -> Dictionary:
	for b in _buttons():
		if b["a"] == action:
			return b
	return {}


func _on_release(index: int) -> void:
	if index == _drag_touch:
		# the player latches the aim while the button is held, so it can go now
		_drag_touch = -1
		_drag = Vector2.ZERO
		_axis("aim_left", "aim_right", 0.0)
		_axis("aim_up", "aim_down", 0.0)
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
	# a button pops when its cooldown runs out, and ULT when it becomes ready
	for a in COOLING:
		var cooling := _cd(a).x > 0.0
		if _was_cooling.get(a, false) and not cooling:
			_pop[a] = 1.0
		_was_cooling[a] = cooling
	var ult := _ult().x >= 1.0
	if ult and not _was_ult_ready:
		_pop["ultimate"] = 1.0
	_was_ult_ready = ult
	for a in _pop:
		_pop[a] = maxf(0.0, float(_pop[a]) - delta / 0.12)
	for a in _deny:
		_deny[a] = maxf(0.0, float(_deny[a]) - delta / 0.3)
	queue_redraw()


func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


## (left, total) for a button with a cooldown.
func _cd(action: String) -> Vector2:
	var pl := _player()
	return pl.cooldown(action) if pl and pl.has_method("cooldown") else Vector2.ZERO


## (charge 0..1, usable 0/1) for the ultimate.
func _ult() -> Vector2:
	var pl := _player()
	if not (pl and "ult_charge" in pl):
		return Vector2.ZERO
	return Vector2(float(pl.ult_charge) / float(pl.ULT_COST), 1.0 if pl.ult_ready() else 0.0)


# --- draw -------------------------------------------------------------
func _draw() -> void:
	if editing:
		_draw_editor()
		return
	if _over or get_tree().paused:
		return
	var c := UI.CORE
	var pressed := _btn_touch.values()

	# pause: 100x100 square with two bars
	var pr := _pause_rect()
	var pdown := pressed.has("pause")
	if locked:
		draw_rect(pr, Color(UI.MOSS, 0.8))
		UI.dashed_rect(self, pr, Game.FLOOR)
	else:
		draw_rect(pr, c if pdown else Color(UI.MOSS, 0.8))
		if not pdown:
			draw_rect(pr, c, false, UI.STROKE)
	var bar_col := UI.MOSS if pdown else (Game.FLOOR if locked else c)
	for x in [-11.0, 11.0]:
		draw_rect(Rect2(pr.get_center() + Vector2(x - 5.0, -18.0), Vector2(10, 36)), bar_col)

	# stick: a resting hint, or live under the thumb
	var live := _stick_touch != -1
	var origin := _stick_origin if live else _stick_home()
	# no alpha here: the last pass snaps a see-through ring to whatever is under
	# it, so it would vanish on the floor. A dark band keeps it visible on both.
	var stick_col: Color = Game.FLOOR if locked else c
	draw_arc(origin, STICK_RADIUS, 0, TAU, 64, UI.MOSS, UI.STROKE + 4.0)
	draw_arc(origin, STICK_RADIUS, 0, TAU, 64, stick_col, UI.STROKE)
	var knob := origin + _knob
	draw_circle(knob, KNOB_RADIUS, stick_col if live else Color(UI.MOSS, 0.8))
	if not live:
		draw_arc(knob, KNOB_RADIUS, 0, TAU, 48, stick_col, UI.STROKE)

	for b in _buttons():
		var a: String = b["a"]
		var p: Vector2 = b["p"]
		var no := float(_deny.get(b["a"], 0.0))
		if not Game.reduced_motion:
			p.x += sin(no * 28.0) * 8.0 * no
		var r: float = b["r"]
		var down := pressed.has(a)
		var sc := float(_scale.get(a, 1.0)) * (1.0 + 0.08 * float(_pop.get(a, 0.0)))
		var ring := (r - 5.0) * sc        # the cooldown arc sits 2 units inside the edge
		r *= sc
		var label_col := c
		var cd := _cd(a) if COOLING.has(a) else Vector2.ZERO
		var ult := _ult() if a == "ultimate" else Vector2(1, 1)
		if locked:
			draw_circle(p, r, Color(UI.MOSS, 0.8))
			_dashed_circle(p, r, Game.FLOOR)
			label_col = Game.FLOOR
		elif down:
			draw_circle(p, r, c)
			label_col = UI.MOSS
		elif cd.x > 0.0 or ult.y < 1.0:
			# cooling down (or the ultimate still charging): dim ring, and an arc
			# sweeping clockwise from 12 o'clock as it comes back
			draw_circle(p, r, Color(UI.MOSS, 0.8))
			draw_arc(p, r, 0, TAU, 48, Game.FLOOR, UI.STROKE)
			var done := ult.x if a == "ultimate" else 1.0 - cd.x / maxf(cd.y, 0.01)
			if done > 0.0:
				draw_arc(p, ring, -PI * 0.5, -PI * 0.5 + TAU * clampf(done, 0.0, 1.0), 48, c, 6.0)
			label_col = Game.FLOOR
		else:
			draw_circle(p, r, Color(UI.MOSS, 0.8))
			draw_arc(p, r, 0, TAU, 48, c, UI.STROKE)
		_face(b, p, r, label_col)

	# the tutorial's pointer: a ring breathing round the control it teaches
	if highlight != "":
		var hb := _button(highlight)
		var hp: Vector2 = _stick_home() if highlight == "move" else hb.get("p", Vector2.ZERO)
		var hr: float = STICK_RADIUS if highlight == "move" else float(hb.get("r", 0.0))
		if highlight == "move" or not hb.is_empty():
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
			draw_arc(hp, hr + 12.0 + 8.0 * k, 0, TAU, 64, Color(c, 0.4 + 0.5 * k), 4.0)

	# RICOCHET's pull: a line from the button to the thumb
	if _drag_touch != -1 and _drag.length() > 20.0:
		var from: Vector2 = _button("ricochet")["p"]
		draw_line(from, from + _drag, Color(c, 0.6), UI.STROKE)
		draw_circle(from + _drag, 8.0, Color(c, 0.6))


func _dashed_circle(p: Vector2, r: float, col: Color) -> void:
	for k in 24:
		var a0 := TAU * k / 24.0
		draw_arc(p, r, a0, a0 + TAU / 48.0, 4, col, UI.STROKE)


## A button's icon over its name.
func _face(b: Dictionary, p: Vector2, r: float, col: Color) -> void:
	var px := 18 if r > 66.0 else 14
	var u := r * 0.2                   # icon unit
	var ic := p - Vector2(0, r * 0.22)
	var w := UI.STROKE + 1.0
	match b["a"]:
		"attack_light", "attack_heavy":
			# a blade pointing up and right; the heavy one longer and broader
			var n := 1.3 if b["a"] == "attack_heavy" else 1.0
			var d := Vector2(1, -1).normalized()
			var hilt := ic - d * u * 1.3 * n
			draw_line(hilt, ic + d * u * 1.5 * n, col, w * n)
			draw_line(hilt + d.orthogonal() * u * 0.6, hilt - d.orthogonal() * u * 0.6, col, w)
		"dodge":
			for x in [-0.5, 0.5]:
				var t := ic + Vector2(u * x + u * 0.4, 0)
				draw_polyline(PackedVector2Array([t + Vector2(-u * 0.7, -u * 0.8), t, t + Vector2(-u * 0.7, u * 0.8)]), col, w)
		"blink":
			for i in 3:
				var x0 := ic.x - u * 1.4 + i * u * 0.75
				draw_line(Vector2(x0, ic.y), Vector2(x0 + u * 0.4, ic.y), col, w)
			draw_polyline(PackedVector2Array([ic + Vector2(u * 0.9, -u * 0.6), ic + Vector2(u * 1.5, 0), ic + Vector2(u * 0.9, u * 0.6)]), col, w)
		"ricochet":
			draw_polyline(PackedVector2Array([ic + Vector2(-u * 1.4, u * 0.6), ic + Vector2(-u * 0.5, -u * 0.6), ic + Vector2(u * 0.4, u * 0.6), ic + Vector2(u * 1.3, -u * 0.6)]), col, w)
		"ultimate":
			UI.diamond(self, ic, u * 1.6, col, false, w)
			UI.diamond(self, ic, u * 0.7, col, true)
	UI.text(self, p + Vector2(0, r * 0.18), b["t"], px, col, 600, 0.12, 0)


## Brings a hidden button in, with the ready pop.
func reveal(action: String) -> void:
	hidden_buttons.erase(action)
	_pop[action] = 1.0


# --- layout editor ----------------------------------------------------
## DONE and RESET, side by side at the top centre.
func _edit_rects() -> Array:
	var s := Game.safe_area(size)
	var y := s.position.y + 110.0
	var cx := s.get_center().x
	return [Rect2(cx - 316.0, y, 300.0, 100.0), Rect2(cx + 16.0, y, 300.0, 100.0)]


func _edit_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		edit_done.emit()
	elif event is InputEventScreenTouch and event.pressed and _edit_touch == -1:
		var rs := _edit_rects()
		if rs[0].has_point(event.position):
			Sfx.play("toggle")
			edit_done.emit()
		elif rs[1].has_point(event.position):
			Sfx.play("toggle")
			Game.change("button_layout", {})
		else:
			var hit := _hit(event.position)
			if not hit.is_empty():
				_edit_touch = event.index
				_edit_a = hit["a"]
				_edit_grab = event.position - hit["p"]
				Haptics.play("tap")
	elif event is InputEventScreenDrag and event.index == _edit_touch:
		var s := Game.safe_area(size)
		var k := Game.button_size
		var layout: Dictionary = Game.button_layout.duplicate()
		layout[_edit_a] = (s.end - (event.position - _edit_grab)) / k
		Game.button_layout = layout        # saved on release, not every drag event
	elif event is InputEventScreenTouch and not event.pressed and event.index == _edit_touch:
		_edit_touch = -1
		# store where it was drawn, so a drag past the edge doesn't leave an off-screen offset
		var b := _button(_edit_a)
		var layout: Dictionary = Game.button_layout.duplicate()
		layout[_edit_a] = (Game.safe_area(size).end - b["p"]) / Game.button_size
		Game.change("button_layout", layout)


func _draw_editor() -> void:
	var c := UI.CORE
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.94))
	var s := Game.safe_area(size)
	UI.text(self, Vector2(s.get_center().x, s.position.y + 40.0), "DRAG A BUTTON TO MOVE IT", 28, c, 600, 0.2, 0)
	var rs := _edit_rects()
	for i in 2:
		draw_rect(rs[i], c if i == 0 else Color(UI.MOSS, 0.8))
		draw_rect(rs[i], c, false, UI.STROKE)
		UI.text(self, rs[i].get_center() - Vector2(0, UI.text_height(28) * 0.5), ["DONE", "RESET"][i], 28, UI.MOSS if i == 0 else c, 600, 0.2, 0)
	# the stick floats, so only its resting spot is shown
	draw_arc(_stick_home(), STICK_RADIUS, 0, TAU, 64, Color(c, 0.5), UI.STROKE)
	UI.text(self, _stick_home() - Vector2(0, UI.text_height(18) * 0.5), "STICK", 18, Color(c, 0.6), 600, 0.12, 0)
	for b in _buttons():
		var held: bool = _edit_touch != -1 and b["a"] == _edit_a
		draw_circle(b["p"], b["r"], c if held else Color(UI.MOSS, 0.8))
		draw_arc(b["p"], b["r"], 0, TAU, 48, c, UI.STROKE)
		_face(b, b["p"], b["r"], UI.MOSS if held else c)
