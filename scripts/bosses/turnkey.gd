extends "res://scripts/bosses/boss_base.gd"
## The Turnkey (cell I). A small locked core ringed by six floating keys. The
## core is shielded; the fight is about opening it with the rapier.
##
## Picking the lock: a thrust that hits a key knocks it out for KNOCK_TIME.
##   With PICKS_TO_OPEN keys out, the shield breaks for OPEN_TIME.
## Parry: a thrust on a key flying at you (Volley) sends it back into the
##   core: 1 damage and a stagger, with the shield open while it recovers.
## The shield is also open while the keys drift home after an attack.
##
## Attacks
##   Wall: the keys line up with a gap and march, stop as a barrier for 2 s
##     (a ricochet bounces off it), then march on. Knocked-out keys leave gaps.
##   Volley: keys fire at the player one by one; each can be parried.
##   Lock: a ring of keys closes on the player in two pulsed stages. Escape it
##     (blink, ricochet) and it recasts once where you land; thrust a key out
##     to open a gap instead.
##   Blades (phase 2+): the keys become a fan of swords slashing back and forth
##     while the core advances on the player.
##   Combination (phase 3): four keys spin like a dial around the core. A key
##     glows when it lines up between the core and the player; thrusting it
##     then breaks the shield. Unaligned thrusts glance off. The dial
##     alternates with the other attacks.
##
## Health 25: phase 2 at 18, phase 3 at 10. global_position is the core's
## point on the floor; core and keys float LIFT above their floor points.
## Timer: the core's inner diamond.

enum S { IDLE, TELEGRAPH, ATTACK, RECOVER }
enum K { ORBIT, FORM, FLY, BACK, KNOCK, DIAL }

const KEYS := 6
const ORBIT := 92.0
const KEY_HIT := 30.0            # key against the player
const KEY_R := 16.0              # key size for thrusts and ricochets
const LIFT := 74.0
const MOVE := 60.0
const CONTACT_CD := 0.8

const ATK := {
	"wall":   {"windup": 0.95, "recover": 1.6},
	"volley": {"windup": 0.6, "recover": 1.4},
	"lock":   {"windup": 0.95, "recover": 1.6},
	"blades": {"windup": 0.7, "recover": 1.4},
	"dial":   {"windup": 0.8, "recover": 1.0},
}
const WALL_SPEED := 520.0
const WALL_GAP := 60.0
const WALL_MARCH := 0.55         # march, then stand as a barrier, then march again
const WALL_HOLD := 2.0
const WALL_MARCH2 := 1.0
const VOLLEY_EVERY := 0.24
const KEY_SPEED := 900.0
const PARRY_SPEED := 1100.0
const PARRY_STAGGER := 1.2
const LOCK_STAGES := [175.0, 110.0, 40.0]
const LOCK_WARN := 0.4           # pulse before each step in
const LOCK_SHRINK := 0.18
const BLADE_R := 125.0
const BLADE_SPEED := 200.0
const BLADE_TIME := 2.4
const KNOCK_TIME := 4.0
const KNOCK_SPEED := 420.0
const PICKS_TO_OPEN := 3
const OPEN_TIME := 3.0
const DIAL_R := 300.0
const DIAL_SPIN := 0.9
const DIAL_TIME := 6.0
const DIAL_KEYS := 4
const ALIGN := 0.25              # radians either side of the core-to-player line

var state := S.IDLE
var kind := ""
var keys: Array[Vector2] = []    # floor points
var _target: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _mode: Array[int] = []
var _ktime: Array[float] = []
var _timer := 0.0
var _total := 1.0
var _elapsed := 0.0
var _wait := 1.6
var _spin := 0.0
var _aim := Vector2.DOWN
var _origin := Vector2.ZERO
var _gap := 3
var _fire_t := 0.0
var _contact := 0.0
var _open_t := 0.0               # shield broken: by picking, parrying or the dial
var _chain := ""
var _recast := false             # the Lock already followed the player once
var _ring := 175.0               # Lock ring radius right now
var _dial_ang := 0.0
var _last := ""


func _ready() -> void:
	max_hp = 25
	phase_hp = [18, 10]
	super()
	for i in KEYS:
		keys.append(global_position + Vector2(ORBIT, 0).rotated(TAU * i / KEYS))
		_target.append(keys[i])
		_vel.append(Vector2.ZERO)
		_mode.append(K.ORBIT)
		_ktime.append(0.0)


func _can_be_hit() -> bool:
	return _open_t > 0.0 or state == S.RECOVER


# --- the player's rapier against the keys -----------------------------
## Called for every thrust and blink line. Knocks keys out, parries flying
## ones, and turns the dial when a key is aligned.
func on_thrust(a: Vector2, b: Vector2, width: float) -> void:
	var dir := (b - a).normalized()
	for i in KEYS:
		if _mode[i] == K.KNOCK or _mode[i] == K.BACK:
			continue
		var q := Geometry2D.get_closest_point_to_segment(keys[i], a, b)
		if q.distance_to(keys[i]) > width * 0.5 + KEY_R:
			continue
		match _mode[i]:
			K.FLY:
				# parried: back it goes, into the core
				_mode[i] = K.BACK
				_vel[i] = (global_position - keys[i]).normalized() * PARRY_SPEED
				_burst(keys[i], Game.SAPPHIRE_CORE, 10)
				_request_shake(6.0)
				sfx("parry")
			K.DIAL:
				if _aligned(i):
					_open_t = OPEN_TIME
					_knock(i, dir)
					_end_attack()
				else:
					_burst(keys[i], Game.SAPPHIRE_CORE, 4)    # glances off
			_:
				_knock(i, dir)


## Solid keys bounce a ricochet: the Wall's barrier.
func deflects(p: Vector2, r: float) -> Vector2:
	if kind != "wall" or (state != S.ATTACK and state != S.TELEGRAPH):
		return Vector2.ZERO
	for i in KEYS:
		if _mode[i] == K.FORM and p.distance_to(keys[i]) < KEY_R + r:
			return (p - keys[i]).normalized()
	return Vector2.ZERO


func _knock(i: int, dir: Vector2) -> void:
	_mode[i] = K.KNOCK
	_vel[i] = dir * KNOCK_SPEED
	_ktime[i] = KNOCK_TIME
	_burst(keys[i], Game.SAPPHIRE_CORE, 8)
	_request_shake(4.0)
	sfx("knock")
	var out := 0
	for k in KEYS:
		if _mode[k] == K.KNOCK:
			out += 1
	if out >= PICKS_TO_OPEN and _open_t <= 0.0:
		# lock picked: the shield breaks, and the picked keys stay out with it
		_open_t = OPEN_TIME
		for k in KEYS:
			if _mode[k] == K.KNOCK:
				_ktime[k] = maxf(_ktime[k], OPEN_TIME)
		_request_shake(10.0)
		sfx("unlock")


func _aligned(i: int) -> bool:
	var to_key := keys[i] - global_position
	var to_p := player_pos() - global_position
	return absf(to_key.angle_to(to_p)) < ALIGN


# --- behaviour ---------------------------------------------------------
func _think(delta: float) -> void:
	_spin += delta * (1.2 if phase == 1 else 2.0)
	_open_t = maxf(0.0, _open_t - delta)
	_contact = maxf(0.0, _contact - delta)
	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > 240.0 else velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_wait -= delta
			if _wait <= 0.0:
				_begin(_chain if _chain != "" else _pick())
		S.TELEGRAPH:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			if kind == "lock":
				_origin = _origin.lerp(player_pos(), delta * 2.0)   # the ring follows you until it starts closing
				_ring = LOCK_STAGES[0]
				_ring_targets()
			elif kind == "blades":
				_aim = (player_pos() - global_position).normalized()
				_blade_targets(0.0)
			if _timer <= 0.0:
				state = S.ATTACK
				_elapsed = 0.0
				_fire_t = 0.0
				sfx(kind)
				_request_shake(5.0)
		S.ATTACK:
			_elapsed += delta
			_attack(delta)
		S.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_timer -= delta
			if _timer <= 0.0:
				state = S.IDLE
				_wait = randf_range(0.5, 1.0) if phase >= 2 else randf_range(0.9, 1.5)
	_keys(delta)
	_contacts()
	move_and_slide()
	global_position = clamp_floor(global_position)


func _pick() -> String:
	var pool := ["wall", "volley", "lock"]
	if phase >= 2:
		pool.append("blades")
	if phase >= 3:
		# the dial alternates with everything else
		if _last != "dial":
			return "dial"
	return pool.pick_random()


func _begin(k: String) -> void:
	_chain = ""
	kind = k
	_last = k
	state = S.TELEGRAPH
	_total = 0.5 if (k == "lock" and _recast) else spd(ATK[k]["windup"])
	_timer = _total
	_aim = (player_pos() - global_position).normalized()
	telegraph(k)
	var free := _free_keys()
	match k:
		"wall":
			# a row of seven slots across the aim, one left empty; knocked keys
			# leave more gaps
			_origin = global_position + _aim * 70.0
			_gap = randi_range(1, 5)
			var n := Vector2(-_aim.y, _aim.x)
			var slot := 0
			for i in free:
				if slot == _gap:
					slot += 1
				_mode[i] = K.FORM
				_target[i] = _origin + n * (slot - 3) * WALL_GAP
				slot += 1
		"volley":
			for j in free.size():
				var i: int = free[j]
				_mode[i] = K.FORM
				_target[i] = global_position + Vector2(60.0, 0).rotated(TAU * j / maxi(free.size(), 1) + _spin)
		"lock":
			_origin = player_pos()      # a recast centres on wherever the player landed
			for i in free:
				_mode[i] = K.FORM
		"blades":
			for i in free:
				_mode[i] = K.FORM
		"dial":
			var n := 0
			for i in free:
				if n < DIAL_KEYS:
					_mode[i] = K.DIAL
					n += 1
			_dial_ang = (player_pos() - global_position).angle()


func _free_keys() -> Array:
	var out := []
	for i in KEYS:
		if _mode[i] != K.KNOCK and _mode[i] != K.BACK:
			out.append(i)
	return out


func _attack(delta: float) -> void:
	match kind:
		"wall":
			var t := _elapsed
			var marching := t < WALL_MARCH or t > WALL_MARCH + WALL_HOLD
			for i in KEYS:
				if _mode[i] == K.FORM and marching:
					_target[i] += _aim * WALL_SPEED * delta
			if t >= WALL_MARCH + WALL_HOLD + WALL_MARCH2:
				_end_attack()
		"volley":
			_fire_t -= delta
			if _fire_t <= 0.0:
				var shots := 2 if phase >= 2 else 1
				for i in KEYS:
					if shots == 0:
						break
					if _mode[i] == K.FORM:
						_mode[i] = K.FLY
						_vel[i] = (player_pos() - keys[i]).normalized() * KEY_SPEED
						shots -= 1
				sfx("fire")
				_fire_t = spd(VOLLEY_EVERY)
			var waiting := false
			for i in KEYS:
				if _mode[i] == K.FORM or _mode[i] == K.FLY or _mode[i] == K.BACK:
					waiting = true
			if not waiting or _elapsed > 3.0:
				_end_attack()
		"lock":
			# two steps in, each announced by a pulse: 175 -> 110 -> 40
			var step := LOCK_WARN + LOCK_SHRINK
			var s := int(_elapsed / step)
			if s < LOCK_STAGES.size() - 1:
				var f := clampf((_elapsed - s * step - LOCK_WARN) / LOCK_SHRINK, 0.0, 1.0)
				_ring = lerpf(LOCK_STAGES[s], LOCK_STAGES[s + 1], f)
			else:
				_ring = LOCK_STAGES[-1]
			_ring_targets()
			if _elapsed >= step * (LOCK_STAGES.size() - 1) + 0.2:
				if not _recast and player_pos().distance_to(_origin) > LOCK_STAGES[0]:
					# escaped by blink or ricochet: it comes for you once more
					_recast = true
					_end_attack()
					state = S.IDLE
					_begin("lock")
					return
				_recast = false
				_end_attack()
		"blades":
			# advance on the player, turning to face them, keys slashing
			var to := (player_pos() - global_position).normalized()
			_aim = _aim.slerp(to, delta * 3.0)
			velocity = _aim * BLADE_SPEED
			_blade_targets(_elapsed)
			if _elapsed >= BLADE_TIME:
				velocity = Vector2.ZERO
				_end_attack()
		"dial":
			velocity = Vector2.ZERO
			_dial_ang += DIAL_SPIN * delta
			if _elapsed >= DIAL_TIME:
				_end_attack()


func _ring_targets() -> void:
	var i := 0
	for k in KEYS:
		if _mode[k] == K.FORM:
			_target[k] = _origin + Vector2(_ring, 0).rotated(_spin * 0.5 + TAU * i / KEYS)
		i += 1


## The fan of key-blades in front of the core, swinging as one.
func _blade_targets(t: float) -> void:
	var blades: Array = []
	for k in KEYS:
		if _mode[k] == K.FORM:
			blades.append(k)
	var swing := sin(t * TAU * 1.4) * 0.9
	for j in blades.size():
		var spread := (j - (blades.size() - 1) * 0.5) * 0.24
		_target[blades[j]] = global_position + Vector2(BLADE_R + 16.0 * absf(j - (blades.size() - 1) * 0.5), 0).rotated(_aim.angle() + spread + swing)


func _end_attack() -> void:
	state = S.RECOVER
	_timer = spd(ATK[kind]["recover"])
	for i in KEYS:
		if _mode[i] == K.FORM or _mode[i] == K.DIAL or _mode[i] == K.FLY:
			_mode[i] = K.ORBIT
	if phase >= 2 and kind == "wall":
		_chain = "volley"


## Every key moves by its mode.
func _keys(delta: float) -> void:
	var dial: Array = []
	for i in KEYS:
		if _mode[i] == K.DIAL:
			dial.append(i)
	for i in KEYS:
		match _mode[i]:
			K.ORBIT:
				_target[i] = global_position + Vector2(ORBIT, 0).rotated(_spin + TAU * i / KEYS)
				keys[i] = keys[i].lerp(_target[i], 1.0 - exp(-4.0 * delta))
			K.FORM:
				var hard := kind == "wall" and state == S.ATTACK
				keys[i] = _target[i] if hard else keys[i].lerp(_target[i], 1.0 - exp(-12.0 * delta))
			K.FLY:
				keys[i] += _vel[i] * delta
				if keys[i].distance_to(global_position) > 1400.0:
					_mode[i] = K.ORBIT
			K.BACK:
				_vel[i] = (global_position - keys[i]).normalized() * PARRY_SPEED
				keys[i] += _vel[i] * delta
				if keys[i].distance_to(global_position) < 36.0:
					# the parried key strikes its own lock
					_mode[i] = K.ORBIT
					take_hit(1, keys[i], true)
					if not dead:
						_open_t = maxf(_open_t, PARRY_STAGGER)
						if state != S.RECOVER:
							state = S.RECOVER
							_timer = PARRY_STAGGER
							for k in KEYS:
								if _mode[k] == K.FORM or _mode[k] == K.DIAL:
									_mode[k] = K.ORBIT
			K.KNOCK:
				keys[i] += _vel[i] * delta
				_vel[i] *= exp(-3.0 * delta)
				_ktime[i] -= delta
				if _ktime[i] <= 0.0:
					_mode[i] = K.ORBIT
			K.DIAL:
				var j := dial.find(i)
				_target[i] = global_position + Vector2(DIAL_R, 0).rotated(_dial_ang + TAU * j / maxi(dial.size(), 1))
				keys[i] = keys[i].lerp(_target[i], 1.0 - exp(-6.0 * delta))


## Keys that are attacking hurt on touch; orbiting and knocked-out keys don't.
func _contacts() -> void:
	if _contact > 0.0:
		return
	for i in KEYS:
		var live := (_mode[i] == K.FORM and state == S.ATTACK) or _mode[i] == K.FLY or _mode[i] == K.DIAL
		if live and player_pos().distance_to(keys[i]) < KEY_HIT:
			hurt_player(1, keys[i])
			_contact = CONTACT_CD
			return


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := death_scale() if dead else 1.0
	if s <= 0.0:
		return
	var bob := sin(_t * 2.0) * 6.0

	# telegraphs on the floor
	if state == S.TELEGRAPH or state == S.ATTACK:
		match kind:
			"wall":
				if state == S.TELEGRAPH:
					var n := Vector2(-_aim.y, _aim.x)
					var reach := WALL_SPEED * (WALL_MARCH + WALL_MARCH2)
					for slot in 7:
						if slot == _gap:
							continue
						var a := _origin + n * (slot - 3.5) * WALL_GAP
						var b := a + n * WALL_GAP
						draw_colored_polygon(PackedVector2Array([L(a), L(b), L(b + _aim * reach), L(a + _aim * reach)]),
							Color(Game.PALE_JADE, 0.08 + 0.2 * eye_t))
			"lock":
				# the ring, with a bright pulse before each step in
				var step := LOCK_WARN + LOCK_SHRINK
				var into := fmod(_elapsed, step) if state == S.ATTACK else 0.0
				var pulse := 1.0 if (state == S.ATTACK and into < LOCK_WARN and int(into * 10.0) % 2 == 0) else 0.0
				draw_arc(L(_origin), _ring, 0, TAU, 48, warn_color(maxf(eye_t, pulse)), 4.0 + 3.0 * pulse)
			"blades":
				if state == S.TELEGRAPH:
					var pts := PackedVector2Array([Vector2.ZERO])
					for k in 13:
						pts.append(Vector2(BLADE_R + 60.0, 0).rotated(_aim.angle() - 1.2 + 2.4 * k / 12.0))
					draw_colored_polygon(pts, warn_color())
			"dial":
				draw_arc(Vector2.ZERO, DIAL_R, 0, TAU, 64, Color(Game.SAPPHIRE_CORE, 0.35), 2.0)

	# keys: shadow on the floor, key floating above it
	for i in KEYS:
		var p := L(keys[i])
		var out := _mode[i] == K.KNOCK
		var glow := _mode[i] == K.DIAL and _aligned(i)
		draw_set_transform(p, 0.0, Vector2(s, s))
		draw_colored_polygon(Game.ellipse(12, 4), Color(Game.DEEP_MOSS, 0.5))
		var dir := Vector2.DOWN.rotated(_spin + i)
		match _mode[i]:
			K.FLY, K.BACK:
				dir = _vel[i].normalized()
			K.KNOCK:
				dir = Vector2.DOWN.rotated(_t * 9.0 + i)        # tumbling
			K.FORM:
				if kind == "blades":
					dir = (keys[i] - global_position).normalized()  # blade points outward
		if glow:
			draw_arc(Vector2(0, -LIFT + bob * 0.6), 22.0, 0, TAU, 24, Game.PALE_JADE, 4.0)
		_key(Vector2(0, -LIFT + bob * 0.6), dir, Color(Game.SAPPHIRE_CORE, 0.6) if out else body_color())
	draw_set_transform(Vector2.ZERO)

	# core: shadow, diamond, shield ring while it's locked
	draw_set_transform(kick(), 0.0, _visual * s)
	_shadow(26, 8)
	var c := Vector2(0, -LIFT - 10 + bob)
	if not _can_be_hit():
		draw_arc(c, 34, 0, TAU, 32, Color(Game.SAPPHIRE_CORE, 0.7), 3.0)
	draw_colored_polygon(_diamond(c, 26, 32), body_color())
	draw_colored_polygon(_diamond(c + Vector2(-6, -6), 12, 14), Color(Game.SAPPHIRE_CORE, 0.35))
	draw_colored_polygon(_diamond(c, 11 + 4 * eye_t, 13 + 4 * eye_t), eye_color())
	draw_set_transform(Vector2.ZERO)


## A key: round bow with a hole, a shaft along `dir`, a two-tooth bit.
func _key(at: Vector2, dir: Vector2, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_circle(at, 10, col)
	draw_circle(at, 4, Game.DEEP_MOSS)
	var tip := at + dir * 34
	draw_line(at + dir * 8, tip, col, 6.0)
	draw_line(tip - dir * 4, tip - dir * 4 + n * 9, col, 5.0)
	draw_line(tip - dir * 12, tip - dir * 12 + n * 7, col, 5.0)
