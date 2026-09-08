extends CharacterBody2D
## The Swordsman. Move (8-dir), dodge roll (i-frames + afterimage trail),
## light/heavy attack (one shared system, different numbers).
## Code-driven rig: 9 parts, oriented to facing, animated with tweens.

signal died
signal health_changed(current: int, max: int)
signal hit_taken

const MAX_HP := 4
const SPEED := 260.0

const DODGE_SPEED := 620.0
const DODGE_TIME := 0.18
const DODGE_IFRAME_TIME := 0.20
const DODGE_COOLDOWN := 0.5

const RIG := 1.5               # rig scale; boss body is ~144 tall, bible wants 2:1
const OUTLINE := 3.0           # Deep Moss backing width; keeps overlapping parts readable

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
var _idle_t := 0.0           # idle-breathing phase
var _roll := 0.0             # dodge-roll spin, radians

@onready var boss: Node = get_tree().get_first_node_in_group("boss")


func _ready() -> void:
	add_to_group("player")
	health_changed.emit(hp, MAX_HP)


func _physics_process(delta: float) -> void:
	_dodge_cd = max(0.0, _dodge_cd - delta)
	_idle_t += delta
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
	_roll = 0.0
	_pop_visual(Vector2(1.35, 0.7))   # stretch along travel
	_burst(global_position, Game.SAPPHIRE_CORE, 8)
	get_tree().create_timer(DODGE_IFRAME_TIME).timeout.connect(func(): invulnerable = false)


func _do_dodge(delta: float) -> void:
	_atk_timer -= delta
	_roll = (1.0 - clampf(_atk_timer / DODGE_TIME, 0.0, 1.0)) * TAU
	velocity = velocity.move_toward(facing * SPEED, 1400.0 * delta)
	_ghost_acc -= delta
	if _ghost_acc <= 0.0:
		_ghosts.append({"pos": global_position, "f": facing.angle(), "age": 0.0})
		_ghost_acc = GHOST_EVERY
	if _atk_timer <= 0.0:
		state = State.FREE
		_roll = 0.0
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


# --- rig: 9 parts in a "facing = +X" local frame -----------------------
func _p(x: float, y: float, f: float) -> Vector2:
	return Vector2(x * RIG, y * RIG).rotated(f)


## Sword-arm angle relative to facing: settle at rest, wind back, sweep through.
func _swing_angle() -> float:
	if state != State.ATTACK:
		return 0.18 + sin(_idle_t * 2.2) * 0.06
	var p := _atk_progress()
	match _atk_phase:
		"windup":
			return lerpf(0.18, -1.25, ease(p, 1.8))
		"active":
			return lerpf(-1.25, 1.35, ease(p, 0.45))
		_:
			return lerpf(1.35, 0.18, ease(p, 0.7))


func _draw() -> void:
	var f := facing.angle()

	# afterimages first, in world-offset space, untouched by the body transform
	for g in _ghosts:
		var a: float = (1.0 - float(g.age) / GHOST_LIFE) * 0.35
		var off: Vector2 = g.pos - global_position
		var gf: float = g.f
		var gc := Color(Game.SAPPHIRE_CORE, a)
		_capsule(off + _p(-20, 0, gf), off + _p(-2, 0, gf), 9 * RIG, gc)
		draw_circle(off + _p(8, 0, gf), 10 * RIG, gc)

	var col := Game.PALE_JADE if _flash > 0.0 else Game.SAPPHIRE_CORE

	# body transform: idle breathing, walk squash + hop, dodge-roll spin, hurt jitter
	var sq := _visual
	var hop := 0.0
	var spin := 0.0
	var breathe := 1.0 + sin(_idle_t * 2.4) * 0.022 * (1.0 - _walk_amp)
	sq *= Vector2(breathe, 2.0 - breathe)
	if _walk_amp > 0.0:
		var w := sin(_walk * 2.0) * 0.06 * _walk_amp
		sq *= Vector2(1.0 - w, 1.0 + w)
		hop = -absf(sin(_walk)) * 4.0 * _walk_amp
	if state == State.DODGE:
		spin = _roll                       # full turn over the roll: a top-down tumble
		sq *= Vector2(1.06, 0.86)
	var jitter := Vector2.ZERO
	if _flash > 0.0:
		var j := _flash * 14.0
		jitter = Vector2(randf_range(-j, j), randf_range(-j, j))
	draw_set_transform(Vector2(0, hop) + jitter, spin, sq)

	# legs: alternating stride along the facing axis, so the walk actually steps
	var stride := sin(_walk) * 10.0 * _walk_amp
	_capsule_o(_p(-16, -8, f), _p(-24 + stride, -10, f), 5.5 * RIG, col)
	_capsule_o(_p(-16, 8, f), _p(-24 - stride, 10, f), 5.5 * RIG, col)

	# off arm: counter-swings against the legs
	var sh_b := _p(0, -20, f)
	_capsule_o(sh_b, _p(12 - stride * 0.8, -34, f), 4.5 * RIG, col)

	# torso, then a shoulder bar across it. The bar is what gives the rig a
	# humanoid T from straight above; the head then sits on top of it.
	_capsule_o(_p(-20, 0, f), _p(-2, 0, f), 9 * RIG, col)
	var sh_f := _p(0, 20, f)
	_capsule_o(sh_b, sh_f, 7.5 * RIG, col)

	# sword arm + greatsword: Deep Moss grip, Pale Jade blade of 2 triangles
	var swing := _swing_angle()
	var hand := sh_f + _p(16, 6, f).rotated(swing)
	_capsule_o(sh_f, hand, 5.0 * RIG, col)

	var reach := 62.0 * RIG
	if state == State.ATTACK:
		reach = float(ATTACKS[_atk_name]["reach"]) * (0.5 if _atk_phase == "windup" else 0.85)
	var bf := f + swing
	var dir := Vector2(1, 0).rotated(bf)
	var nrm := Vector2(-dir.y, dir.x)
	var guard := hand + dir * 14.0 * RIG
	var tip := hand + dir * reach
	var hw := 9.0 * RIG
	draw_colored_polygon(PackedVector2Array([
		guard - nrm * (hw + OUTLINE), guard + nrm * (hw + OUTLINE), tip + dir * OUTLINE
	]), Game.DEEP_MOSS)
	_capsule(hand - dir * 7.0 * RIG, guard, 5.0 * RIG + OUTLINE, col)
	_capsule(hand - dir * 7.0 * RIG, guard, 5.0 * RIG, Game.DEEP_MOSS)
	draw_colored_polygon(PackedVector2Array([guard - nrm * hw, guard, tip]), Game.PALE_JADE)
	draw_colored_polygon(PackedVector2Array([guard, guard + nrm * hw, tip]), Color(Game.PALE_JADE, 0.82))

	# head last, so it reads as one clean circle on top of the shoulders
	_circle_o(_p(8, 0, f), 10 * RIG, col)
	draw_circle(_p(15, 0, f), 3.0 * RIG, Game.DEEP_MOSS)

	# active swing arc flash (blade sweep, Pale Jade), fading as it passes
	if state == State.ATTACK and _atk_phase == "active":
		var a: Dictionary = ATTACKS[_atk_name]
		var half := deg_to_rad(float(a["arc_deg"]) * 0.5)
		var t := _atk_progress()
		draw_arc(Vector2.ZERO, float(a["reach"]), f - half, f + half, 24,
			Color(Game.PALE_JADE, 1.0 - t * 0.6), 5.0 - t * 3.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


## Capsule on a Deep Moss backing. Drawn back-to-front, these outlines are what
## keep the limbs from merging into one silhouette when viewed from straight above.
func _capsule_o(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	_capsule(a, b, r + OUTLINE, Game.DEEP_MOSS)
	_capsule(a, b, r, col)


func _circle_o(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + OUTLINE, Game.DEEP_MOSS)
	draw_circle(c, r, col)
