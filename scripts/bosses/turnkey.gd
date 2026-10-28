extends "res://scripts/bosses/boss_base.gd"
## The Turnkey (cell I). A small locked core ringed by six floating keys. While
## the keys circle it the core is shielded and the sword bounces off; it can
## only be hurt while the keys are away attacking or drifting back.
##
## Wall: the keys line up in a row with one gap and march across the floor.
## Volley: the keys fire at the player one by one, each lighting up first.
## Lock: the keys ring the player and close in.
## Phase 2: everything faster, and a wall is always followed by a volley.
##
## global_position is the core's point on the floor; core and keys float LIFT
## above their floor points. Timer: the core's inner diamond.

enum S { IDLE, TELEGRAPH, ATTACK, RECOVER }

const KEYS := 6
const ORBIT := 92.0
const KEY_HIT := 30.0
const LIFT := 74.0
const MOVE := 60.0
const ATK := {
	"wall":   {"windup": 0.95, "active": 1.5, "recover": 1.6},
	"volley": {"windup": 0.6, "active": 2.0, "recover": 1.4},
	"lock":   {"windup": 0.95, "active": 0.8, "recover": 1.6},
}
const WALL_SPEED := 520.0
const WALL_GAP := 60.0
const VOLLEY_EVERY := 0.24
const KEY_SPEED := 900.0
const LOCK_R := 175.0

var state := S.IDLE
var kind := ""
var keys: Array[Vector2] = []      # floor points
var _target: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _flying: Array[bool] = []
var _timer := 0.0
var _total := 1.0
var _wait := 1.6
var _spin := 0.0
var _aim := Vector2.DOWN
var _origin := Vector2.ZERO
var _gap := 3
var _fired := 0
var _fire_t := 0.0
var _hit_done := false
var _chain := ""


func _ready() -> void:
	max_hp = 12
	super()
	for i in KEYS:
		keys.append(global_position + Vector2(ORBIT, 0).rotated(TAU * i / KEYS))
		_target.append(keys[i])
		_vel.append(Vector2.ZERO)
		_flying.append(false)


func _can_be_hit() -> bool:
	return state == S.ATTACK or state == S.RECOVER


func _think(delta: float) -> void:
	_spin += delta * (1.2 if phase == 1 else 2.0)
	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > 240.0 else velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_orbit()
			_wait -= delta
			if _wait <= 0.0:
				_begin(_chain if _chain != "" else ["wall", "volley", "lock"].pick_random())
		S.TELEGRAPH:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			if kind == "lock":
				_origin = _origin.lerp(player_pos(), delta * 2.0)   # the ring tracks you until it closes
				_ring(LOCK_R)
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_attack(delta)
		S.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_orbit()
			_timer -= delta
			if _timer <= 0.0:
				state = S.IDLE
				_wait = randf_range(0.5, 1.0) if phase == 2 else randf_range(0.9, 1.5)

	# keys ease toward their formation; fired keys fly on their own
	var ease_k := 1.0 - exp(-(10.0 if state != S.RECOVER else 3.0) * delta)
	for i in KEYS:
		if _flying[i]:
			keys[i] += _vel[i] * delta
		else:
			keys[i] = keys[i].lerp(_target[i], ease_k)
	move_and_slide()
	global_position = clamp_floor(global_position)


func _begin(k: String) -> void:
	_chain = ""
	kind = k
	state = S.TELEGRAPH
	_total = spd(ATK[k]["windup"])
	_timer = _total
	_aim = (player_pos() - global_position).normalized()
	_hit_done = false
	telegraph(k)
	match k:
		"wall":
			# a row of seven slots across the aim, one left empty
			_origin = global_position + _aim * 70.0
			_gap = randi_range(1, 5)
			var n := Vector2(-_aim.y, _aim.x)
			var slot := 0
			for i in KEYS:
				if slot == _gap:
					slot += 1
				_target[i] = _origin + n * (slot - 3) * WALL_GAP
				slot += 1
		"volley":
			for i in KEYS:
				_target[i] = global_position + Vector2(60.0, 0).rotated(TAU * i / KEYS + _spin)
		"lock":
			_origin = player_pos()


func _activate() -> void:
	state = S.ATTACK
	_total = ATK[kind]["active"]
	_timer = _total
	_fired = 0
	_fire_t = 0.0
	_request_shake(5.0)


func _attack(delta: float) -> void:
	_timer -= delta
	match kind:
		"wall":
			for i in KEYS:
				_target[i] += _aim * WALL_SPEED * delta
				keys[i] = _target[i]
		"volley":
			_fire_t -= delta
			if _fire_t <= 0.0 and _fired < KEYS:
				for n in (2 if phase == 2 else 1):
					if _fired < KEYS:
						_flying[_fired] = true
						_vel[_fired] = (player_pos() - keys[_fired]).normalized() * KEY_SPEED
						_fired += 1
				_fire_t = spd(VOLLEY_EVERY)
		"lock":
			var prog := 1.0 - clampf(_timer / _total, 0.0, 1.0)
			_ring(lerpf(LOCK_R, 14.0, ease(prog, 2.2)))
			for i in KEYS:
				keys[i] = _target[i]
	if not _hit_done:
		for k in keys:
			if player_pos().distance_to(k) < KEY_HIT:
				hurt_player(1, k)
				_hit_done = true
				break
	if _timer <= 0.0:
		state = S.RECOVER
		_timer = spd(ATK[kind]["recover"])
		for i in KEYS:
			_flying[i] = false
		if phase == 2 and kind == "wall":
			_chain = "volley"


func _orbit() -> void:
	for i in KEYS:
		_target[i] = global_position + Vector2(ORBIT, 0).rotated(_spin + TAU * i / KEYS)


func _ring(r: float) -> void:
	for i in KEYS:
		_target[i] = _origin + Vector2(r, 0).rotated(_spin * 0.5 + TAU * i / KEYS)


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := death_scale() if dead else 1.0
	if s <= 0.0:
		return
	var bob := sin(_t * 2.0) * 6.0

	# telegraphs lie on the floor
	if state == S.TELEGRAPH or (state == S.ATTACK and kind == "lock"):
		match kind:
			"wall":
				var n := Vector2(-_aim.y, _aim.x)
				var reach := WALL_SPEED * ATK["wall"]["active"]
				for slot in 7:
					if slot == _gap:
						continue
					var a := _origin + n * (slot - 3.5) * WALL_GAP
					var b := a + n * WALL_GAP
					draw_colored_polygon(PackedVector2Array([L(a), L(b), L(b + _aim * reach), L(a + _aim * reach)]),
						Color(Game.PALE_JADE, 0.08 + 0.2 * eye_t))
			"lock":
				draw_arc(L(_origin), LOCK_R if state == S.TELEGRAPH else _target[0].distance_to(_origin),
					0, TAU, 48, warn_color(), 4.0)
	if state == S.ATTACK and kind == "volley" and _fired < KEYS:
		draw_line(L(keys[_fired]) + Vector2(0, -LIFT * 0.3), L(player_pos()), warn_color(1.0 - _fire_t / spd(VOLLEY_EVERY)), 3.0)

	# keys: shadow on the floor, key floating above it
	for i in KEYS:
		var p := L(keys[i])
		draw_set_transform(p, 0.0, Vector2(s, s))
		draw_colored_polygon(Game.ellipse(12, 4), Color(Game.DEEP_MOSS, 0.5))
		var dir := _vel[i].normalized() if _flying[i] else Vector2.DOWN.rotated(_spin + i)
		_key(Vector2(0, -LIFT + bob * 0.6), dir)
	draw_set_transform(Vector2.ZERO)

	# core: shadow, diamond, shield ring while the keys guard it
	draw_set_transform(Vector2.ZERO, 0.0, _visual * s)
	_shadow(26, 8)
	var c := Vector2(0, -LIFT - 10 + bob)
	if not _can_be_hit():
		draw_arc(c, 34, 0, TAU, 32, Color(Game.SAPPHIRE_CORE, 0.7), 3.0)
	draw_colored_polygon(_diamond(c, 26, 32), body_color())
	draw_colored_polygon(_diamond(c + Vector2(-6, -6), 12, 14), Color(Game.SAPPHIRE_CORE, 0.35))
	draw_colored_polygon(_diamond(c, 11 + 4 * eye_t, 13 + 4 * eye_t), eye_color())
	draw_set_transform(Vector2.ZERO)


## A key: round bow with a hole, a shaft along `dir`, a two-tooth bit.
func _key(at: Vector2, dir: Vector2) -> void:
	var col := body_color()
	var n := Vector2(-dir.y, dir.x)
	draw_circle(at, 10, col)
	draw_circle(at, 4, Game.DEEP_MOSS)
	var tip := at + dir * 34
	draw_line(at + dir * 8, tip, col, 6.0)
	draw_line(tip - dir * 4, tip - dir * 4 + n * 9, col, 5.0)
	draw_line(tip - dir * 12, tip - dir * 12 + n * 7, col, 5.0)
