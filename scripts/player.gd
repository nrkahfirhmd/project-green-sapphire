extends CharacterBody2D
## The Swordsman. Move (8-dir), dodge roll (i-frames + afterimage trail),
## light/heavy attack (one shared system, different numbers).
## Code-driven rig: 8 parts, oriented to facing, animated with tweens.

signal died
signal health_changed(current: int, max: int)
signal hit_taken

const MAX_HP := 4
const SPEED := 260.0

const DODGE_SPEED := 620.0
const DODGE_TIME := 0.18
const DODGE_IFRAME_TIME := 0.20
const DODGE_COOLDOWN := 0.5

const GHOST_LIFE := 0.30       # afterimage fade time
const GHOST_EVERY := 0.028     # afterimage spawn interval during dodge

# Shared attack skeleton: windup -> active -> recovery.
const ATTACKS := {
	"light": {"windup": 0.07, "active": 0.06, "recovery": 0.17, "dmg": 1, "reach": 92.0, "arc_deg": 100.0, "shake": 4.0, "hitstop": 0.05, "punch": 0.0},
	"heavy": {"windup": 0.28, "active": 0.08, "recovery": 0.44, "dmg": 3, "reach": 112.0, "arc_deg": 120.0, "shake": 11.0, "hitstop": 0.10, "punch": 1.09},
}

enum State { FREE, DODGE, ATTACK }

var hp := MAX_HP
var state: State = State.FREE
var facing := Vector2.DOWN
var invulnerable := false

var _dodge_cd := 0.0
var _atk_name := ""
var _atk_phase := ""          # "windup" | "active" | "recovery"
var _atk_timer := 0.0
var _atk_dur := 0.0           # duration of current phase, for progress
var _atk_hit_done := false
var _flash := 0.0             # Pale Jade damage flash, seconds remaining
var _visual := Vector2.ONE    # squash/stretch scale, tweened

var _walk := 0.0             # walk-cycle phase
var _walk_amp := 0.0         # 0..1 walk bounce strength
var _ghosts: Array = []      # [{pos:Vector2, f:float, age:float}]
var _ghost_acc := 0.0

@onready var boss: Node = get_tree().get_first_node_in_group("boss")


func _ready() -> void:
	add_to_group("player")
	health_changed.emit(hp, MAX_HP)


func _physics_process(delta: float) -> void:
	_dodge_cd = max(0.0, _dodge_cd - delta)
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta)

	# age + prune afterimages
	if not _ghosts.is_empty():
		for g in _ghosts:
			g.age += delta
		_ghosts = _ghosts.filter(func(g): return g.age < GHOST_LIFE)

	match state:
		State.FREE:
			_do_free(delta)
		State.DODGE:
			_do_dodge(delta)
		State.ATTACK:
			_do_attack(delta)

	move_and_slide()
	_clamp_to_arena()
	queue_redraw()


func _do_free(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	velocity = dir.normalized() * SPEED if dir != Vector2.ZERO else velocity.move_toward(Vector2.ZERO, SPEED * 0.35)

	# walk squash-and-stretch
	if velocity.length() > 30.0:
		_walk += delta * 16.0
		_walk_amp = move_toward(_walk_amp, 1.0, delta * 6.0)
	else:
		_walk_amp = move_toward(_walk_amp, 0.0, delta * 6.0)

	if Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0:
		_start_dodge()
	elif Input.is_action_just_pressed("attack_light"):
		_start_attack("light")
	elif Input.is_action_just_pressed("attack_heavy"):
		_start_attack("heavy")


func _start_dodge() -> void:
	state = State.DODGE
	_dodge_cd = DODGE_COOLDOWN
	_atk_timer = DODGE_TIME
	invulnerable = true
	velocity = facing * DODGE_SPEED
	_walk_amp = 0.0
	_ghost_acc = 0.0
	_pop_visual(Vector2(1.35, 0.7))   # stretch along travel
	_burst(global_position, Game.SAPPHIRE_CORE, 8)
	get_tree().create_timer(DODGE_IFRAME_TIME).timeout.connect(func(): invulnerable = false)


func _do_dodge(delta: float) -> void:
	_atk_timer -= delta
	velocity = velocity.move_toward(facing * SPEED, 1400.0 * delta)
	_ghost_acc -= delta
	if _ghost_acc <= 0.0:
		_ghosts.append({"pos": global_position, "f": facing.angle(), "age": 0.0})
		_ghost_acc = GHOST_EVERY
	if _atk_timer <= 0.0:
		state = State.FREE
		_pop_visual(Vector2(0.85, 1.15))


func _start_attack(name: String) -> void:
	state = State.ATTACK
	_atk_name = name
	_atk_phase = "windup"
	_atk_timer = ATTACKS[name]["windup"]
	_atk_dur = _atk_timer
	_atk_hit_done = false
	velocity = Vector2.ZERO
	_walk_amp = 0.0
	var s := 1.25 if name == "heavy" else 1.12
	_pop_visual(Vector2(s, 2.0 - s))   # scale-pulse windup


func _do_attack(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0 * delta)
	_atk_timer -= delta
	if _atk_timer > 0.0:
		return
	var a: Dictionary = ATTACKS[_atk_name]
	match _atk_phase:
		"windup":
			_atk_phase = "active"
			_atk_timer = a["active"]
			_atk_dur = _atk_timer
		"active":
			if not _atk_hit_done:
				_resolve_hit(a)
				_atk_hit_done = true
			_atk_phase = "recovery"
			_atk_timer = a["recovery"]
			_atk_dur = _atk_timer
		"recovery":
			state = State.FREE
			_atk_name = ""


func _atk_progress() -> float:
	if _atk_dur <= 0.0:
		return 1.0
	return clampf(1.0 - _atk_timer / _atk_dur, 0.0, 1.0)


func _resolve_hit(a: Dictionary) -> void:
	if boss == null or not is_instance_valid(boss):
		boss = get_tree().get_first_node_in_group("boss")
	if boss == null or not boss.has_method("take_hit"):
		return
	var to_boss: Vector2 = boss.global_position - global_position
	if to_boss.length() > a["reach"] + 40.0:   # +40 rough boss radius
		return
	if rad_to_deg(abs(facing.angle_to(to_boss))) > a["arc_deg"] * 0.5:
		return
	boss.take_hit(a["dmg"], global_position)
	Game.hit_stop(a["hitstop"])
	_request_shake(a["shake"])
	if a["punch"] > 0.0:
		_request_punch(a["punch"])
	_pop_visual(Vector2(0.8, 1.2))
	var contact: Vector2 = global_position + to_boss.normalized() * a["reach"]
	_burst(contact, Game.PALE_JADE, 8 if _atk_name == "light" else 16)


func take_hit(amount: int, from_pos: Vector2) -> void:
	if invulnerable or hp <= 0:
		return
	hp -= amount
	_flash = 0.18
	invulnerable = true
	velocity = (global_position - from_pos).normalized() * 340.0
	_pop_visual(Vector2(1.3, 0.75))
	_request_shake(9.0)
	_request_punch(1.06)
	Game.hit_stop(0.06)
	_burst(global_position, Game.PALE_JADE, 14)
	hit_taken.emit()
	health_changed.emit(hp, MAX_HP)
	get_tree().create_timer(0.45).timeout.connect(func(): invulnerable = false)
	if hp <= 0:
		died.emit()
		set_physics_process(false)


func _pop_visual(target: Vector2) -> void:
	_visual = target
	var tw := create_tween()
	tw.tween_property(self, "_visual", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _request_shake(amount: float) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("add_shake"):
		main.add_shake(amount)


func _request_punch(zoom_scale: float) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("punch"):
		main.punch(zoom_scale)


func _burst(pos: Vector2, col: Color, n := 10) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("spawn_burst"):
		main.spawn_burst(pos, col, n)


func _clamp_to_arena() -> void:
	var m := get_tree().current_scene
	if m and "arena_rect" in m:
		var r: Rect2 = m.arena_rect
		global_position.x = clampf(global_position.x, r.position.x, r.end.x)
		global_position.y = clampf(global_position.y, r.position.y, r.end.y)


# --- rig: 8 parts in a "facing = +X" local frame -----------------------
func _p(x: float, y: float, f: float) -> Vector2:
	return Vector2(x, y).rotated(f)


func _draw() -> void:
	# afterimages first, in world-offset space, untouched by the squash transform
	for g in _ghosts:
		var a: float = (1.0 - float(g.age) / GHOST_LIFE) * 0.4
		var off: Vector2 = g.pos - global_position
		var gc := Color(Game.SAPPHIRE_CORE, a)
		draw_circle(off + Vector2(14, 0).rotated(g.f), 8, gc)
		_capsule(off + Vector2(-8, 0).rotated(g.f), off + Vector2(6, 0).rotated(g.f), 12, gc)

	var col := Game.PALE_JADE if _flash > 0.0 else Game.SAPPHIRE_CORE
	var f := facing.angle()

	# walk bounce: perpendicular squash + tiny hop
	var sq := _visual
	var hop := 0.0
	if _walk_amp > 0.0:
		var w := sin(_walk * 2.0) * 0.06 * _walk_amp
		sq *= Vector2(1.0 - w, 1.0 + w)
		hop = -absf(sin(_walk)) * 3.0 * _walk_amp
	draw_set_transform(Vector2(0, hop), 0.0, sq)

	# legs (trailing), back arm, torso, front (sword) arm, head
	_capsule(_p(-7, -7, f), _p(-17, -9, f), 5, col)
	_capsule(_p(-7, 7, f), _p(-17, 9, f), 5, col)
	_capsule(_p(0, -12, f), _p(6, -20, f), 4, col)
	_capsule(_p(-8, 0, f), _p(6, 0, f), 13, col)

	# sword arm + sword; blade sweeps during the active window
	var swing := 0.0
	if state == State.ATTACK:
		match _atk_phase:
			"windup":    swing = lerpf(0.0, -0.7, _atk_progress())
			"active":    swing = lerpf(-0.7, 0.8, _atk_progress())
			"recovery":  swing = lerpf(0.8, 0.0, _atk_progress())
	var hand := _p(11, 14, f)
	_capsule(_p(2, 11, f), hand, 4, col)

	var reach := 64.0
	if state == State.ATTACK:
		reach = float(ATTACKS[_atk_name]["reach"]) * (0.55 if _atk_phase == "windup" else 1.0)
	var bf := f + swing
	var grip_a := hand
	var grip_b := hand + Vector2(14, 0).rotated(bf)
	var tip := hand + Vector2(reach, 0).rotated(bf)
	draw_line(grip_a, grip_b, Game.DEEP_MOSS, 7.0)
	draw_line(hand + Vector2(9, 0).rotated(bf), tip, Game.PALE_JADE, 6.0)

	draw_circle(_p(14, 0, f), 9, col)

	# active swing arc flash (blade sweep, Pale Jade)
	if state == State.ATTACK and _atk_phase == "active":
		var a: Dictionary = ATTACKS[_atk_name]
		var half := deg_to_rad(float(a["arc_deg"]) * 0.5)
		draw_arc(Vector2.ZERO, float(a["reach"]), f - half, f + half, 24, Game.PALE_JADE, 4.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)
