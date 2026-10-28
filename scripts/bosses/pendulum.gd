extends "res://scripts/bosses/boss_base.gd"
## The Pendulum (cell II). A diamond body hangs from a rail along the
## library's ceiling and swings a crescent blade on a long arm. The fight is
## about meeting the blade with the rapier.
##
## Riposte: thrust the blade as it sweeps through you (its edge flashes Jade
##   while it's in reach) and it rebounds; the arm locks and the body drops to
##   the floor, open to every hit, for DOWN_TIME. Riposted into the bookshelves
##   along the back wall, the blade jams and the body stays down for JAM_TIME.
## The blade itself can also be hit while it rests after an attack, or sticks
##   in the floor after a Cut.
##
## Attacks
##   Swing: full swings whose arm stretches and shortens as it goes, so neither
##     under the rail nor far from it is safe.
##   Cut: the arm locks over the player and drives the blade down; it sticks.
##   Unwind: one turn of the arm, spiralling out from 120 to 480.
##   Bookfall: the blade clips the shelves and books rain on marked spots,
##     leaving piles for a few seconds that a ricochet bounces off.
##   Rail Rush (phase 2+): the body races along the rail with the blade held
##     low at the player's row, raking the whole hall.
##   Clockwork (phase 3): the body lowers into the middle of the hall and two
##     arms sweep as clock hands at different speeds. Riposte a hand and the
##     clock stops with the body down. It alternates with the other attacks.
##   Phase 2 also brings back a mirrored second blade in Swing, which can be
##   riposted too.
##
## Health 20: phase 2 at 15, phase 3 at 10. global_position is whatever can be
## hit right now: the blade's point, or the body once it's on the floor.
## Timer: the body's eye.

enum S { IDLE, TELEGRAPH, ATTACK, REST, DOWN }

const ARM := 330.0
const BLADE_HIT := 54.0
const PIVOT_LIFT := 180.0        # low enough to hang clear of the HUD bar
const BLADE_LIFT := 26.0
const RAIL_SPEED := 90.0
const CUT_RADIUS := 74.0
const RIPOSTE_R := 46.0          # a thrust must pass this close to the blade
const RIPOSTE_REACH := 200.0     # ...and the blade must be this close to the player
const DOWN_TIME := 2.5
const JAM_TIME := 4.0
const SHELF_BAND := 90.0         # a blade this close to the back wall jams in the shelves
const BODY_FLOOR := 80.0         # where the dropped body lands, below the rail
const SWING_STRETCH := 130.0
const UNWIND_FROM := 120.0
const UNWIND_TO := 480.0
const RUSH_SPEED := 1400.0
const BOOKS := 5
const BOOK_R := 60.0
const BOOK_EVERY := 0.15
const PILE_R := 28.0
const PILE_TIME := 4.0
const CLOCK_TIME := 6.0
const HOUR_LEN := 250.0
const MINUTE_LEN := 430.0
const HOUR_SPIN := 0.6
const MINUTE_SPIN := 1.5
const CONTACT_CD := 0.8
const ATK := {
	"swing":  {"windup": 0.8, "rest": 1.2},
	"cut":    {"windup": 0.85, "rest": 1.7},
	"unwind": {"windup": 0.9, "rest": 1.2},
	"books":  {"windup": 0.9, "rest": 0.8},
	"rush":   {"windup": 0.8, "rest": 1.0},
	"clock":  {"windup": 1.0, "rest": 1.0},
}

var state := S.IDLE
var kind := ""
var pivot := Vector2.ZERO        # floor point under the rail end of the arm
var ang := 0.0                   # arm angle off straight-down-the-floor
var arm := ARM
var _anchor := Vector2.ZERO      # floor point under the body (the pivot, or the hall's middle)
var _drop := 0.0                 # 0 body on the rail .. 1 body on the floor
var _timer := 0.0
var _total := 1.0
var _wait := 1.4
var _amp := 1.15
var _period := 1.4
var _phase_t := 0.0
var _cut_at := Vector2.ZERO
var _hit_done := false
var _contact := 0.0
var _prev := Vector2.ZERO        # blade point last frame, for sweep tests
var _prev2 := Vector2.ZERO
var _rush_dir := 1.0
var _rush_y := 0.0
var _books: Array[Vector2] = []
var _dropped := 0
var _piles: Array = []           # {p: Vector2, t: float}
var _hour := 0.0
var _minute := 0.0
var _last := ""


func _ready() -> void:
	max_hp = 20
	phase_hp = [15, 10]
	super()
	var r := arena_rect()
	pivot = Vector2(r.get_center().x, r.position.y + 14.0)
	_anchor = pivot
	global_position = _blade(ang, arm)
	_prev = global_position
	_prev2 = global_position


func _can_be_hit() -> bool:
	return state == S.REST or state == S.DOWN


func _blade(a: float, length: float) -> Vector2:
	return pivot + Vector2(0, 1).rotated(a) * length


func _clocked() -> bool:
	return kind == "clock" and state != S.IDLE


func _hands() -> Array:
	var c := arena_rect().get_center()
	return [[c, c + Vector2(0, 1).rotated(_hour) * HOUR_LEN], [c, c + Vector2(0, 1).rotated(_minute) * MINUTE_LEN]]


## Floor point of the body: under the rail, or the hall's middle in Clockwork.
func _body_floor() -> Vector2:
	return _anchor if _clocked() else _anchor + Vector2(0, BODY_FLOOR)


## Floor point of whatever the sword can reach right now.
func _hit_point() -> Vector2:
	if state == S.DOWN or _clocked():
		return _body_floor()
	return _blade(ang, arm)


# --- the rapier against the blade --------------------------------------
## Called for every thrust and blink line: a riposte when the line meets a
## moving blade that has reached the player.
func on_thrust(a: Vector2, b: Vector2, width: float) -> void:
	if state != S.ATTACK:
		return
	if kind == "clock":
		for h in _hands():
			var near := Geometry2D.get_closest_points_between_segments(a, b, (h[0] as Vector2).lerp(h[1], 0.5), h[1])
			if near[0].distance_to(near[1]) <= width * 0.5 + RIPOSTE_R:
				_riposte(near[1])
				return
		return
	if not ["swing", "unwind", "rush"].has(kind):
		return
	var tips: Array[Vector2] = [_blade(ang, arm)]
	if kind == "swing" and phase >= 2:
		tips.append(_blade(-ang, arm))
	for t in tips:
		var q := Geometry2D.get_closest_point_to_segment(t, a, b)
		if q.distance_to(t) <= width * 0.5 + RIPOSTE_R and t.distance_to(player_pos()) <= RIPOSTE_REACH:
			_riposte(t)
			return


func _riposte(at: Vector2) -> void:
	var jammed := at.y < arena_rect().position.y + SHELF_BAND
	if kind == "clock":
		_anchor = arena_rect().get_center()
	state = S.DOWN
	_timer = JAM_TIME if jammed else DOWN_TIME
	velocity = Vector2.ZERO
	_burst(at, Game.PALE_JADE, 16)
	_request_shake(12.0)
	sfx("riposte")
	Game.hit_stop(0.1)


## Book piles bounce a ricochet.
func deflects(p: Vector2, r: float) -> Vector2:
	for pile in _piles:
		var c: Vector2 = pile.p
		if p.distance_to(c) < PILE_R + r:
			return (p - c).normalized()
	return Vector2.ZERO


# --- behaviour ---------------------------------------------------------
func _think(delta: float) -> void:
	var r := arena_rect()
	_contact = maxf(0.0, _contact - delta)
	for pile in _piles:
		pile.t -= delta
	_piles = _piles.filter(func(pl): return pl.t > 0.0)
	_drop = move_toward(_drop, 1.0 if state == S.DOWN else 0.0, delta * 4.0)
	if not _clocked() and state != S.DOWN:
		_anchor = _anchor.lerp(pivot, 1.0 - exp(-5.0 * delta))

	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			pivot.x = clampf(move_toward(pivot.x, player_pos().x, RAIL_SPEED * delta), r.position.x + 120.0, r.end.x - 120.0)
			ang = lerp_angle(ang, sin(_t * 1.6) * 0.3, delta * 4.0)
			arm = move_toward(arm, ARM, 400.0 * delta)
			_wait -= delta
			if _wait <= 0.0:
				_begin(_pick())
		S.TELEGRAPH:
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			_windup(delta)
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_phase_t += delta
			_attack(delta)
		S.REST, S.DOWN:
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_timer -= delta
			if _timer <= 0.0:
				_idle()

	_prev = _blade(ang, arm)
	_prev2 = _blade(-ang, arm)
	global_position = _hit_point()


func _idle() -> void:
	state = S.IDLE
	kind = ""
	_wait = randf_range(0.4, 0.9) if phase >= 2 else randf_range(0.8, 1.4)


func _pick() -> String:
	var pool := ["swing", "cut", "unwind", "books"]
	if phase >= 2:
		pool.append("rush")
	if phase >= 3 and _last != "clock":
		return "clock"
	return pool.pick_random()


func _begin(k: String) -> void:
	kind = k
	_last = k
	state = S.TELEGRAPH
	_total = spd(ATK[k]["windup"])
	_timer = _total
	_hit_done = false
	_cut_at = player_pos()
	telegraph(k)
	var r := arena_rect()
	match k:
		"rush":
			# start from the far end of the rail and rake toward the other
			_rush_dir = 1.0 if player_pos().x > r.get_center().x else -1.0
			_rush_y = clampf(player_pos().y, pivot.y + 120.0, r.end.y - 20.0)
		"books":
			_books.clear()
			_books.append(player_pos())
			for i in BOOKS - 1:
				_books.append(clamp_floor(player_pos() + Vector2(randf_range(90.0, 260.0), 0).rotated(randf() * TAU)))
		"clock":
			_hour = 0.0
			_minute = PI


## What the arm does while winding up.
func _windup(delta: float) -> void:
	var r := arena_rect()
	match kind:
		"swing":
			ang = move_toward(ang, -_amp, 2.5 * delta)
		"cut":
			# hold over the player, stretching to reach them
			_cut_at = _cut_at.lerp(player_pos(), delta * 3.0)
			var off := _cut_at - pivot
			ang = lerp_angle(ang, Vector2(0, 1).angle_to(off), delta * 6.0)
			arm = clampf(off.length(), 120.0, ARM * 1.5)
		"unwind":
			ang = move_toward(ang, 0.0, 2.0 * delta)
			arm = move_toward(arm, UNWIND_FROM, 600.0 * delta)
		"books":
			# the blade swings up into the shelves
			ang = lerp_angle(ang, PI, delta * 5.0)
			arm = move_toward(arm, 120.0, 600.0 * delta)
		"rush":
			var start_x := r.position.x + 40.0 if _rush_dir > 0.0 else r.end.x - 40.0
			pivot.x = move_toward(pivot.x, start_x, 2400.0 * delta)
			ang = lerp_angle(ang, 0.0, delta * 6.0)
			arm = move_toward(arm, _rush_y - pivot.y, 800.0 * delta)
		"clock":
			_anchor = _anchor.lerp(r.get_center(), 1.0 - exp(-4.0 * delta))


func _activate() -> void:
	state = S.ATTACK
	sfx(kind)
	_phase_t = 0.0
	_period = spd(1.4)
	_dropped = 0
	if kind == "cut":
		_request_shake(14.0)
		_burst(_blade(ang, arm), Game.SAPPHIRE_CORE, 14)
		if player_pos().distance_to(_blade(ang, arm)) < CUT_RADIUS:
			hurt_player(1, _blade(ang, arm))
		_rest()


func _attack(delta: float) -> void:
	var r := arena_rect()
	match kind:
		"swing":
			var swings := 4.0 if phase >= 2 else 3.0
			ang = -_amp * cos(PI * _phase_t / (_period * 0.5))
			# stretch and shorten through the passes, so no distance is safe
			arm = ARM + SWING_STRETCH * sin(PI * _phase_t / (_period * 0.75))
			_sweep(_prev, _blade(ang, arm))
			if phase >= 2:
				_sweep(_prev2, _blade(-ang, arm))
			if _phase_t >= _period * 0.5 * swings:
				_rest()
		"unwind":
			var dur := spd(1.4)
			var p := clampf(_phase_t / dur, 0.0, 1.0)
			ang = TAU * p
			arm = lerpf(UNWIND_FROM, UNWIND_TO, p)
			_sweep(_prev, _blade(ang, arm))
			if p >= 1.0:
				ang = 0.0
				_rest()
		"books":
			while _dropped < _books.size() and _phase_t >= _dropped * BOOK_EVERY:
				var at: Vector2 = _books[_dropped]
				_burst(at, Game.SAPPHIRE_CORE, 10)
				_request_shake(5.0)
				if not _hit_done and player_pos().distance_to(at) < BOOK_R:
					hurt_player(1, at)
					_hit_done = true
				_piles.append({"p": at, "t": PILE_TIME})
				_dropped += 1
			if _phase_t >= _books.size() * BOOK_EVERY + 0.2:
				_rest()
		"rush":
			pivot.x += _rush_dir * RUSH_SPEED * delta
			_sweep(_prev, _blade(ang, arm))
			if pivot.x < r.position.x + 40.0 or pivot.x > r.end.x - 40.0:
				pivot.x = clampf(pivot.x, r.position.x + 40.0, r.end.x - 40.0)
				_rest()
		"clock":
			_hour += HOUR_SPIN * delta
			_minute += MINUTE_SPIN * delta
			if _contact <= 0.0:
				for h in _hands():
					var q := Geometry2D.get_closest_point_to_segment(player_pos(), h[0], h[1])
					if q.distance_to(player_pos()) < BLADE_HIT * 0.6:
						hurt_player(1, q)
						_contact = CONTACT_CD
						break
			if _phase_t >= CLOCK_TIME:
				_rest()


func _sweep(a: Vector2, b: Vector2) -> void:
	if _hit_done:
		return
	var q := Geometry2D.get_closest_point_to_segment(player_pos(), a, b)
	if q.distance_to(player_pos()) < BLADE_HIT:
		hurt_player(1, q)
		_hit_done = true


func _rest() -> void:
	state = S.REST
	_timer = spd(ATK[kind]["rest"])
	if kind != "cut":
		_request_shake(4.0)


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := death_scale() if dead else 1.0
	var r := arena_rect()

	# book piles, and the spots books are about to land on
	for pile in _piles:
		var c := L(pile.p)
		for k in 3:
			draw_rect(Rect2(c + Vector2(-22 + k * 3, -10 - k * 9), Vector2(40 - k * 6, 8)), Color(Game.SAPPHIRE_CORE, 0.7))
	if kind == "books" and (state == S.TELEGRAPH or state == S.ATTACK):
		for i in _books.size():
			if i >= _dropped:
				draw_circle(L(_books[i]), BOOK_R * (0.4 + 0.6 * eye_t), warn_color())

	# telegraphs
	if state == S.TELEGRAPH:
		match kind:
			"swing":
				var swings := 4.0 if phase >= 2 else 3.0
				_path(func(t: float) -> Vector2:
					var tt := t * _period * 0.5 * swings
					return _blade(-_amp * cos(PI * tt / (_period * 0.5)), ARM + SWING_STRETCH * sin(PI * tt / (_period * 0.75))))
			"unwind":
				_path(func(t: float) -> Vector2: return _blade(TAU * t, lerpf(UNWIND_FROM, UNWIND_TO, t)))
			"cut":
				draw_circle(L(_cut_at), CUT_RADIUS * (0.5 + 0.5 * eye_t), warn_color())
			"rush":
				draw_rect(Rect2(Vector2(r.position.x, _rush_y - BLADE_HIT) - global_position, Vector2(r.size.x, BLADE_HIT * 2.0)), warn_color())
			"clock":
				var c := L(r.get_center())
				draw_arc(c, HOUR_LEN, 0, TAU, 48, warn_color(), 3.0)
				draw_arc(c, MINUTE_LEN, 0, TAU, 64, warn_color(), 3.0)

	# the rail across the top, and the body: hanging, dropped, or mid-hall
	var rail_y := L(Vector2(0, pivot.y - PIVOT_LIFT - 60.0)).y
	draw_line(Vector2(L(Vector2.ZERO).x, rail_y), Vector2(L(Vector2(get_viewport_rect().size.x, 0)).x, rail_y), Color(Game.SAPPHIRE_CORE, 0.6), 6.0)
	var clocked := _clocked()
	var hang := 90.0 if clocked else PIVOT_LIFT
	var lift := lerpf(hang, 40.0, _drop)
	var floor_pt := _anchor.lerp(_body_floor(), _drop) if not clocked else _anchor
	var body := L(floor_pt) + Vector2(0, -lift + sin(_t * 1.3) * 4.0 * (1.0 - _drop))
	if not clocked:
		draw_line(body + Vector2(0, -40), Vector2(body.x, rail_y), Color(Game.SAPPHIRE_CORE, 0.6), 4.0)
	if _drop > 0.05 or clocked:
		draw_colored_polygon(Transform2D(0.0, L(floor_pt)) * Game.ellipse(44, 13), Color(Game.DEEP_MOSS, 0.5))

	# arms: one blade, a mirrored second in phase-2 swings, or two clock hands
	var attacking := state == S.ATTACK
	if clocked:
		var hands := _hands()
		_draw_arm(body, L(hands[0][1]), _hour, s, attacking)
		_draw_arm(body, L(hands[1][1]), _minute, s, attacking)
	else:
		_draw_arm(body, L(_blade(ang, arm)), ang, s, attacking)
		if phase >= 2 and kind == "swing" and attacking:
			_draw_arm(body, L(_blade(-ang, arm)), -ang, s, attacking)

	draw_set_transform(body + kick(), 0.0, _visual * s)
	draw_colored_polygon(_diamond(Vector2.ZERO, 34, 40), body_color())
	draw_colored_polygon(_diamond(Vector2(-8, -8), 14, 16), Color(Game.SAPPHIRE_CORE, 0.35))
	draw_colored_polygon(_diamond(Vector2.ZERO, 12 + 4 * eye_t, 14 + 4 * eye_t), eye_color())
	draw_set_transform(Vector2.ZERO)


## Arm from the body down to a blade whose floor point is `at` (in drawing
## space). While the blade is attacking and within reach of the player, its
## edge flashes Jade: the riposte window.
func _draw_arm(body: Vector2, at: Vector2, a: float, s: float, attacking: bool) -> void:
	var resting := state == S.REST
	var blade := at + Vector2(0, -BLADE_LIFT * (0.3 if resting else 1.0))
	draw_colored_polygon(Transform2D(0.0, at) * Game.ellipse(30, 8), Color(Game.DEEP_MOSS, 0.5))
	draw_line(body, blade, body_color(), 6.0)
	var along := Vector2(1, 0).rotated(a)
	var w := 62.0 * s
	var p0 := blade - along * w
	var p1 := blade + along * w
	var bulge := Vector2(0, 36 * s)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 9:
		var f := k / 8.0
		var mid := p0.lerp(p1, f)
		var curve := sin(PI * f)
		outer.append(mid + bulge * curve)
		inner.append(mid + bulge * curve * 0.4)
	inner.reverse()
	draw_colored_polygon(outer + inner, body_color())
	var in_reach := attacking and (at + global_position).distance_to(player_pos()) <= RIPOSTE_REACH
	draw_polyline(outer, Game.PALE_JADE if in_reach else Color(Game.SAPPHIRE_CORE, 0.6), 4.0 if in_reach else 2.0)
	if resting:
		draw_arc(at, 30, 0, TAU, 24, Color(Game.SAPPHIRE_CORE, 0.6), 2.0)


## A telegraph band along the path a blade will take, f(0..1) -> floor point.
func _path(f: Callable) -> void:
	var pts := PackedVector2Array()
	for k in 41:
		pts.append(L(f.call(k / 40.0)))
	draw_polyline(pts, warn_color(), BLADE_HIT * 1.4)
