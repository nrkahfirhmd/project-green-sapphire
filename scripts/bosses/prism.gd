extends "res://scripts/bosses/boss_base.gd"
## The Prism (cell III), the honest duelist: no shield, always hittable, a
## test of fundamentals. Its attacks are light and crystal, and crystal spikes
## it leaves on the floor shape the fight: they block movement, bounce a
## ricochet, bend its beams, and stop its charge dead.
##
## Six phases, a new one every 10 health, alternating what changes:
##   1 base: Slam, Spectrum, Charge, Beam
##   2 adds Shardfall          3 tunes: faster, a fourth Spectrum ring,
##   4 adds Lens                 longer-lived spikes
##   6 adds Refraction         5 tunes: faster still, chained attacks,
##                               beams sweep as they fire
##
## Attacks
##   Slam: a 100 degree cone, reach 300, leaving a line of spikes along it.
##   Spectrum: three (later four) rings in succession, each with one gap a
##     little round from the last, so there's always a path to walk. They come
##     further apart than the dodge's cooldown, so dodging each ring works too.
##   Charge: a dash that bounces off the floor's edge, leaving shards behind.
##     It crashes into any older spike and is stuck there for STUCK_TIME.
##   Beam: the eye fires a straight beam; passing through a spike, it bends
##     and splits in two.
##   Shardfall: shards land on marked spots and become spikes.
##   Lens: a burning spot chases the player, a little slower than they run.
##   Refraction: mid-floor, spinning, three beams in a rotating fan, each
##     bending through every spike it crosses.
##
## global_position is the Prism's point on the floor; the body floats LIFT
## above it. Timer: the eye.

enum S { IDLE, TELEGRAPH, ATTACK, RECOVER, STUCK }

const LIFT := Vector2(0, -104)
const RADIUS := 46.0
const MOVE := 70.0
const TOUCH_CD := 0.6
const CONTACT_CD := 0.8
const SPIKE_R := 22.0
const STUCK_TIME := 1.5
const BLINK_TIME := 0.16

const ATK := {
	"slam":       {"windup": 0.95, "active": 0.28, "recover": 0.75},
	"spectrum":   {"windup": 1.0, "recover": 0.7},
	"charge":     {"windup": 0.9, "active": 0.45, "recover": 0.85},
	"beam":       {"windup": 0.8, "active": 0.5, "recover": 0.7},
	"shardfall":  {"windup": 0.9, "active": 0.2, "recover": 0.7},
	"lens":       {"windup": 0.7, "active": 3.0, "recover": 0.9},
	"refraction": {"windup": 1.0, "active": 4.0, "recover": 1.0},
}
const SLAM_REACH := 300.0
const SLAM_ARC := 100.0
const SLAM_SPIKES := [100.0, 170.0, 240.0, 310.0]
const RING_FROM := 40.0
const RING_TO := 560.0
const RING_TIME := 0.55
const RING_EVERY := 0.6           # > the dodge cooldown (0.5), at every phase
const RING_BAND := 34.0
const RING_GAP := 65.0           # degrees
const GAP_STEP := 70.0           # most a gap moves round from the ring before
const CHARGE_SPEED := 1250.0
const CHARGE_HIT := 62.0
const CHARGE_SHARD_EVERY := 90.0
const BEAM_W := 22.0
const BEAM_SPLIT := 0.45         # radians either side of the beam after a spike
const SHARDS := 5
const SHARD_R := 50.0
const LENS_R := 55.0
const LENS_SPEED := 230.0
const FAN_SPIN := 0.8

var state := S.IDLE
var kind := ""
var _timer := 0.0
var _total := 1.0
var _elapsed := 0.0
var _wait := 1.6
var _aim := Vector2.DOWN
var _hit_done := false
var _touch := 0.0
var _contact := 0.0
var _chain_left := 0
var _arm_t := 0.15               # 0 arms at rest .. 1 raised overhead
var _blink := 0.0
var _blink_cd := 3.0
var _spikes: Array = []          # {p: Vector2, t: life left, age: float}
var _gaps: Array[float] = []     # one gap angle per Spectrum ring
var _ring_hit: Array[bool] = []
var _travel := 0.0
var _spots: Array[Vector2] = []
var _lens := Vector2.ZERO
var _fan := 0.0


func _ready() -> void:
	max_hp = 60
	phase_hp = [50, 40, 30, 20, 10]
	super()


## Odd phases retune: 1-2 base, 3-4 faster, 5-6 fastest with chains and sweeps.
func _tune() -> Dictionary:
	if phase >= 5:
		return {"speed": 0.72, "rings": 4, "spike_life": 5.0, "chain": 0.5, "sweep": 0.6}
	if phase >= 3:
		return {"speed": 0.85, "rings": 4, "spike_life": 5.0, "chain": 0.0, "sweep": 0.0}
	return {"speed": 1.0, "rings": 3, "spike_life": 4.0, "chain": 0.0, "sweep": 0.0}


func spd(v: float) -> float:
	return v * float(_tune()["speed"])


# --- spikes: obstacles for the player, walls for a ricochet --------------
func _spike(p: Vector2) -> void:
	p = clamp_floor(p)
	for s in _spikes:
		if (s.p as Vector2).distance_to(p) < SPIKE_R * 1.5:
			return
	_spikes.append({"p": p, "t": float(_tune()["spike_life"]), "age": 0.0})


## Push a walker of radius `r` out of every spike.
func push_out(p: Vector2, r: float) -> Vector2:
	for s in _spikes:
		var c: Vector2 = s.p
		var d := p - c
		if d.length() < SPIKE_R + r:
			p = c + (d.normalized() if d != Vector2.ZERO else Vector2.DOWN) * (SPIKE_R + r)
	return p


## Spikes bounce a ricochet.
func deflects(p: Vector2, r: float) -> Vector2:
	for s in _spikes:
		var c: Vector2 = s.p
		if p.distance_to(c) < SPIKE_R + r:
			return (p - c).normalized()
	return Vector2.ZERO


# --- beams --------------------------------------------------------------
## Where a ray from `o` along `d` leaves the floor's surroundings.
func _ray_end(o: Vector2, d: Vector2) -> Vector2:
	var r := arena_rect().grow(60.0)
	var t := INF
	if d.x > 0.0:
		t = minf(t, (r.end.x - o.x) / d.x)
	elif d.x < 0.0:
		t = minf(t, (r.position.x - o.x) / d.x)
	if d.y > 0.0:
		t = minf(t, (r.end.y - o.y) / d.y)
	elif d.y < 0.0:
		t = minf(t, (r.position.y - o.y) / d.y)
	return o + d * maxf(t, 0.0)


## A beam's segments: straight until the first spike it passes, then two
## beams bending away either side from that spike.
func _beam(o: Vector2, d: Vector2) -> Array:
	var end := _ray_end(o, d)
	var hit := Vector2.INF
	var best := INF
	for s in _spikes:
		var c: Vector2 = s.p
		var q := Geometry2D.get_closest_point_to_segment(c, o + d * 30.0, end)
		var along := (q - o).length()
		if q.distance_to(c) < SPIKE_R and along < best:
			best = along
			hit = c
	if hit == Vector2.INF:
		return [[o, end]]
	var out := [[o, hit]]
	for side in [-1.0, 1.0]:
		var nd := d.rotated(side * BEAM_SPLIT)
		out.append([hit, _ray_end(hit, nd)])
	return out


func _beams_hit(segs: Array) -> bool:
	for sg in segs:
		var q := Geometry2D.get_closest_point_to_segment(player_pos(), sg[0], sg[1])
		if q.distance_to(player_pos()) < BEAM_W * 0.5 + 16.0:
			return true
	return false


func _fan_beams() -> Array:
	var segs := []
	for k in 3:
		segs.append_array(_beam(global_position, Vector2(0, 1).rotated(_fan + TAU * k / 3.0)))
	return segs


# --- behaviour ---------------------------------------------------------
func _think(delta: float) -> void:
	_touch = maxf(0.0, _touch - delta)
	_contact = maxf(0.0, _contact - delta)
	for s in _spikes:
		s.t -= delta
		s.age += delta
	_spikes = _spikes.filter(func(s): return s.t > 0.0)

	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > 180.0 else velocity.move_toward(Vector2.ZERO, 300.0 * delta)
			_wait -= delta
			if _wait <= 0.0:
				_begin(_pick())
		S.TELEGRAPH:
			velocity = _aim * 18.0
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			if kind == "refraction":
				# drift to the middle of the floor before the fan starts
				velocity = (arena_rect().get_center() - global_position) * 3.0
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_elapsed += delta
			_attack(delta)
		S.RECOVER, S.STUCK:
			eye_t = maxf(0.0, eye_t - delta * 3.0)
			velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
			_timer -= delta
			if _timer <= 0.0:
				if _chain_left > 0:
					_chain_left -= 1
					_begin(_pick())
				else:
					state = S.IDLE
					_wait = spd(randf_range(0.9, 1.6))
					if randf() < float(_tune()["chain"]):
						_chain_left = 1

	# arms: raise through the windup, slam down on the attack
	var arm_target := 0.15
	match state:
		S.TELEGRAPH:
			arm_target = 0.4 + 0.6 * eye_t
		S.ATTACK:
			arm_target = 0.0
	_arm_t = move_toward(_arm_t, arm_target, (14.0 if state == S.ATTACK else 4.0) * delta)
	if state == S.IDLE:
		_blink_cd -= delta
		if _blink_cd <= 0.0:
			_blink = BLINK_TIME
			_blink_cd = randf_range(2.4, 5.0)
	_blink = maxf(0.0, _blink - delta)

	# body contact, except mid-attack or stuck
	if _touch <= 0.0 and state != S.ATTACK and state != S.STUCK and global_position.distance_to(player_pos()) < RADIUS + 16.0:
		hurt_player(1)
		_touch = TOUCH_CD

	move_and_slide()
	var c := clamp_floor(global_position)
	if c != global_position:
		if state == S.ATTACK and kind == "charge":
			_aim = _aim.bounce((global_position - c).normalized())
		global_position = c


func _cancel() -> void:
	state = S.IDLE
	kind = ""
	_chain_left = 0
	_wait = 0.5
	_spots.clear()


func _pick() -> String:
	var pool := ["slam", "spectrum", "charge", "beam"]
	if phase >= 2:
		pool.append("shardfall")
	if phase >= 4:
		pool.append("lens")
	if phase >= 6:
		pool.append_array(["refraction", "refraction"])
	return pool.pick_random()


func _begin(k: String) -> void:
	kind = k
	state = S.TELEGRAPH
	_total = spd(ATK[k]["windup"])
	_timer = _total
	_hit_done = false
	_aim = (player_pos() - global_position).normalized()
	velocity = Vector2.ZERO
	telegraph(k)
	match k:
		"spectrum":
			_gaps.clear()
			_ring_hit.clear()
			var g := (player_pos() - global_position).angle() + randf_range(-PI, PI)
			for i in int(_tune()["rings"]):
				_gaps.append(g)
				_ring_hit.append(false)
				g += deg_to_rad(randf_range(-GAP_STEP, GAP_STEP))
		"shardfall":
			_spots.clear()
			_spots.append(player_pos())
			for i in SHARDS - 1:
				_spots.append(clamp_floor(player_pos() + Vector2(randf_range(100.0, 280.0), 0).rotated(randf() * TAU)))
		"lens":
			_lens = global_position + _aim * 120.0
		"refraction":
			_fan = _aim.angle() - PI * 0.5


func _activate() -> void:
	state = S.ATTACK
	sfx(kind)
	_elapsed = 0.0
	_travel = 0.0
	_request_shake(6.0)
	match kind:
		"slam":
			var half := deg_to_rad(SLAM_ARC * 0.5)
			var to := player_pos() - global_position
			if to.length() <= SLAM_REACH and absf(_aim.angle_to(to)) <= half:
				hurt_player(1)
			_request_shake(14.0)
			for d in SLAM_SPIKES:
				_spike(global_position + _aim * d)
		"charge":
			velocity = _aim * CHARGE_SPEED
		"shardfall":
			for sp in _spots:
				_burst(sp, Game.SAPPHIRE_CORE, 10)
				if not _hit_done and player_pos().distance_to(sp) < SHARD_R:
					hurt_player(1, sp)
					_hit_done = true
				_spike(sp)


func _attack(delta: float) -> void:
	var dur := float(ATK[kind].get("active", 0.0))
	match kind:
		"spectrum":
			for i in _gaps.size():
				var t0 := i * RING_EVERY
				var f := (_elapsed - t0) / RING_TIME
				if f < 0.0 or f > 1.0 or _ring_hit[i]:
					continue
				var r := lerpf(RING_FROM, RING_TO, f)
				var to := player_pos() - global_position
				var in_gap := absf(angle_difference(to.angle(), _gaps[i])) < deg_to_rad(RING_GAP * 0.5)
				if absf(to.length() - r) <= RING_BAND and not in_gap:
					hurt_player(1)
					_ring_hit[i] = true
			dur = (_gaps.size() - 1) * RING_EVERY + RING_TIME
		"charge":
			velocity = _aim * CHARGE_SPEED
			_travel += CHARGE_SPEED * delta
			if _travel >= CHARGE_SHARD_EVERY:
				_travel = 0.0
				_spike(global_position - _aim * 70.0)
			if not _hit_done and player_pos().distance_to(global_position) <= CHARGE_HIT:
				hurt_player(1)
				_hit_done = true
				_request_shake(10.0)
			# crashing into an older spike: stuck
			for s in _spikes:
				if float(s.age) > 0.4 and (s.p as Vector2).distance_to(global_position) < RADIUS + SPIKE_R:
					_spikes.erase(s)
					_burst(global_position, Game.SAPPHIRE_CORE, 16)
					_request_shake(12.0)
					state = S.STUCK
					_timer = STUCK_TIME
					velocity = Vector2.ZERO
					return
		"beam":
			_aim = _aim.rotated(float(_tune()["sweep"]) * delta)
			if not _hit_done and _beams_hit(_beam(global_position, _aim)):
				hurt_player(1)
				_hit_done = true
		"lens":
			velocity = Vector2.ZERO
			_lens = _lens.move_toward(player_pos(), LENS_SPEED * delta)
			if _contact <= 0.0 and player_pos().distance_to(_lens) < LENS_R:
				hurt_player(1, _lens)
				_contact = CONTACT_CD
		"refraction":
			velocity = Vector2.ZERO
			_fan += FAN_SPIN * delta
			if _contact <= 0.0 and _beams_hit(_fan_beams()):
				hurt_player(1)
				_contact = CONTACT_CD
	if _elapsed >= dur:
		state = S.RECOVER
		_timer = spd(ATK[kind]["recover"])
		if kind == "charge":
			velocity = -_aim * 220.0     # drift back off the player


# --- draw ------------------------------------------------------------
func _draw() -> void:
	# spikes: three crystal shards over a shadow, fading out as they expire
	for s in _spikes:
		var c := L(s.p)
		var a := clampf(float(s.t) / 0.5, 0.0, 1.0) * clampf(float(s.age) / 0.15, 0.0, 1.0)
		draw_colored_polygon(Transform2D(0.0, c) * Game.ellipse(24, 7), Color(Game.DEEP_MOSS, 0.5 * a))
		for k in 3:
			var x := (k - 1) * 11.0
			var h := 48.0 - absf(k - 1) * 16.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(x - 7, 0), c + Vector2(x + 7, 0), c + Vector2(x, -h)]),
				Color(Game.SAPPHIRE_CORE, 0.8 * a))

	if state == S.TELEGRAPH or state == S.ATTACK:
		_draw_attack()

	var s_ := death_scale() if dead else 1.0
	var rate := 1.5 + 0.15 * (phase - 1)
	var off := Vector2(0, sin(_t * rate) * 6.0)
	var rot := sin(_t * 0.7) * 0.03
	var sq := _visual * s_
	match state:
		S.TELEGRAPH:
			# tremble and a heartbeat pulse, both growing with the windup
			var j := eye_t * eye_t * 4.0
			off += Vector2(randf_range(-j, j), randf_range(-j, j))
			var beat := 1.0 + sin(_t * (14.0 + 30.0 * eye_t)) * 0.035 * eye_t
			sq *= Vector2(2.0 - beat, beat)
			rot += _aim.x * 0.14 * eye_t
		S.ATTACK:
			rot += _aim.x * 0.2
			if kind == "charge":
				sq *= Vector2(1.14, 0.88)
			elif kind == "refraction":
				rot += _fan
		S.STUCK:
			rot += sin(_t * 30.0) * 0.06                 # rattling in the crystal
	if dead:
		rot += _death_t * 5.0
	if _flash > 0.0:
		var jf := _flash * 30.0
		off += Vector2(randf_range(-jf, jf), randf_range(-jf, jf))

	var shrink := (1.0 - 0.07 * sin(_t * rate)) * s_
	draw_colored_polygon(Game.ellipse(58.0 * shrink, 15.0 * shrink), Color(Game.DEEP_MOSS, 0.5))
	draw_set_transform(off + LIFT + kick(), rot, sq)
	var body := body_color()

	# arms raise overhead through the windup; fingers splay as the attack nears
	var sway := sin(_t * 1.2) * 0.10 * (1.0 - _arm_t)
	var sh_l := Vector2(-48, -42)
	var sh_r := Vector2(48, -42)
	var hand_l: Vector2 = Vector2(-104, 34).lerp(Vector2(-74, -112), _arm_t)
	var hand_r: Vector2 = Vector2(104, 34).lerp(Vector2(74, -112), _arm_t)
	hand_l = sh_l + (hand_l - sh_l).rotated(sway)
	hand_r = sh_r + (hand_r - sh_r).rotated(-sway)
	_capsule(sh_l, hand_l, 10, body)
	_capsule(sh_r, hand_r, 10, body)
	var splay := deg_to_rad(28.0 + 20.0 * eye_t)
	var flen := 24.0 + 7.0 * eye_t
	for i in 3:
		_capsule(hand_l, hand_l + Vector2(flen, 0).rotated((hand_l - sh_l).angle() + (i - 1) * splay), 4.5, body)
		_capsule(hand_r, hand_r + Vector2(flen, 0).rotated((hand_r - sh_r).angle() + (i - 1) * splay), 4.5, body)

	draw_colored_polygon(PackedVector2Array([Vector2(-58, -48), Vector2(58, -48), Vector2(0, 96)]), body)
	var shimmer := 0.32 + 0.12 * sin(_t * 1.9)
	draw_colored_polygon(PackedVector2Array([Vector2(-30, -30), Vector2(30, -30), Vector2(0, 34)]), Color(Game.SAPPHIRE_CORE, shimmer))
	# a new fracture with every phase: the gem visibly breaking down
	var cracks := [[Vector2(-40, -32), Vector2(4, 22)], [Vector2(4, 22), Vector2(34, -16)], [Vector2(-14, -48), Vector2(-2, -12)],
		[Vector2(20, -48), Vector2(10, 4)], [Vector2(-30, 10), Vector2(-4, 60)]]
	for i in mini(phase - 1, cracks.size()):
		draw_line(cracks[i][0], cracks[i][1], Game.DEEP_MOSS, 3.0)
	var e := 16.0 + 5.0 * eye_t
	var lid := 1.0
	if _blink > 0.0:
		lid = lerpf(1.0, 0.1, sin(PI * (1.0 - _blink / BLINK_TIME)))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -22 - e * lid), Vector2(e, -22), Vector2(0, -22 + e * lid), Vector2(-e, -22)]), eye_color())
	draw_set_transform(Vector2.ZERO)


## Telegraphs while winding up, and the attack itself while it runs.
func _draw_attack() -> void:
	var tele := state == S.TELEGRAPH
	var col := warn_color()
	match kind:
		"slam":
			var half := deg_to_rad(SLAM_ARC * 0.5)
			var reach := SLAM_REACH * ((0.4 + 0.6 * eye_t) if tele else 1.0)
			var poly := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				poly.append(Vector2(reach, 0).rotated(_aim.angle() - half + 2.0 * half * i / 12.0))
			draw_colored_polygon(poly, col)
		"spectrum":
			for i in _gaps.size():
				var r := RING_TO * eye_t if tele else lerpf(RING_FROM, RING_TO, (_elapsed - i * RING_EVERY) / RING_TIME)
				if tele and i > 0:
					break
				if r < RING_FROM or r > RING_TO:
					continue
				var g := deg_to_rad(RING_GAP * 0.5)
				draw_arc(Vector2.ZERO, r, _gaps[i] + g, _gaps[i] + TAU - g, 64, col if tele else Game.PALE_JADE, 3.0 + 4.0 * eye_t if tele else 8.0)
		"charge":
			if tele:
				var run := CHARGE_SPEED * float(ATK["charge"]["active"])
				var n := Vector2(-_aim.y, _aim.x) * 60.0
				draw_colored_polygon(PackedVector2Array([n, n + _aim * run, -n + _aim * run, -n]), col)
		"beam":
			for sg in _beam(global_position, _aim):
				draw_line(L(sg[0]), L(sg[1]), col if tele else Game.PALE_JADE, 2.0 + 2.0 * eye_t if tele else BEAM_W)
		"shardfall":
			if tele:
				for sp in _spots:
					draw_circle(L(sp), SHARD_R * (0.4 + 0.6 * eye_t), col)
		"lens":
			draw_line(LIFT + Vector2(0, -22), L(_lens), Color(Game.PALE_JADE, 0.35), 3.0)
			draw_circle(L(_lens), LENS_R * (0.5 + 0.5 * eye_t if tele else 1.0), col if tele else Color(Game.PALE_JADE, 0.6))
		"refraction":
			for sg in _fan_beams():
				draw_line(L(sg[0]), L(sg[1]), col if tele else Game.PALE_JADE, 2.0 if tele else BEAM_W)
