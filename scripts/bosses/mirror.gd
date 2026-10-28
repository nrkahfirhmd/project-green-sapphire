extends "res://scripts/bosses/boss_base.gd"
## The Mirror (gate V, the final boss). A giant Pale Jade reflection of the
## Swordsman that copies the player: every attack the player starts, it
## replays a moment later, aimed back at them, and every dodge it echoes as a
## roll. Between echoes it winds up its own great swing. Spam one move and you
## are fighting yourself.
##
## Phase 2: it splits. A decoy circles to the player's far side and copies
## every move; only the real one has the diamond on its face, and only the real
## one can be hurt. Every few seconds they swap places.
##
## The body is the player's own rig (player.gd) on a puppet that never runs its
## own physics; this script poses it. global_position is the real one's feet.
## Timer: the face diamond.

enum S { IDLE, WINDUP, STRIKE, RECOVER, ROLL }

const PLAYER := "res://scripts/player.gd"
const SIZE := 1.9
const ECHO_DELAY := 0.8
const MOVE := 150.0
const KEEP := 190.0
const ROLL_SPEED := 700.0
const GREAT := {"reach": 125.0, "arc_deg": 170.0}
const SWAP_EVERY := 7.0
# player.gd's State enum: FREE, DODGE, ATTACK
const P_FREE := 0
const P_DODGE := 1
const P_ATTACK := 2

var state := S.IDLE
var real: CharacterBody2D
var decoy: CharacterBody2D
var _decoy_at := Vector2.ZERO
var _atk := "light"
var _aim := Vector2.DOWN
var _timer := 0.0
var _total := 1.0
var _queued := ""
var _great_cd := 3.0
var _seen := P_FREE
var _roll_dir := Vector2.DOWN
var _swap_cd := SWAP_EVERY
var _eye: Node2D


func _ready() -> void:
	max_hp = 16
	super()
	real = _puppet()
	_eye = Node2D.new()
	_eye.draw.connect(_draw_eye)
	add_child(_eye)
	phase_changed.connect(_split)


func _puppet() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.set_script(load(PLAYER))
	add_child(p)
	# its _ready joins the "player" group; it must not be mistaken for the player
	p.remove_from_group("player")
	p.set_physics_process(false)
	p.scale = Vector2(SIZE, SIZE)
	p.body_color = Game.PALE_JADE
	return p


func _can_be_hit() -> bool:
	return state != S.ROLL


func _split(_p: int) -> void:
	decoy = _puppet()
	move_child(_eye, -1)
	_decoy_at = clamp_floor(player_pos() * 2.0 - global_position)
	_burst(_decoy_at, Game.PALE_JADE, 18)


func _physics_process(delta: float) -> void:
	super(delta)
	var face := (player_pos() - global_position).normalized()
	var moving := velocity.length() > 20.0
	_pose(real, global_position, face if state == S.IDLE else _aim, delta, moving)
	real.body_color = Game.SAPPHIRE_CORE if _flash > 0.0 else Game.PALE_JADE
	if decoy:
		_pose(decoy, _decoy_at, (player_pos() - _decoy_at).normalized() if state == S.IDLE else _aim, delta, moving)
	if dead:
		for p in [real, decoy]:
			if p:
				p.scale = Vector2.ONE * SIZE * death_scale()
	_eye.position = Vector2(real._face_x * 4.0, -113.0 - absf(sin(real._walk)) * 3.0 * real._walk_amp)
	_eye.visible = not dead
	_eye.queue_redraw()


func _think(delta: float) -> void:
	# watch the player: every attack and dodge they start gets echoed
	if player and is_instance_valid(player) and "state" in player:
		var ps: int = player.state
		if ps != _seen:
			if ps == P_ATTACK:
				_queued = player._atk_name
			elif ps == P_DODGE:
				_queued = "dodge"
				_roll_dir = player.facing
			_seen = ps

	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > KEEP else velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			_great_cd -= delta
			if _queued == "dodge":
				_roll()
			elif _queued != "":
				_windup(_queued, ECHO_DELAY)
			elif _great_cd <= 0.0:
				_windup("great", spd(0.9))
				_great_cd = randf_range(2.5, 3.5) if phase == 2 else randf_range(3.5, 5.0)
		S.WINDUP:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			_set_attack_phase("windup", _total - _timer, _total)
			if _timer <= 0.0:
				_strike()
		S.STRIKE:
			_timer -= delta
			_set_attack_phase("active", 0.12 - _timer, 0.12)
			if _timer <= 0.0:
				state = S.RECOVER
				_total = 0.6 if _atk == "great" else 0.4
				_timer = _total
		S.RECOVER:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			_timer -= delta
			_set_attack_phase("recovery", _total - _timer, _total)
			if _timer <= 0.0:
				state = S.IDLE
				real.state = P_FREE
				if decoy:
					decoy.state = P_FREE
		S.ROLL:
			_timer -= delta
			velocity = _roll_dir * ROLL_SPEED
			var prog := 1.0 - clampf(_timer / 0.3, 0.0, 1.0)
			for p in [real, decoy]:
				if p:
					p.state = P_DODGE
					p._roll = prog * TAU
			if _timer <= 0.0:
				state = S.IDLE
				for p in [real, decoy]:
					if p:
						p.state = P_FREE
						p._roll = 0.0

	move_and_slide()
	global_position = clamp_floor(global_position)

	if decoy:
		# the decoy keeps to the player's far side, and now and then they swap
		var want := clamp_floor(player_pos() + (player_pos() - global_position).normalized() * KEEP)
		if state == S.IDLE:
			_decoy_at = _decoy_at.move_toward(want, MOVE * delta)
		elif state == S.ROLL:
			_decoy_at = clamp_floor(_decoy_at - _roll_dir * ROLL_SPEED * delta)
		_swap_cd -= delta
		if _swap_cd <= 0.0 and state == S.IDLE:
			_swap_cd = SWAP_EVERY
			_burst(global_position, Game.PALE_JADE, 14)
			_burst(_decoy_at, Game.PALE_JADE, 14)
			var here := global_position
			global_position = _decoy_at
			_decoy_at = here


func _windup(atk: String, t: float) -> void:
	_queued = ""
	_atk = atk
	state = S.WINDUP
	_total = t
	_timer = t
	_aim = (player_pos() - global_position).normalized()
	telegraph(atk)


func _roll() -> void:
	_queued = ""
	state = S.ROLL
	_timer = 0.3


func _strike() -> void:
	state = S.STRIKE
	_timer = 0.12
	var reach := _reach()
	var half := deg_to_rad(_arc() * 0.5)
	_request_shake(10.0 if _atk != "light" else 5.0)
	for from in _bodies():
		var to := player_pos() - from
		if to.length() <= reach and absf(_aim.angle_to(to)) <= half:
			hurt_player(1, from)
			return


func _reach() -> float:
	var base: float = GREAT["reach"] if _atk == "great" else real.ATTACKS[_atk]["reach"]
	return base * SIZE


func _arc() -> float:
	return GREAT["arc_deg"] if _atk == "great" else real.ATTACKS[_atk]["arc_deg"]


func _bodies() -> Array[Vector2]:
	var out: Array[Vector2] = [global_position]
	if decoy:
		out.append(_decoy_at)
	return out


## Drive the puppets' attack animation from this script's timers.
func _set_attack_phase(ph: String, elapsed: float, total: float) -> void:
	for p in [real, decoy]:
		if p:
			p.state = P_ATTACK
			p._atk_name = "heavy" if _atk == "great" else _atk
			p._atk_phase = ph
			p._atk_dur = total
			p._atk_timer = maxf(0.0, total - elapsed)


func _pose(p: CharacterBody2D, at: Vector2, face: Vector2, delta: float, moving: bool) -> void:
	p.global_position = at
	if face != Vector2.ZERO:
		p.facing = face
		if absf(face.x) > 0.15:
			p._face_x = signf(face.x)
	p._idle_t += delta
	p._walk_amp = move_toward(p._walk_amp, 1.0 if moving and state == S.IDLE else 0.0, delta * 6.0)
	if moving:
		p._walk += delta * 12.0
	p.queue_redraw()


# --- draw ------------------------------------------------------------
## The floor sector each body is about to swing through.
func _draw() -> void:
	if state != S.WINDUP:
		return
	var reach := _reach()
	var half := deg_to_rad(_arc() * 0.5)
	for from in _bodies():
		var pts := PackedVector2Array([L(from)])
		for k in 17:
			pts.append(L(from) + Vector2(reach * (0.5 + 0.5 * eye_t), 0).rotated(_aim.angle() - half + 2.0 * half * k / 16.0))
		draw_colored_polygon(pts, Color(Game.PALE_JADE, 0.1 + 0.3 * eye_t))


## The tell: only the real reflection has a diamond on its face.
func _draw_eye() -> void:
	var e := 8.0 + 3.0 * eye_t
	_eye.draw_colored_polygon(PackedVector2Array([Vector2(0, -e * 1.2), Vector2(e, 0), Vector2(0, e * 1.2), Vector2(-e, 0)]), Game.DEEP_MOSS)
	_eye.draw_colored_polygon(PackedVector2Array([Vector2(0, -e), Vector2(e * 0.8, 0), Vector2(0, e), Vector2(-e * 0.8, 0)]), eye_color(maxf(eye_t, 0.35)))
