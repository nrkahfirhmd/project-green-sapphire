extends "res://scripts/bosses/boss_base.gd"
## The Mirror (gate V, the final boss): the final exam. A giant Pale Jade
## reflection of the Swordsman that copies the player's whole kit, then
## recalls each cell's trick, one per phase.
##
## Copies
##   Echo: every thrust the player starts, it repeats after ECHO_DELAY, aimed
##     where the player is heading rather than where they were.
##   Roll: every dodge, echoed as a roll (it can't be hit mid-roll).
##   Ricochet: a second later, it ricochets along the mirror image of the
##     player's path (reflected across the middle of the floor).
##   Blink: it blinks to the mirror point of where the player landed, then
##     cuts toward them.
##   Ultimate: it answers with its own star of cuts through the player.
##   Great thrust: its own move, whenever there's nothing to copy.
## Clash: a player thrust that meets its thrust blade to blade (both strips
##   crossing while its strike lands) knocks both back and cracks it, stunned
##   for CLASH_STUN. CRACKS_TO_SHATTER cracks skip it to its next phase.
##
## Phases (health 52: 44 / 35 / 26 / 17 / 9)
##   1 the copies alone
##   2 memory of the Turnkey: keys orbit and fly at the player. Thrust an
##     orbiting key out (three out stuns it); thrust a flying key back into it.
##   3 memory of the Pendulum: a blade swings from a rail overhead. Riposte it
##     as it reaches you and the Mirror is stunned.
##   4 memory of the Prism: crystal spikes rise around the player, block
##     movement and bounce a ricochet; its beams bend through them.
##   5 memory of the Hourglass: a sand clock drains over its head and ends in
##     Time's Up; a dead-centre thrust while its neck glows flips it.
##   6 Shatter: three shards of it circle the player with the real one, all
##     copying. A shard breaks from one hit and reforms later; only the real
##     one (the face diamond) takes damage.
##
## The body is the player's own rig (player.gd) on puppets this script poses.
## global_position is the real Mirror's feet. Timer: the face diamond.

enum S { IDLE, WINDUP, STRIKE, RECOVER, ROLL, STUN, RICO, BLINK, STAR, TIMESUP }

const PLAYER := "res://scripts/player.gd"
const SIZE := 1.9
const ECHO_DELAY := 0.8
const MOVE := 150.0
const KEEP := 190.0
const ROLL_SPEED := 700.0
const GREAT := {"reach": 170.0, "width": 90.0}
const CLASH_WINDOW := 0.15       # the last moment of its windup counts as meeting it
const CLASH_STUN := 1.5
const CRACKS_TO_SHATTER := 3
const RICO_DELAY := 1.0
const RICO_SPEED := 1100.0
const RICO_TIME := 1.5
const BLINK_WINDUP := 0.35
const BLINK_DIST := 300.0
const BLINK_W := 90.0
const STAR_DELAY := 2.0
const STAR_CUTS := 6
const STAR_EVERY := 0.18
const STAR_WARN := 0.4
const STAR_R := 220.0
const CUT_W := 40.0
# memories
const KEYS := 4
const KEY_ORBIT := 90.0
const KEY_SPEED := 900.0
const KEY_R := 16.0
const KEY_EVERY := 2.5
const KNOCK_TIME := 4.0
const PICK_STUN := 1.5
const PARRY_DMG := 2
const BLADE_ARM := 330.0
const BLADE_HIT := 54.0
const BLADE_REACH := 200.0
const RIPOSTE_STUN := 2.5
const SPIKE_R := 22.0
const SPIKE_EVERY := 3.0
const SPIKE_LIFE := 5.0
const BEAM_EVERY := 4.0
const BEAM_W := 22.0
const CLOCK_TIME := 14.0
const TIMESUP_R := 480.0
const TIMESUP_WINDUP := 1.2
const NECK_R := 24.0
const NECK_AFTER := 1.0
const SHARDS := 3
const SHARD_R := 230.0
const SHARD_SPIN := 0.6
const SHARD_REFORM := 6.0
const SHARD_SWAP := 5.0
# player.gd's State enum
const P_FREE := 0
const P_DODGE := 1
const P_ATTACK := 2
const P_RICOCHET := 3
const P_BLINK := 4
const P_ULT := 5

var state := S.IDLE
var cracks := 0
var real: CharacterBody2D
var _eye: Node2D
var _atk := "light"
var _aim := Vector2.DOWN
var _timer := 0.0
var _total := 1.0
var _queued := ""
var _great_cd := 3.0
var _seen := P_FREE
var _roll_dir := Vector2.DOWN
var _later: Array = []           # ability copies waiting their turn: {kind, t, data}
var _move_dir := Vector2.ZERO    # ricochet direction
var _hit_cd := 0.0
var _cut_from := Vector2.ZERO
var _star_c := Vector2.ZERO
var _star_base := 0.0
var _star_done := 0
var _streaks: Array = []         # {a, b, age}
var _neck_t := 0.0
# memories
var _keys: Array = []            # {p, mode: "orbit"/"fly"/"back"/"out", v, t}
var _key_cd := KEY_EVERY
var _pivot := Vector2.ZERO
var _blade_ang := 0.0
var _blade_t := 0.0
var _blade_stop := 0.0
var _blade_prev := Vector2.ZERO
var _spikes: Array = []          # {p, t, age}
var _spike_cd := SPIKE_EVERY
var _beam_cd := BEAM_EVERY
var _beam_aim := Vector2.ZERO
var _beam_t := 0.0               # >0 while a beam is warning/firing
var _clock := 1.0
var _shards: Array = []          # {pup, slot, alive, t}
var _spin := 0.0
var _swap_cd := SHARD_SWAP


func _ready() -> void:
	max_hp = 52
	phase_hp = [44, 35, 26, 17, 9]
	super()
	real = _puppet()
	_eye = Node2D.new()
	_eye.draw.connect(_draw_eye)
	add_child(_eye)
	phase_changed.connect(_on_phase)


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


## Every new phase brings its memory; cracks start over.
func _on_phase(p: int) -> void:
	cracks = 0
	_keys.clear()
	_spikes.clear()
	_beam_t = 0.0
	var r := arena_rect()
	match p:
		2:
			for i in KEYS:
				_keys.append({"p": global_position, "mode": "orbit", "v": Vector2.ZERO, "t": 0.0})
		3:
			_pivot = Vector2(r.get_center().x, r.position.y + 14.0)
			_blade_t = 0.0
		5:
			_clock = 1.0
		6:
			for i in SHARDS:
				var pup := _puppet()
				_shards.append({"pup": pup, "slot": i + 1, "alive": true, "t": 0.0})
			move_child(_eye, -1)


# --- the rapier against the Mirror --------------------------------------
## Every player thrust and blink line: clash with its strike, pick and parry
## keys, riposte the blade, flip the clock, break shards.
func on_thrust(a: Vector2, b: Vector2, width: float) -> void:
	if dead:
		return
	# clash: blade to blade as its strike lands
	if state == S.STRIKE or (state == S.WINDUP and _timer < CLASH_WINDOW):
		var reach := _reach()
		for from in _bodies():
			var near := Geometry2D.get_closest_points_between_segments(a, b, from, from + _aim * reach)
			if near[0].distance_to(near[1]) <= (width + _width()) * 0.5:
				_clash()
				return
	# the Turnkey's keys
	for k in _keys:
		var q := Geometry2D.get_closest_point_to_segment(k.p, a, b)
		if q.distance_to(k.p) > width * 0.5 + KEY_R:
			continue
		if k.mode == "fly":
			k.mode = "back"
		elif k.mode == "orbit":
			k.mode = "out"
			k.v = (b - a).normalized() * 420.0
			k.t = KNOCK_TIME
			var out := 0
			for kk in _keys:
				if kk.mode == "out":
					out += 1
			if out >= 3:
				_stun(PICK_STUN)
	# the Pendulum's blade
	if phase == 3 and _blade_stop <= 0.0:
		var tip := _blade_tip()
		var q := Geometry2D.get_closest_point_to_segment(tip, a, b)
		if q.distance_to(tip) <= width * 0.5 + 46.0 and tip.distance_to(player_pos()) <= BLADE_REACH:
			_blade_stop = RIPOSTE_STUN
			_stun(RIPOSTE_STUN)
			_burst(tip, Game.PALE_JADE, 16)
	# the Hourglass: dead centre while the neck glows
	if phase == 5 and _neck_t > 0.0:
		var q := Geometry2D.get_closest_point_to_segment(global_position, a, b)
		if q.distance_to(global_position) <= NECK_R:
			_clock = 1.0
			_neck_t = 0.0
			_burst(global_position + Vector2(0, -230), Game.PALE_JADE, 14)
			_stun(1.0)
	# shards break from any hit
	for sh in _shards:
		if sh.alive:
			var pos: Vector2 = sh.pup.global_position
			var q := Geometry2D.get_closest_point_to_segment(pos, a, b)
			if q.distance_to(pos) <= width * 0.5 + 40.0:
				sh.alive = false
				sh.t = SHARD_REFORM
				sh.pup.hide()
				_burst(pos, Game.PALE_JADE, 18)


func _clash() -> void:
	cracks += 1
	_burst(global_position + _aim * 60.0, Game.PALE_JADE, 20)
	_request_shake(14.0)
	Game.hit_stop(0.1)
	velocity = -_aim * 300.0
	if player and is_instance_valid(player):
		player.velocity = (player_pos() - global_position).normalized() * 340.0
	if cracks >= CRACKS_TO_SHATTER:
		# shattered into the next phase early
		var marks := phases()
		if phase - 1 < marks.size():
			take_hit(hp - int(marks[phase - 1]), global_position, true)
	_stun(CLASH_STUN)


func _stun(t: float) -> void:
	state = S.STUN
	_timer = t
	_queued = ""
	velocity = Vector2.ZERO


## Crystal spikes (the Prism's memory) block the player...
func push_out(p: Vector2, r: float) -> Vector2:
	for s in _spikes:
		var c: Vector2 = s.p
		var d := p - c
		if d.length() < SPIKE_R + r:
			p = c + (d.normalized() if d != Vector2.ZERO else Vector2.DOWN) * (SPIKE_R + r)
	return p


## ...and bounce a ricochet.
func deflects(p: Vector2, r: float) -> Vector2:
	for s in _spikes:
		if p.distance_to(s.p) < SPIKE_R + r:
			return (p - (s.p as Vector2)).normalized()
	return Vector2.ZERO


# --- watching the player ---------------------------------------------
func _watch() -> void:
	if not (player and is_instance_valid(player) and "state" in player):
		return
	var ps: int = player.state
	if ps == _seen:
		return
	match ps:
		P_ATTACK:
			_queued = player._atk_name
		P_DODGE:
			_queued = "dodge"
			_roll_dir = player.facing
		P_RICOCHET:
			_later.append({"kind": "rico", "t": RICO_DELAY, "data": {"from": player_pos(), "dir": player._move_dir}})
		P_ULT:
			_later.append({"kind": "star", "t": STAR_DELAY, "data": {}})
	if _seen == P_BLINK and ps != P_BLINK:
		_later.append({"kind": "blink", "t": 0.2, "data": {"to": player_pos()}})
	_seen = ps


## Across the middle of the floor, left to right.
func _mirror_point(p: Vector2) -> Vector2:
	var cx := arena_rect().get_center().x
	return clamp_floor(Vector2(cx * 2.0 - p.x, p.y))


# --- behaviour ---------------------------------------------------------
func _physics_process(delta: float) -> void:
	super(delta)
	var face := (player_pos() - global_position).normalized()
	var moving := velocity.length() > 20.0
	_pose(real, global_position + kick(), face if state == S.IDLE else _aim, delta, moving)
	real.body_color = Game.SAPPHIRE_CORE if _flash > 0.0 else Game.PALE_JADE
	for sh in _shards:
		_pose(sh.pup, sh.pup.global_position, (player_pos() - sh.pup.global_position).normalized() if state == S.IDLE else _aim, delta, moving)
	if dead:
		real.scale = Vector2.ONE * SIZE * death_scale()
		for sh in _shards:
			sh.pup.scale = Vector2.ONE * SIZE * death_scale()
	_eye.position = Vector2(real._face_x * 4.0, -113.0 - absf(sin(real._walk)) * 3.0 * real._walk_amp)
	_eye.visible = not dead
	_eye.queue_redraw()


func _think(delta: float) -> void:
	_watch()
	_hit_cd = maxf(0.0, _hit_cd - delta)
	_neck_t = maxf(0.0, _neck_t - delta)
	for st in _streaks:
		st.age += delta
	_streaks = _streaks.filter(func(st): return st.age < 0.3)
	for l in _later:
		l.t -= delta
	_memories(delta)

	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > KEEP else velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			_great_cd -= delta
			if not _start_later():
				if _queued == "dodge":
					_queued = ""
					state = S.ROLL
					_timer = 0.3
				elif _queued != "":
					_windup(_queued, ECHO_DELAY)
				elif _great_cd <= 0.0:
					_windup("great", spd(0.9))
					_great_cd = randf_range(2.5, 3.5) if phase >= 4 else randf_range(3.5, 5.0)
		S.WINDUP:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			_set_attack("windup", _total - _timer, _total)
			if _timer <= 0.0:
				_strike()
		S.STRIKE:
			_timer -= delta
			_set_attack("active", 0.12 - _timer, 0.12)
			if _timer <= 0.0:
				state = S.RECOVER
				_total = 0.6 if _atk == "great" else 0.4
				_timer = _total
		S.RECOVER:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			_timer -= delta
			_set_attack("recovery", _total - _timer, _total)
			if _timer <= 0.0:
				_idle()
		S.STUN:
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				_idle()
		S.ROLL:
			_timer -= delta
			velocity = _roll_dir * ROLL_SPEED
			_set_roll(1.0 - clampf(_timer / 0.3, 0.0, 1.0))
			if _timer <= 0.0:
				_idle()
		S.RICO:
			_timer -= delta
			_set_roll(fmod(_timer * 4.0, 1.0))
			var p := global_position + _move_dir * RICO_SPEED * delta
			var c := clamp_floor(p)
			if c != p:
				_move_dir = _move_dir.bounce((p - c).normalized())
			global_position = c
			velocity = Vector2.ZERO
			if _hit_cd <= 0.0 and player_pos().distance_to(global_position) < 50.0:
				hurt_player(1)
				_hit_cd = 0.5
			if _timer <= 0.0:
				_idle()
		S.BLINK:
			_timer -= delta
			eye_t = clampf(1.0 - _timer / BLINK_WINDUP, 0.0, 1.0)
			if _timer <= 0.0:
				var to_pt := clamp_floor(global_position + _aim * BLINK_DIST)
				_cut(global_position, to_pt, BLINK_W)
				_idle()
		S.STAR:
			_timer += delta
			var due := int((_timer - STAR_WARN) / STAR_EVERY) + 1
			while _star_done < mini(due, STAR_CUTS) and _timer >= STAR_WARN:
				var line := _star_line(_star_done)
				_cut(line[0], line[1], CUT_W)
				_star_done += 1
			if _star_done >= STAR_CUTS:
				_idle()
		S.TIMESUP:
			_timer -= delta
			eye_t = clampf(1.0 - _timer / TIMESUP_WINDUP, 0.0, 1.0)
			if _timer <= 0.0:
				_request_shake(18.0)
				_burst(global_position, Game.PALE_JADE, 30)
				if player_pos().distance_to(global_position) < TIMESUP_R:
					hurt_player(2)
				_clock = 1.0
				_idle()

	if state != S.RICO:
		move_and_slide()
		global_position = clamp_floor(global_position)


func _idle() -> void:
	state = S.IDLE
	real.state = P_FREE
	real._roll = 0.0
	for sh in _shards:
		sh.pup.state = P_FREE
		sh.pup._roll = 0.0
	_neck_t = NECK_AFTER


## Start the oldest ability copy that's due. True if one started.
func _start_later() -> bool:
	for l in _later:
		if l.t > 0.0:
			continue
		_later.erase(l)
		match l.kind:
			"rico":
				global_position = _mirror_point(l.data.from)
				var d: Vector2 = l.data.dir
				_move_dir = Vector2(-d.x, d.y)
				state = S.RICO
				_timer = RICO_TIME
				_burst(global_position, Game.PALE_JADE, 12)
			"blink":
				global_position = _mirror_point(l.data.to)
				_aim = (player_pos() - global_position).normalized()
				state = S.BLINK
				_timer = BLINK_WINDUP
				telegraph("blink")
				_burst(global_position, Game.PALE_JADE, 12)
			"star":
				_star_c = player_pos()
				_star_base = randf() * TAU
				_star_done = 0
				state = S.STAR
				_timer = 0.0
				telegraph("star")
		return true
	return false


func _star_line(k: int) -> Array:
	var d := Vector2(STAR_R, 0).rotated(_star_base + k * PI * 0.8)
	return [clamp_floor(_star_c + d), clamp_floor(_star_c - d)]


## A cut from a to b: it moves there, leaving a slash, and hurts on the line.
func _cut(a: Vector2, b: Vector2, w: float) -> void:
	global_position = b
	_streaks.append({"a": a, "b": b, "age": 0.0})
	_request_shake(8.0)
	var q := Geometry2D.get_closest_point_to_segment(player_pos(), a, b)
	if q.distance_to(player_pos()) < w * 0.5 + 16.0:
		hurt_player(1, q)


func _windup(atk: String, t: float) -> void:
	_queued = ""
	_atk = atk
	state = S.WINDUP
	_total = t
	_timer = t
	# aim where the player is heading, not where they are
	var lead: Vector2 = player.velocity * t if player and is_instance_valid(player) else Vector2.ZERO
	_aim = (player_pos() + lead - global_position).normalized()
	telegraph(atk)


func _strike() -> void:
	state = S.STRIKE
	_timer = 0.12
	var reach := _reach()
	var half_w := _width() * 0.5
	_request_shake(10.0 if _atk != "light" else 5.0)
	for from in _bodies():
		var q := Geometry2D.get_closest_point_to_segment(player_pos(), from, from + _aim * reach)
		if q.distance_to(player_pos()) <= half_w + 16.0:
			hurt_player(1, from)
			return


func _reach() -> float:
	var base: float = GREAT["reach"] if _atk == "great" else real.ATTACKS[_atk]["reach"]
	return base * SIZE


func _width() -> float:
	var base: float = GREAT["width"] if _atk == "great" else real.ATTACKS[_atk]["width"]
	return base * SIZE


## The real Mirror, plus every shard still standing.
func _bodies() -> Array[Vector2]:
	var out: Array[Vector2] = [global_position]
	for sh in _shards:
		if sh.alive:
			out.append(sh.pup.global_position)
	return out


# --- memories ------------------------------------------------------------
func _memories(delta: float) -> void:
	var c := arena_rect().get_center()
	match phase:
		2:
			_key_cd -= delta
			var fired := false
			for i in _keys.size():
				var k: Dictionary = _keys[i]
				match k.mode:
					"orbit":
						k.p = (k.p as Vector2).lerp(global_position + Vector2(KEY_ORBIT, 0).rotated(_t * 1.5 + TAU * i / KEYS), 1.0 - exp(-6.0 * delta))
						if _key_cd <= 0.0 and not fired:
							k.mode = "fly"
							k.v = (player_pos() - (k.p as Vector2)).normalized() * KEY_SPEED
							fired = true
					"fly":
						k.p = (k.p as Vector2) + (k.v as Vector2) * delta
						if (k.p as Vector2).distance_to(player_pos()) < 30.0 and _hit_cd <= 0.0:
							hurt_player(1, k.p)
							_hit_cd = 0.6
							k.mode = "orbit"
						elif (k.p as Vector2).distance_to(c) > 1400.0:
							k.mode = "orbit"
					"back":
						k.p = (k.p as Vector2).move_toward(global_position, KEY_SPEED * 1.2 * delta)
						if (k.p as Vector2).distance_to(global_position) < 36.0:
							k.mode = "orbit"
							take_hit(PARRY_DMG, k.p, true)
							if not dead:
								_stun(1.0)
					"out":
						k.p = (k.p as Vector2) + (k.v as Vector2) * delta
						k.v = (k.v as Vector2) * exp(-3.0 * delta)
						k.t = float(k.t) - delta
						if float(k.t) <= 0.0:
							k.mode = "orbit"
			if fired:
				_key_cd = KEY_EVERY
		3:
			_blade_stop = maxf(0.0, _blade_stop - delta)
			_pivot.x = clampf(move_toward(_pivot.x, player_pos().x, 90.0 * delta), arena_rect().position.x + 120.0, arena_rect().end.x - 120.0)
			if _blade_stop <= 0.0:
				_blade_t += delta
				_blade_ang = sin(_blade_t * TAU / 2.8) * 1.0
				var tip := _blade_tip()
				var q := Geometry2D.get_closest_point_to_segment(player_pos(), _blade_prev, tip)
				if _hit_cd <= 0.0 and q.distance_to(player_pos()) < BLADE_HIT:
					hurt_player(1, q)
					_hit_cd = 1.0
			_blade_prev = _blade_tip()
		4:
			for s in _spikes:
				s.t = float(s.t) - delta
				s.age = float(s.age) + delta
			_spikes = _spikes.filter(func(s): return float(s.t) > 0.0)
			_spike_cd -= delta
			if _spike_cd <= 0.0:
				_spike_cd = SPIKE_EVERY
				for i in 3:
					var p := clamp_floor(player_pos() + Vector2(randf_range(60.0, 200.0), 0).rotated(randf() * TAU))
					_spikes.append({"p": p, "t": SPIKE_LIFE, "age": 0.0})
			if _beam_t > 0.0:
				_beam_t -= delta
				if _beam_t < 0.4 and _hit_cd <= 0.0 and _beam_hits(_beam(global_position, _beam_aim)):
					hurt_player(1)
					_hit_cd = 1.0
			else:
				_beam_cd -= delta
				if _beam_cd <= 0.0:
					_beam_cd = BEAM_EVERY
					_beam_aim = (player_pos() - global_position).normalized()
					_beam_t = 1.2         # 0.8 warning, then 0.4 firing
		5:
			if state != S.STUN and state != S.TIMESUP:
				_clock = maxf(0.0, _clock - delta / CLOCK_TIME)
				if _clock <= 0.0 and (state == S.IDLE or state == S.RECOVER):
					state = S.TIMESUP
					_timer = TIMESUP_WINDUP
					telegraph("timesup")
		6:
			_spin += SHARD_SPIN * delta
			_swap_cd -= delta
			if _swap_cd <= 0.0 and state == S.IDLE:
				_swap_cd = SHARD_SWAP
				# the real one trades places with a shard
				var live := _shards.filter(func(sh): return sh.alive)
				if not live.is_empty():
					var sh: Dictionary = live.pick_random()
					var here := global_position
					global_position = sh.pup.global_position
					sh.pup.global_position = here
					_burst(here, Game.PALE_JADE, 10)
			for sh in _shards:
				if not sh.alive:
					sh.t = float(sh.t) - delta
					if float(sh.t) <= 0.0:
						sh.alive = true
						sh.pup.show()
				var slot := player_pos() + Vector2(SHARD_R, 0).rotated(_spin + TAU * int(sh.slot) / (SHARDS + 1))
				sh.pup.global_position = (sh.pup.global_position as Vector2).move_toward(clamp_floor(slot), MOVE * 1.5 * delta)


func _blade_tip() -> Vector2:
	var arm := BLADE_ARM + 100.0 * sin(_blade_t * TAU / 4.2)
	return _pivot + Vector2(0, 1).rotated(_blade_ang) * arm


## A beam: straight until the first spike, then split in two either side.
func _beam(o: Vector2, d: Vector2) -> Array:
	var end := o + d * 1600.0
	var hit := Vector2.INF
	var best := INF
	for s in _spikes:
		var sc: Vector2 = s.p
		var q := Geometry2D.get_closest_point_to_segment(sc, o + d * 30.0, end)
		if q.distance_to(sc) < SPIKE_R and (q - o).length() < best:
			best = (q - o).length()
			hit = sc
	if hit == Vector2.INF:
		return [[o, end]]
	return [[o, hit], [hit, hit + d.rotated(-0.45) * 1600.0], [hit, hit + d.rotated(0.45) * 1600.0]]


func _beam_hits(segs: Array) -> bool:
	for sg in segs:
		var q := Geometry2D.get_closest_point_to_segment(player_pos(), sg[0], sg[1])
		if q.distance_to(player_pos()) < BEAM_W * 0.5 + 16.0:
			return true
	return false


# --- posing the puppets -----------------------------------------------
func _set_attack(ph: String, elapsed: float, total: float) -> void:
	for p in _all_puppets():
		p.state = P_ATTACK
		p._atk_name = "heavy" if _atk == "great" else _atk
		p._atk_phase = ph
		p._atk_dur = total
		p._atk_timer = maxf(0.0, total - elapsed)


func _set_roll(f: float) -> void:
	for p in _all_puppets():
		p.state = P_DODGE
		p._roll = f * TAU


func _all_puppets() -> Array:
	var out := [real]
	for sh in _shards:
		out.append(sh.pup)
	return out


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
func _draw() -> void:
	var c := Game.SAPPHIRE_CORE

	# the strip each body is about to thrust through, growing as it winds up
	if state == S.WINDUP:
		var reach := _reach() * (0.5 + 0.5 * eye_t)
		var side := Vector2(-_aim.y, _aim.x) * _width() * 0.5
		for from in _bodies():
			var a := L(from)
			var b := a + _aim * reach
			draw_colored_polygon(PackedVector2Array([a + side, b + side, b - side, a - side]), Color(Game.PALE_JADE, 0.1 + 0.3 * eye_t))
	# copied abilities
	if state == S.BLINK:
		draw_line(Vector2.ZERO, _aim * BLINK_DIST, warn_color(), BLINK_W * (0.3 + 0.7 * eye_t))
	if state == S.STAR:
		for k in STAR_CUTS:
			var t0 := STAR_WARN + k * STAR_EVERY
			if k >= _star_done and _timer > t0 - STAR_WARN:
				var line := _star_line(k)
				draw_line(L(line[0]), L(line[1]), warn_color(clampf(1.0 - (t0 - _timer) / STAR_WARN, 0.0, 1.0)), CUT_W * 0.6)
	if state == S.TIMESUP:
		draw_circle(Vector2.ZERO, TIMESUP_R * (0.6 + 0.4 * eye_t), warn_color())
	for st in _streaks:
		var k: float = 1.0 - float(st.age) / 0.3
		draw_line(L(st.a), L(st.b), Color(Game.PALE_JADE, k), 2.0 + 8.0 * k)
	if real and is_instance_valid(real) and state == S.RICO:
		draw_line(Vector2.ZERO, _move_dir * 120.0, Color(Game.PALE_JADE, 0.6), 4.0)

	# memories
	match phase:
		2:
			for k in _keys:
				var at := L(k.p) + Vector2(0, -70)
				var col := Color(c, 0.6) if k.mode == "out" else Game.PALE_JADE
				var dir := (k.v as Vector2).normalized() if k.mode == "fly" or k.mode == "out" else Vector2.DOWN.rotated(_t * 2.0)
				draw_circle(at, 9, col)
				draw_circle(at, 3.5, Game.DEEP_MOSS)
				draw_line(at + dir * 7, at + dir * 30, col, 5.0)
		3:
			var tip := L(_blade_tip())
			var body := L(_pivot) + Vector2(0, -180)
			draw_line(body, tip + Vector2(0, -26), Game.PALE_JADE, 5.0)
			draw_colored_polygon(_diamond(body, 26, 30), Game.PALE_JADE)
			var along := Vector2(1, 0).rotated(_blade_ang)
			var in_reach := _blade_stop <= 0.0 and _blade_tip().distance_to(player_pos()) <= BLADE_REACH
			var blade := tip + Vector2(0, -26)
			draw_colored_polygon(PackedVector2Array([blade - along * 55, blade + Vector2(0, 30), blade + along * 55, blade + Vector2(0, 12)]), Game.PALE_JADE)
			if in_reach:
				draw_polyline(PackedVector2Array([blade - along * 55, blade + Vector2(0, 30), blade + along * 55]), Game.PALE_JADE, 4.0)
		4:
			for s in _spikes:
				var sc := L(s.p)
				var a := clampf(float(s.age) / 0.2, 0.0, 1.0) * clampf(float(s.t) / 0.5, 0.0, 1.0)
				for k in 3:
					var x := (k - 1) * 11.0
					draw_colored_polygon(PackedVector2Array([sc + Vector2(x - 7, 0), sc + Vector2(x + 7, 0), sc + Vector2(x, -48.0 + absf(k - 1) * 16.0)]), Color(c, 0.8 * a))
			if _beam_t > 0.0:
				var firing := _beam_t < 0.4
				for sg in _beam(global_position, _beam_aim):
					draw_line(L(sg[0]), L(sg[1]), Game.PALE_JADE if firing else warn_color(1.0 - (_beam_t - 0.4) / 0.8), BEAM_W if firing else 2.0)
		5:
			# the clock hangs over its head; the neck glows while a flip is possible
			var o := Vector2(0, -230)
			draw_colored_polygon(PackedVector2Array([o + Vector2(-26, -40), o + Vector2(26, -40), o]), Game.PALE_JADE)
			draw_colored_polygon(PackedVector2Array([o, o + Vector2(26, 40), o + Vector2(-26, 40)]), Game.PALE_JADE)
			var top := _clock
			draw_colored_polygon(PackedVector2Array([o + Vector2(-22 * top, -36 * top), o + Vector2(22 * top, -36 * top), o]), Color(c, 0.85))
			if _neck_t > 0.0:
				draw_arc(o, 12, 0, TAU, 16, Game.PALE_JADE, 3.0)


## The tell: only the real Mirror has a diamond on its face. Cracks from
## clashes show across it.
func _draw_eye() -> void:
	var e := 8.0 + 3.0 * eye_t
	_eye.draw_colored_polygon(PackedVector2Array([Vector2(0, -e * 1.2), Vector2(e, 0), Vector2(0, e * 1.2), Vector2(-e, 0)]), Game.DEEP_MOSS)
	_eye.draw_colored_polygon(PackedVector2Array([Vector2(0, -e), Vector2(e * 0.8, 0), Vector2(0, e), Vector2(-e * 0.8, 0)]), eye_color(maxf(eye_t, 0.35)))
	var lines := [[Vector2(-30, -30), Vector2(10, 20)], [Vector2(25, -25), Vector2(-5, 30)], [Vector2(-35, 10), Vector2(30, 0)]]
	for i in cracks:
		_eye.draw_line(lines[i][0], lines[i][1], Game.DEEP_MOSS, 3.0)
