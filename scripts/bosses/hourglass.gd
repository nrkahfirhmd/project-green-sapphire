extends "res://scripts/bosses/boss_base.gd"
## The Hourglass (cell IV), the time boss. Always hittable; the fight is a
## race against its clock, played with precise thrusts at the glass.
##
## The sand clock: the top bulb drains all fight long (faster while it
##   Pours). Empty, it casts Time's Up, a burst over most of the floor that
##   only a blink or a well-timed dodge escapes, then refills and buries more
##   floor. The floor shrinks toward its middle through Main.floor_scale.
## Flip by precision: a thrust dead through the neck while it glows (during a
##   Pour, and for 1 s after any attack) flips it: the bulb refills, floor is
##   won back, and it's stunned for FLIP_STUN.
## Cracking the glass: a light thrust off-centre cracks the bulb on that side.
##   Three cracks spill it and stun it for SPILL_STUN.
##
## Attacks
##   Pour: the neck glows while sand pours, the clock drains fast and the
##     floor shrinks.
##   Sandfall: columns drop on marked spots around the player.
##   Sandslide: it tips over and slides at the player, bouncing off the edge
##     and leaving a trail of sand that halves the player's speed.
##   Rewind: it glows and starts winding back to where it stood REWIND_BACK s
##     ago, healing the damage it took since -- unless it takes REWIND_BREAK
##     hits during the warning.
##   Quicksand (phase 2): sinkholes open and pull the player in; the middle
##     hurts. A ricochet bounces off their rims.
##   Time Echo (phase 2): every Sandfall, Sandslide and Quicksand is repeated
##     by a sand ghost ECHO_DELAY s later, in the same place.
##
## Health 40, phase 2 at 20. global_position is where it stands.
## Timer: the neck.

enum S { IDLE, TELEGRAPH, ATTACK, RECOVER, STUN }

const MOVE := 50.0
const BODY_R := 55.0             # thrust within this of the middle hits the glass
const NECK_R := 20.0             # ...and within this, the neck
const NECK_AFTER := 1.0          # the neck stays lit this long after an attack
const CLOCK := [20.0, 14.0]      # seconds for the top bulb to run dry, by phase
const POUR_DRAIN := 4.0          # how much faster it runs while Pouring
const POUR := 0.16               # floor lost per pour
const MIN_FLOOR := 0.5
const FLIP_GAIN := 0.3
const FLIP_STUN := 1.0
const CRACKS_TO_SPILL := 3
const SPILL_STUN := 2.0
const TIMESUP_R := 480.0
const TIMESUP_WINDUP := 1.2
const FALL_R := 62.0
const SLIDE_SPEED := 700.0
const SLIDE_HIT := 70.0
const TRAIL_EVERY := 50.0
const TRAIL_R := 40.0
const TRAIL_TIME := 3.0
const SLOW := 0.5
const REWIND_BACK := 3.0
const REWIND_BREAK := 2
const PIT_R := 90.0
const PIT_CORE := 26.0
const PIT_PULL := 140.0
const PIT_TIME := 5.0
const PITS := 3
const ECHO_DELAY := 2.0
const CONTACT_CD := 1.0
const ATK := {
	"pour":      {"windup": 0.7, "active": 2.2, "recover": 0.8},
	"sandfall":  {"windup": 1.0, "active": 0.3, "recover": 0.9},
	"slide":     {"windup": 0.8, "active": 0.8, "recover": 1.0},
	"rewind":    {"windup": 1.5, "active": 0.5, "recover": 0.6},
	"quicksand": {"windup": 0.9, "active": 0.3, "recover": 0.8},
	"timesup":   {"windup": 1.2, "active": 0.3, "recover": 1.0},
}

var state := S.IDLE
var kind := ""
var sand := 1.0                  # top bulb, 1 full .. 0 empty: the clock
var cracks := [0, 0]             # top, bottom
var _timer := 0.0
var _total := 1.0
var _elapsed := 0.0
var _wait := 1.4
var _aim := Vector2.DOWN
var _spots: Array[Vector2] = []
var _hit_done := false
var _rot := 0.0
var _flip_to := 0.0
var _floor_goal := 1.0
var _neck_t := 0.0               # neck lit while this runs (after attacks)
var _contact := 0.0
var _trail: Array = []           # {p, t}
var _pits: Array = []            # {p, t}
var _travel := 0.0
var _history: Array = []         # [{t, p, hp}] for Rewind
var _rewind_hits := 0
var _rewind_to := Vector2.ZERO
var _rewind_hp := 0
var _echoes: Array = []          # {kind, t, data}; replay at t <= 0
var _ghosts: Array = []          # live echoes being drawn/replayed: {kind, age, data}


func _ready() -> void:
	max_hp = 40
	phase_hp = [20]
	super()


func neck_open() -> bool:
	return (state == S.ATTACK and kind == "pour") or _neck_t > 0.0


# --- the rapier against the glass --------------------------------------
## Called for every thrust and blink line. Dead centre through the lit neck
## flips it; a light thrust off-centre cracks the bulb on that side.
func on_thrust(a: Vector2, b: Vector2, width: float) -> void:
	if dead or state == S.STUN:
		return
	var q := Geometry2D.get_closest_point_to_segment(global_position, a, b)
	var off := q.distance_to(global_position)
	if off > BODY_R + width * 0.5:
		return
	if off <= NECK_R and neck_open():
		_flip()
	elif width < 50.0 and off > NECK_R:
		# which side of the thrust line the hourglass is on picks the bulb
		var side := 0 if (b - a).cross(global_position - a) > 0.0 else 1
		cracks[side] += 1
		_burst(global_position + Vector2(0, -90), Game.SAPPHIRE_CORE, 6)
		if cracks[side] >= CRACKS_TO_SPILL:
			cracks[side] = 0
			_stun(SPILL_STUN)
			_burst(global_position, Game.SAPPHIRE_CORE, 18)


func _flip() -> void:
	sand = 1.0
	_floor_goal = minf(1.0, _floor_goal + FLIP_GAIN)
	_flip_to += PI
	_request_shake(10.0)
	_burst(global_position + Vector2(0, -90), Game.PALE_JADE, 16)
	_stun(FLIP_STUN)


func _stun(t: float) -> void:
	state = S.STUN
	_timer = t
	_neck_t = 0.0
	velocity = Vector2.ZERO


func _on_hit(amount: int) -> void:
	if state == S.TELEGRAPH and kind == "rewind":
		_rewind_hits += 1
		if _rewind_hits >= REWIND_BREAK:
			_burst(global_position, Game.SAPPHIRE_CORE, 16)
			_stun(FLIP_STUN)


# --- ground: sand trails slow, quicksand pulls -------------------------
func slow_at(p: Vector2) -> float:
	for tr in _trail:
		if p.distance_to(tr.p) < TRAIL_R:
			return SLOW
	return 1.0


func pull_at(p: Vector2) -> Vector2:
	for pit in _all_pits():
		var d: Vector2 = pit - p
		if d.length() < PIT_R and d.length() > 2.0:
			return d.normalized() * PIT_PULL
	return Vector2.ZERO


## A ricochet bounces off a sinkhole's rim.
func deflects(p: Vector2, r: float) -> Vector2:
	for pit in _all_pits():
		var d: Vector2 = p - pit
		if absf(d.length() - PIT_R) < r:
			return d.normalized() * (1.0 if d.length() > PIT_R else -1.0)
	return Vector2.ZERO


func _all_pits() -> Array:
	var out := []
	for pit in _pits:
		out.append(pit.p)
	for g in _ghosts:
		if g.kind == "quicksand":
			out.append_array(g.data)
	return out


# --- behaviour ---------------------------------------------------------
func _think(delta: float) -> void:
	var main := get_parent()
	if "floor_scale" in main:
		main.floor_scale = move_toward(main.floor_scale, _floor_goal, delta * 0.12)
	_contact = maxf(0.0, _contact - delta)
	_neck_t = maxf(0.0, _neck_t - delta)
	_tick_ground(delta)
	_history.append({"t": _t, "p": global_position, "hp": hp})
	while not _history.is_empty() and _t - float(_history[0].t) > REWIND_BACK + 0.5:
		_history.pop_front()

	# the clock never stops, except while stunned
	if state != S.STUN:
		var drain := 1.0 / float(CLOCK[phase - 1])
		if state == S.ATTACK and kind == "pour":
			drain *= POUR_DRAIN
		sand = maxf(0.0, sand - drain * delta)

	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > 220.0 else velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_rot = lerp_angle(_rot, _flip_to, delta * 6.0)
			_wait -= delta
			if sand <= 0.0:
				_begin("timesup")
			elif _wait <= 0.0:
				_begin(_pick())
		S.TELEGRAPH:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			if kind == "slide":
				_aim = (player_pos() - global_position).normalized()
				_rot = lerp_angle(_rot, _flip_to + PI * 0.5 * signf(_aim.x if _aim.x != 0.0 else 1.0), delta * 5.0)
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_elapsed += delta
			_attack(delta)
		S.RECOVER, S.STUN:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_rot = lerp_angle(_rot, _flip_to, delta * 5.0)
			_timer -= delta
			if _timer <= 0.0:
				state = S.IDLE
				_wait = spd(randf_range(0.9, 1.5))
	move_and_slide()
	var c := clamp_floor(global_position)
	if c != global_position:
		if state == S.ATTACK and kind == "slide":
			_aim = _aim.bounce((global_position - c).normalized())
		global_position = c


func _pick() -> String:
	var pool := ["pour", "sandfall", "slide", "rewind"]
	if phase >= 2:
		pool.append_array(["quicksand", "quicksand"])
	if _floor_goal <= MIN_FLOOR + 0.01:
		pool.erase("pour")
	if hp >= max_hp:
		pool.erase("rewind")       # nothing to win back
	return pool.pick_random()


func _begin(k: String) -> void:
	kind = k
	state = S.TELEGRAPH
	_total = TIMESUP_WINDUP if k == "timesup" else spd(ATK[k]["windup"])
	_timer = _total
	_hit_done = false
	_aim = (player_pos() - global_position).normalized()
	telegraph(k)
	match k:
		"sandfall":
			_spots.clear()
			_spots.append(player_pos())
			for i in (5 if phase >= 2 else 3):
				_spots.append(clamp_floor(player_pos() + Vector2(randf_range(90.0, 220.0), 0).rotated(randf() * TAU)))
		"quicksand":
			_spots.clear()
			_spots.append(clamp_floor(player_pos() + Vector2(randf_range(30.0, 80.0), 0).rotated(randf() * TAU)))
			for i in PITS - 1:
				_spots.append(clamp_floor(player_pos() + Vector2(randf_range(220.0, 380.0), 0).rotated(randf() * TAU)))
		"rewind":
			_rewind_hits = 0
			var past: Dictionary = _history[0] if not _history.is_empty() else {"p": global_position, "hp": hp}
			_rewind_to = past.p
			_rewind_hp = past.hp


func _activate() -> void:
	state = S.ATTACK
	_elapsed = 0.0
	_travel = 0.0
	match kind:
		"pour":
			_floor_goal = maxf(MIN_FLOOR, _floor_goal - POUR * (1.5 if phase >= 2 else 1.0))
		"sandfall":
			_drop_sand(_spots)
			_echo("sandfall", _spots.duplicate())
		"slide":
			velocity = _aim * SLIDE_SPEED
			_echo("slide", {"from": global_position, "aim": _aim})
		"rewind":
			# not broken in time: back it goes, healing what it took since
			global_position = _rewind_to
			if _rewind_hp > hp:
				hp = _rewind_hp
				health_changed.emit(hp, max_hp)
			_burst(global_position, Game.SAPPHIRE_CORE, 16)
		"quicksand":
			for sp in _spots:
				_pits.append({"p": sp, "t": PIT_TIME})
			_echo("quicksand", _spots.duplicate())
		"timesup":
			_request_shake(18.0)
			_burst(global_position, Game.PALE_JADE, 30)
			if player_pos().distance_to(global_position) < TIMESUP_R:
				hurt_player(2)
			sand = 1.0
			_floor_goal = maxf(MIN_FLOOR, _floor_goal - POUR)


func _drop_sand(spots: Array) -> void:
	_request_shake(10.0)
	var hit := false
	for sp in spots:
		_burst(sp, Game.SAPPHIRE_CORE, 10)
		if not hit and player_pos().distance_to(sp) < FALL_R:
			hurt_player(1, sp)
			hit = true


func _attack(delta: float) -> void:
	if kind == "slide":
		velocity = _aim * SLIDE_SPEED
		_rot += delta * 14.0 * signf(_aim.x if _aim.x != 0.0 else 1.0)
		_travel += SLIDE_SPEED * delta
		if _travel >= TRAIL_EVERY:
			_travel = 0.0
			_trail.append({"p": global_position, "t": TRAIL_TIME})
		if not _hit_done and player_pos().distance_to(global_position) < SLIDE_HIT:
			hurt_player(1)
			_hit_done = true
			_request_shake(10.0)
	if _elapsed >= ATK[kind]["active"]:
		state = S.RECOVER
		_timer = spd(ATK[kind]["recover"])
		_neck_t = NECK_AFTER
		if kind == "slide":
			velocity = -_aim * 160.0


## In phase 2, a sand ghost replays this attack ECHO_DELAY s later.
func _echo(k: String, data) -> void:
	if phase >= 2:
		_echoes.append({"kind": k, "t": ECHO_DELAY, "data": data})


func _tick_ground(delta: float) -> void:
	for tr in _trail:
		tr.t -= delta
	_trail = _trail.filter(func(tr): return tr.t > 0.0)
	for pit in _pits:
		pit.t -= delta
	_pits = _pits.filter(func(pit): return pit.t > 0.0)
	# quicksand's middle hurts
	if _contact <= 0.0:
		for pit in _all_pits():
			if player_pos().distance_to(pit) < PIT_CORE:
				hurt_player(1, pit)
				_contact = CONTACT_CD
				break
	# echoes: wait, then play out as a ghost (aged from next frame on)
	var fresh := []
	for e in _echoes:
		e.t -= delta
		if e.t <= 0.0:
			fresh.append({"kind": e.kind, "age": 0.0, "data": e.data, "hit": false})
			if e.kind == "sandfall":
				_drop_sand(e.data)
	_echoes = _echoes.filter(func(e): return e.t > 0.0)
	for g in _ghosts:
		g.age += delta
		if g.kind == "slide" and not g.hit:
			var from: Vector2 = g.data.from
			var aim: Vector2 = g.data.aim
			var at := clamp_floor(from + aim * SLIDE_SPEED * minf(g.age, 0.8))
			if player_pos().distance_to(at) < SLIDE_HIT:
				hurt_player(1, at)
				g.hit = true
	_ghosts = _ghosts.filter(func(g): return g.age < (PIT_TIME if g.kind == "quicksand" else 1.0))
	_ghosts.append_array(fresh)


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := death_scale() if dead else 1.0
	var main := get_parent()
	var c := Game.SAPPHIRE_CORE

	# the buried band: everything between the full floor and the shrunk one
	if "floor_scale" in main and main.floor_scale < 0.999 and "arena_poly" in main:
		var full: PackedVector2Array = main.arena_poly
		var mid: Vector2 = main.arena_rect.get_center()
		var inner := PackedVector2Array()
		for p in full:
			inner.append(mid + (p - mid) * float(main.floor_scale))
		var n := full.size()
		for i in n:
			var j := (i + 1) % n
			draw_colored_polygon(PackedVector2Array([L(full[i]), L(full[j]), L(inner[j]), L(inner[i])]), Color(c, 0.42))
		draw_polyline(_close(inner), Color(c, 0.75), 3.0)

	# sand trails, sinkholes (live and echoed), echo ghosts
	for tr in _trail:
		draw_circle(L(tr.p), TRAIL_R, Color(c, 0.22 * clampf(float(tr.t), 0.0, 1.0)))
	for pit in _all_pits():
		var pc := L(pit)
		draw_circle(pc, PIT_R, Color(Game.DEEP_MOSS, 0.6))
		for k in 3:
			var r := fposmod(PIT_R - _t * 40.0 - k * 30.0, PIT_R)
			draw_arc(pc, r, 0, TAU, 32, Color(c, 0.6), 2.0)
		draw_circle(pc, PIT_CORE, warn_color(1.0))
	for g in _ghosts:
		if g.kind == "slide":
			var at: Vector2 = clamp_floor(g.data.from + g.data.aim * SLIDE_SPEED * minf(g.age, 0.8))
			draw_circle(L(at), SLIDE_HIT, Color(c, 0.3 * (1.0 - g.age)))
	for e in _echoes:
		# where an echo is about to replay
		match e.kind:
			"sandfall":
				for sp in e.data:
					draw_arc(L(sp), FALL_R, 0, TAU, 24, Color(c, 0.5), 2.0)
			"slide":
				var n := Vector2(-e.data.aim.y, e.data.aim.x) * SLIDE_HIT
				var a0 := L(e.data.from)
				var run: Vector2 = e.data.aim * SLIDE_SPEED * 0.8
				draw_polyline(PackedVector2Array([a0 + n, a0 + n + run, a0 - n + run, a0 - n, a0 + n]), Color(c, 0.5), 2.0)
			"quicksand":
				for sp in e.data:
					draw_arc(L(sp), PIT_R, 0, TAU, 24, Color(c, 0.5), 2.0)

	# telegraphs
	if state == S.TELEGRAPH:
		match kind:
			"sandfall":
				for sp in _spots:
					draw_circle(L(sp), FALL_R * (0.4 + 0.6 * eye_t), warn_color())
			"slide":
				var n := Vector2(-_aim.y, _aim.x) * SLIDE_HIT
				var run := _aim * SLIDE_SPEED * float(ATK["slide"]["active"])
				draw_colored_polygon(PackedVector2Array([n, n + run, -n + run, -n]), warn_color())
			"pour":
				draw_arc(Vector2.ZERO, 120, 0, TAU, 40, warn_color(), 4.0)
			"quicksand":
				for sp in _spots:
					draw_circle(L(sp), PIT_R * (0.4 + 0.6 * eye_t), warn_color())
			"rewind":
				# a ghost where it will wind back to, and pips for the hits that stop it
				draw_arc(L(_rewind_to), 60, 0, TAU, 32, warn_color(), 3.0)
				for i in REWIND_BREAK:
					var filled := i < _rewind_hits
					var pc := Vector2(-14 + i * 28, -200)
					draw_colored_polygon(_diamond(pc, 9, 9), Game.PALE_JADE if filled else Color(c, 0.5))
			"timesup":
				draw_circle(Vector2.ZERO, TIMESUP_R * (0.6 + 0.4 * eye_t), warn_color())

	_shadow(60.0 * s, 16.0 * s)
	# body: two bulbs on frames, turned by _rot about its middle
	draw_set_transform(Vector2(0, -90), _rot, _visual * s)
	var body := body_color()
	draw_rect(Rect2(-56, -88, 112, 14), Color(c, 0.9))
	draw_rect(Rect2(-56, 74, 112, 14), Color(c, 0.9))
	draw_line(Vector2(-50, -74), Vector2(-50, 74), Color(c, 0.8), 5.0)
	draw_line(Vector2(50, -74), Vector2(50, 74), Color(c, 0.8), 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-44, -74), Vector2(44, -74), Vector2(0, 0)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(44, 74), Vector2(-44, 74)]), body)
	# the clock: sand left in the top bulb, what has run into the bottom
	var top := clampf(sand, 0.0, 1.0)
	if top > 0.02:
		draw_colored_polygon(PackedVector2Array([Vector2(-38 * top, -66 * top), Vector2(38 * top, -66 * top), Vector2(0, 0)]), Color(c, 0.75))
	var bot := 1.0 - top
	if bot > 0.02:
		var h := 66.0 * bot
		draw_colored_polygon(PackedVector2Array([Vector2(-44 + 44 * (1.0 - bot), 74 - h), Vector2(44 - 44 * (1.0 - bot), 74 - h),
			Vector2(44, 74), Vector2(-44, 74)]), Color(c, 0.75))
	if state == S.ATTACK and kind == "pour":
		draw_line(Vector2.ZERO, Vector2(0, 70), Color(c, 0.85), 3.0)
	# cracks in the glass
	var lines := [[Vector2(-20, -60), Vector2(6, -30)], [Vector2(14, -58), Vector2(-4, -22)], [Vector2(-26, -44), Vector2(18, -40)]]
	for side in 2:
		for i in cracks[side]:
			var l: Array = lines[i]
			var flip := 1.0 if side == 0 else -1.0
			draw_line(l[0] * Vector2(1, flip), l[1] * Vector2(1, flip), Game.DEEP_MOSS, 3.0)
	# the neck: its timer colour, and a ring while a flip is possible
	if neck_open():
		draw_arc(Vector2.ZERO, 16, 0, TAU, 20, Game.PALE_JADE, 3.0)
	draw_circle(Vector2.ZERO, 9 + 3 * eye_t, eye_color())
	draw_set_transform(Vector2.ZERO)


func _close(p: PackedVector2Array) -> PackedVector2Array:
	return p + PackedVector2Array([p[0]])
