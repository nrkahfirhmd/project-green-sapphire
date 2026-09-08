extends CharacterBody2D
## The Prism. Floats. State machine: IDLE -> TELEGRAPH -> ATTACK -> RECOVER.
## 3 attacks (slam cone, ring pulse, charge dash). Phase 2 at 50% HP:
## faster timings + can chain two attacks. Eye color is the windup timer.

signal died
signal health_changed(current: int, max: int)
signal phase_changed(phase: int)
signal telegraph_started(kind: String)

const MAX_HP := 12
const PHASE2_AT := 6

const RADIUS := 46.0                 # body half-width, for hit math
const MOVE_SPEED := 70.0             # slow drift toward player when idle

# Per-attack tuning. Phase 2 multiplies windup/recover by PHASE2_SPEED.
const PHASE2_SPEED := 0.62
const ATK := {
	"slam":   {"windup": 0.95, "active": 0.28, "recover": 0.75, "dmg": 1, "reach": 300.0, "arc_deg": 72.0},
	"ring":   {"windup": 1.05, "active": 0.55, "recover": 0.70, "dmg": 1, "r_from": 40.0, "r_to": 540.0, "band": 34.0},
	"charge": {"windup": 0.90, "active": 0.45, "recover": 0.85, "dmg": 1, "speed": 1250.0, "hit_dist": 62.0},
}

enum State { IDLE, TELEGRAPH, ATTACK, RECOVER, DEAD }

var hp := MAX_HP
var phase := 1
var state: State = State.IDLE
var _t := 0.0                        # generic phase timer
var _idle_wait := 0.0
var _kind := ""
var _aim := Vector2.DOWN             # locked aim at telegraph start
var _ring_r := 0.0
var _hit_done := false
var _chain_left := 0
var _flash := 0.0
var _visual := Vector2.ONE
var _bob := 0.0
var _eye_t := 0.0                    # 0..1 telegraph progress, drives eye color

@onready var player: Node = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	add_to_group("boss")
	health_changed.emit(hp, MAX_HP)
	_idle_wait = 1.6


func _physics_process(delta: float) -> void:
	_bob += delta
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	match state:
		State.IDLE:     _do_idle(delta)
		State.TELEGRAPH: _do_telegraph(delta)
		State.ATTACK:    _do_attack(delta)
		State.RECOVER:   _do_recover(delta)
		State.DEAD:      velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)

	move_and_slide()
	queue_redraw()


func _spd(v: float) -> float:
	return v * (PHASE2_SPEED if phase == 2 else 1.0)


func _do_idle(delta: float) -> void:
	_eye_t = 0.0
	if player and is_instance_valid(player):
		var to_p: Vector2 = player.global_position - global_position
		velocity = to_p.normalized() * MOVE_SPEED if to_p.length() > 180.0 else velocity.move_toward(Vector2.ZERO, 300.0 * delta)
	_idle_wait -= delta
	if _idle_wait <= 0.0:
		_begin_telegraph(_pick_attack())


func _pick_attack() -> String:
	var keys := ATK.keys()
	return keys[randi() % keys.size()]


func _begin_telegraph(kind: String) -> void:
	state = State.TELEGRAPH
	_kind = kind
	_t = _spd(ATK[kind]["windup"])
	_eye_t = 0.0
	_hit_done = false
	velocity = Vector2.ZERO
	if player and is_instance_valid(player):
		_aim = (player.global_position - global_position).normalized()
	telegraph_started.emit(kind)
	_pop_visual(Vector2(0.86, 1.16))


func _do_telegraph(delta: float) -> void:
	var total := _spd(ATK[_kind]["windup"])
	_t -= delta
	_eye_t = clampf(1.0 - _t / total, 0.0, 1.0)
	# subtle lean toward aim as it charges
	velocity = _aim * 18.0
	if _t <= 0.0:
		_begin_active()


func _begin_active() -> void:
	state = State.ATTACK
	_t = ATK[_kind]["active"]
	_eye_t = 1.0
	_ring_r = float(ATK[_kind].get("r_from", 0.0))
	_pop_visual(Vector2(1.22, 0.8))
	_request_shake(6.0)
	if _kind == "charge":
		velocity = _aim * ATK["charge"]["speed"]


func _do_attack(delta: float) -> void:
	_t -= delta
	match _kind:
		"slam":
			if not _hit_done:
				_try_cone_hit()
				_hit_done = true
		"ring":
			var a: Dictionary = ATK["ring"]
			var prog := 1.0 - clampf(_t / float(a["active"]), 0.0, 1.0)
			_ring_r = lerpf(float(a["r_from"]), float(a["r_to"]), prog)
			_try_ring_hit()
		"charge":
			velocity = _aim * ATK["charge"]["speed"]
			_try_charge_hit()
			_bounce_walls()
	if _t <= 0.0:
		state = State.RECOVER
		_t = _spd(ATK[_kind]["recover"])
		velocity = Vector2.ZERO


func _do_recover(delta: float) -> void:
	_eye_t = maxf(0.0, _eye_t - delta * 3.0)
	velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_t -= delta
	if _t <= 0.0:
		if _chain_left > 0:
			_chain_left -= 1
			_begin_telegraph(_pick_attack())
		else:
			state = State.IDLE
			_idle_wait = randf_range(0.5, 1.1) if phase == 2 else randf_range(0.9, 1.6)
			# phase 2: sometimes queue a 2-attack chain
			if phase == 2 and randf() < 0.5:
				_chain_left = 1


# --- hit resolution (pure geometry) -----------------------------------
func _player_pos() -> Vector2:
	return player.global_position if (player and is_instance_valid(player)) else global_position + Vector2(9999, 0)


func _hurt_player(dmg: int) -> void:
	if player and is_instance_valid(player) and player.has_method("take_hit"):
		player.take_hit(dmg, global_position)


func _try_cone_hit() -> void:
	var a: Dictionary = ATK["slam"]
	var to_p := _player_pos() - global_position
	if to_p.length() <= a["reach"] and rad_to_deg(abs(_aim.angle_to(to_p))) <= a["arc_deg"] * 0.5:
		_hurt_player(a["dmg"])
	_request_shake(14.0)


func _try_ring_hit() -> void:
	if _hit_done:
		return
	var a: Dictionary = ATK["ring"]
	var d := (_player_pos() - global_position).length()
	if absf(d - _ring_r) <= a["band"]:
		_hurt_player(a["dmg"])
		_hit_done = true


func _try_charge_hit() -> void:
	if _hit_done:
		return
	if (_player_pos() - global_position).length() <= ATK["charge"]["hit_dist"]:
		_hurt_player(ATK["charge"]["dmg"])
		_hit_done = true
		_request_shake(10.0)


func _bounce_walls() -> void:
	var m := get_tree().current_scene
	if m and "arena_rect" in m:
		var r: Rect2 = m.arena_rect
		if global_position.x < r.position.x or global_position.x > r.end.x:
			_aim.x = -_aim.x
		if global_position.y < r.position.y or global_position.y > r.end.y:
			_aim.y = -_aim.y
		global_position.x = clampf(global_position.x, r.position.x, r.end.x)
		global_position.y = clampf(global_position.y, r.position.y, r.end.y)


# --- damage in --------------------------------------------------------
func take_hit(amount: int, from_pos: Vector2) -> void:
	if state == State.DEAD:
		return
	hp = max(0, hp - amount)
	_flash = 0.12
	velocity += (global_position - from_pos).normalized() * 120.0
	_pop_visual(Vector2(1.18, 0.84))
	_burst(from_pos.lerp(global_position, 0.7), Game.SAPPHIRE_CORE, 12)
	health_changed.emit(hp, MAX_HP)

	if phase == 1 and hp <= PHASE2_AT and hp > 0:
		phase = 2
		phase_changed.emit(2)
		_request_shake(18.0)
		Game.hit_stop(0.12)

	if hp <= 0:
		state = State.DEAD
		velocity = Vector2.ZERO
		died.emit()


func _pop_visual(target: Vector2) -> void:
	_visual = target
	var tw := create_tween()
	tw.tween_property(self, "_visual", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _request_shake(amount: float) -> void:
	var m := get_tree().current_scene
	if m and m.has_method("add_shake"):
		m.add_shake(amount)


func _burst(pos: Vector2, col: Color, n := 10) -> void:
	var m := get_tree().current_scene
	if m and m.has_method("spawn_burst"):
		m.spawn_burst(pos, col, n)


# --- draw ------------------------------------------------------------
func _eye_color() -> Color:
	# Deep Moss -> Sapphire Core -> Pale Jade across the windup
	if _eye_t < 0.5:
		return Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, _eye_t * 2.0)
	return Game.SAPPHIRE_CORE.lerp(Game.PALE_JADE, (_eye_t - 0.5) * 2.0)


func _draw() -> void:
	var body_col := Game.PALE_JADE if _flash <= 0.0 else Color.WHITE
	var bob_y := sin(_bob * 1.5) * 6.0
	draw_set_transform(Vector2(0, bob_y), sin(_bob * 0.7) * 0.03, _visual)

	# telegraph shapes first (under body), Pale Jade, alpha rising with _eye_t
	if state == State.TELEGRAPH or state == State.ATTACK:
		_draw_telegraph()

	# arms (capsules) + 3-capsule hands
	_capsule(Vector2(-30, -34), Vector2(-70, 20), 7, body_col)
	_capsule(Vector2(30, -34), Vector2(70, 20), 7, body_col)
	for i in 3:
		var ang := deg_to_rad(-30 + i * 30)
		_capsule(Vector2(-70, 20), Vector2(-70, 20) + Vector2(16, 0).rotated(ang + PI * 0.5), 3, body_col)
		_capsule(Vector2(70, 20), Vector2(70, 20) + Vector2(16, 0).rotated(ang + PI * 0.5), 3, body_col)

	# body: inverted triangle
	var pts := PackedVector2Array([Vector2(-58, -48), Vector2(58, -48), Vector2(0, 96)])
	draw_colored_polygon(pts, body_col)
	# facet shadow (Sapphire Core, soft)
	var facet := PackedVector2Array([Vector2(-30, -30), Vector2(30, -30), Vector2(0, 34)])
	draw_colored_polygon(facet, Game.SAPPHIRE_CORE * Color(1, 1, 1, 0.4))
	# eye: diamond, color = windup timer
	var e := 16.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -22 - e), Vector2(e, -22), Vector2(0, -22 + e), Vector2(-e, -22)
	]), _eye_color())

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_telegraph() -> void:
	var a: float = 0.25 + 0.55 * _eye_t
	var col := Color(Game.PALE_JADE.r, Game.PALE_JADE.g, Game.PALE_JADE.b, a)
	match _kind:
		"slam":
			var half: float = deg_to_rad(float(ATK["slam"]["arc_deg"]) * 0.5)
			var reach: float = float(ATK["slam"]["reach"])
			if state == State.TELEGRAPH:
				reach *= 0.4 + 0.6 * _eye_t
			var base := _aim.angle()
			var poly := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				poly.append(Vector2(reach, 0).rotated(base - half + (2.0 * half) * i / 12.0))
			draw_colored_polygon(poly, col)
		"ring":
			if state == State.TELEGRAPH:
				draw_arc(Vector2.ZERO, ATK["ring"]["r_to"] * _eye_t, 0, TAU, 64, col, 3.0 + 4.0 * _eye_t)
			else:
				draw_arc(Vector2.ZERO, _ring_r, 0, TAU, 64, Game.PALE_JADE, 8.0)
		"charge":
			var len := ATK["charge"]["speed"] * ATK["charge"]["active"]
			var w := 60.0
			var d := _aim
			var n := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([
				n * w, n * w + d * len, -n * w + d * len, -n * w
			]), col)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)
