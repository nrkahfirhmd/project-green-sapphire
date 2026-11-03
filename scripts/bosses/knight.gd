extends "res://scripts/bosses/boss_base.gd"
## The Fallen Knight (the prologue): the tutorial's sparring partner. He is
## the player from the other dream, so his body is the player's own rig
## (player.gd) on a puppet, a little taller and dimmed toward Deep Moss.
##
## He deals no damage: the spar can't be lost, only learned from. A thrust
## that would have landed still knocks the player back and shakes the room.
##
## One attack, slow and fair: he walks in, winds up a thrust down a strip
## that grows in front of him (the strip and his body brightening are the
## timer), strikes, then stands open in a long recovery to be punished.
## Phase 2 (half health) winds up faster and sometimes thrusts twice.
##
## Until `fighting` is set he only stands and watches; the sword glances off.
## Beaten, he doesn't shatter: he stays where he stands, and the prologue
## fades him out once he has said his piece.

enum S { IDLE, WINDUP, STRIKE, RECOVER }

const PLAYER := "res://scripts/player.gd"
const SIZE := 1.15
const MOVE := 130.0
const KEEP := 150.0              # walks in until this close
const WINDUP := 0.8
const RECOVER := 0.75
const REACH := 190.0
const WIDTH := 64.0

# player.gd's State enum
const P_FREE := 0
const P_ATTACK := 2

var fighting := false
var state := S.IDLE
var rig: CharacterBody2D
var _aim := Vector2.DOWN
var _timer := 0.0
var _total := 1.0
var _cd := 1.2                   # until the next thrust
var _again := false              # phase 2's second thrust is queued
var _look_col := Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, 0.55)   # a dimmer twin of the player


func _ready() -> void:
	max_hp = 16                  # past the ultimate's cost, so it charges before he falls
	super()
	rig = CharacterBody2D.new()
	rig.set_script(load(PLAYER))
	add_child(rig)
	# its _ready joins the "player" group; it must not be mistaken for the player
	rig.remove_from_group("player")
	rig.set_physics_process(false)
	rig.scale = Vector2(SIZE, SIZE)
	rig.body_color = _look_col


func _can_be_hit() -> bool:
	return fighting


func _physics_process(delta: float) -> void:
	super(delta)
	var face := (player_pos() - global_position).normalized() if state == S.IDLE else _aim
	rig.global_position = global_position + kick()
	if face != Vector2.ZERO:
		rig.facing = face
		if absf(face.x) > 0.15:
			rig._face_x = signf(face.x)
	var moving := velocity.length() > 20.0 and not dead
	rig._idle_t += delta
	rig._walk_amp = move_toward(rig._walk_amp, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		rig._walk += delta * 11.0
	rig.body_color = Game.PALE_JADE if _flash > 0.0 else body_color()
	rig.queue_redraw()


## Dimmed at rest; blooms toward Jade only over the end of a windup.
func body_color() -> Color:
	return _look_col.lerp(Game.PALE_JADE, clampf((eye_t - 0.6) / 0.4, 0.0, 1.0))


func _think(delta: float) -> void:
	if not fighting:
		eye_t = 0.0
		velocity = Vector2.ZERO
		move_and_slide()
		return
	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > KEEP else velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			_cd -= delta
			if _cd <= 0.0 and to.length() < KEEP + 80.0:
				_windup()
		S.WINDUP:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			_pose_attack("windup", _total - _timer, _total)
			if _timer <= 0.0:
				_strike()
		S.STRIKE:
			_timer -= delta
			_pose_attack("active", 0.12 - _timer, 0.12)
			if _timer <= 0.0:
				state = S.RECOVER
				_total = spd(RECOVER)
				_timer = _total
		S.RECOVER:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			_timer -= delta
			_pose_attack("recovery", _total - _timer, _total)
			if _timer <= 0.0:
				if _again:
					_again = false
					_windup()
				else:
					_idle()
	move_and_slide()
	global_position = clamp_floor(global_position)


func _windup() -> void:
	state = S.WINDUP
	_total = spd(WINDUP)
	_timer = _total
	_aim = (player_pos() - global_position).normalized()
	telegraph("thrust")


func _strike() -> void:
	state = S.STRIKE
	_timer = 0.12
	_request_shake(8.0)
	Sfx.play("mirror_heavy")             # the Mirror's echoed swing: he is a reflection too
	var q := Geometry2D.get_closest_point_to_segment(player_pos(), global_position, global_position + _aim * REACH * SIZE)
	if q.distance_to(player_pos()) <= WIDTH * SIZE * 0.5 + 16.0 and player and not player.invulnerable:
		player.velocity = _aim * 420.0           # caught: shoved, never hurt
		_burst(player_pos(), Game.SAPPHIRE_CORE, 10)
		_request_shake(6.0)
		Haptics.play("blocked")
		Sfx.play("blocked")
	if phase == 2 and not _again and randf() < 0.5:
		_again = true


func _idle() -> void:
	state = S.IDLE
	rig.state = P_FREE
	_cd = randf_range(0.6, 1.2) if phase == 2 else randf_range(1.0, 1.8)


func _cancel() -> void:
	_again = false
	_idle()


func _pose_attack(ph: String, elapsed: float, total: float) -> void:
	rig.state = P_ATTACK
	rig._atk_name = "heavy"
	rig._atk_phase = ph
	rig._atk_dur = total
	rig._atk_timer = maxf(0.0, total - elapsed)


## Beaten: no shatter, no shrink. He stays standing for the last words.
func _shatter(_delta: float) -> void:
	rig.state = P_FREE


## The rig casts its own shadow; this only adds the telegraph under it.
func _draw() -> void:
	# the strip he is about to thrust down, growing as he winds up
	if state == S.WINDUP:
		var reach := REACH * SIZE * (0.5 + 0.5 * eye_t)
		var side := Vector2(-_aim.y, _aim.x) * WIDTH * SIZE * 0.5
		var b := _aim * reach
		draw_colored_polygon(PackedVector2Array([side, b + side, b - side, -side]), warn_color())
