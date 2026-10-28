extends "res://scripts/bosses/boss_base.gd"
## The Pendulum (cell II). A diamond body hangs from the ceiling on a rail
## along the back of the room, swinging a crescent blade on a long arm. The
## blade is the only part in reach, and only while it rests or is stuck in the
## floor -- the rest of the time the sword glances off it.
##
## Swing: a run of full swings across the floor. Cut: the arm locks over the
## player and drives the blade down, where it sticks. Spin: one full turn of
## the arm. Phase 2: a second blade swings mirrored, so the two cross.
##
## global_position is the blade's point on the floor (the thing to hit). The
## pivot's floor point is `pivot`; the body hangs PIVOT_LIFT above it.
## Timer: the body's eye.

enum S { IDLE, TELEGRAPH, ATTACK, REST }

const ARM := 330.0
const BLADE_HIT := 54.0
const PIVOT_LIFT := 180.0      # low enough to hang clear of the HUD bar
const BLADE_LIFT := 26.0
const RAIL_SPEED := 90.0
const CUT_RADIUS := 74.0
const ATK := {
	"swing": {"windup": 0.8, "rest": 1.2},
	"cut":   {"windup": 0.85, "rest": 1.7},
	"spin":  {"windup": 0.9, "rest": 1.2},
}

var state := S.IDLE
var kind := ""
var pivot := Vector2.ZERO
var ang := 0.0               # arm angle off straight-down-the-floor, radians
var arm := ARM
var _timer := 0.0
var _total := 1.0
var _wait := 1.4
var _amp := 1.15
var _period := 1.4
var _phase_t := 0.0
var _cut_at := Vector2.ZERO
var _hit_done := false
var _prev := Vector2.ZERO
var _prev2 := Vector2.ZERO


func _ready() -> void:
	max_hp = 12
	super()
	var r := arena_rect()
	pivot = Vector2(r.get_center().x, r.position.y + 14.0)
	global_position = _blade(ang, arm)
	_prev = global_position
	_prev2 = _blade(-ang, arm)


func _can_be_hit() -> bool:
	return state == S.REST


func _blade(a: float, length: float) -> Vector2:
	return pivot + Vector2(0, 1).rotated(a) * length


func _think(delta: float) -> void:
	var r := arena_rect()
	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			# slide along the rail toward the player, swaying gently
			pivot.x = clampf(move_toward(pivot.x, player_pos().x, RAIL_SPEED * delta), r.position.x + 120.0, r.end.x - 120.0)
			ang = sin(_t * 1.6) * 0.3
			arm = move_toward(arm, ARM, 400.0 * delta)
			_wait -= delta
			if _wait <= 0.0:
				_begin(["swing", "cut", "spin"].pick_random())
		S.TELEGRAPH:
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			match kind:
				"swing":
					ang = move_toward(ang, -_amp, 2.5 * delta)     # draw back to one side
				"cut":
					# hold over the player, extending the arm to reach them
					_cut_at = _cut_at.lerp(player_pos(), delta * 3.0)
					var off := _cut_at - pivot
					ang = lerp_angle(ang, Vector2(0, 1).angle_to(off), delta * 6.0)
					arm = clampf(off.length(), 120.0, ARM * 1.5)
				"spin":
					ang = move_toward(ang, 0.0, 2.0 * delta)
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_attack(delta)
		S.REST:
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_timer -= delta
			if _timer <= 0.0:
				state = S.IDLE
				_wait = randf_range(0.4, 0.9) if phase == 2 else randf_range(0.8, 1.4)

	_prev = global_position
	_prev2 = _blade(-ang, arm)
	global_position = _blade(ang, arm)


func _begin(k: String) -> void:
	kind = k
	state = S.TELEGRAPH
	_total = spd(ATK[k]["windup"])
	_timer = _total
	_hit_done = false
	_cut_at = player_pos()
	telegraph(k)


func _activate() -> void:
	state = S.ATTACK
	_phase_t = 0.0
	_period = spd(1.4)
	if kind == "cut":
		_request_shake(14.0)
		_burst(global_position, Game.SAPPHIRE_CORE, 14)
		if player_pos().distance_to(_blade(ang, arm)) < CUT_RADIUS:
			hurt_player(1, _blade(ang, arm))
		_rest()


func _attack(delta: float) -> void:
	_phase_t += delta
	match kind:
		"swing":
			var swings := 4.0 if phase == 2 else 3.0
			ang = -_amp * cos(PI * _phase_t / (_period * 0.5))
			_check_sweep(_prev, _blade(ang, arm))
			if phase == 2:
				_check_sweep(_prev2, _blade(-ang, arm))
			if _phase_t >= _period * 0.5 * swings:
				_rest()
		"spin":
			var dur := spd(1.2)
			ang = TAU * clampf(_phase_t / dur, 0.0, 1.0)
			_check_sweep(_prev, _blade(ang, arm))
			if _phase_t >= dur:
				ang = 0.0
				_rest()


func _check_sweep(a: Vector2, b: Vector2) -> void:
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
	var piv := L(pivot)

	# telegraphs on the floor
	if state == S.TELEGRAPH:
		match kind:
			"swing":
				_arc_band(piv, arm, -_amp, _amp)
			"spin":
				draw_arc(piv, arm, 0, TAU, 64, warn_color(), BLADE_HIT * 1.4)
			"cut":
				draw_circle(L(_cut_at), CUT_RADIUS * (0.5 + 0.5 * eye_t), warn_color())
		if kind == "swing" and phase == 2:
			_arc_band(piv, arm, -_amp, _amp)

	# rail and the body hanging from it
	var body := piv + Vector2(0, -PIVOT_LIFT + sin(_t * 1.3) * 4.0)
	draw_line(Vector2(L(Vector2(0, 0)).x, body.y - 60), Vector2(L(Vector2(get_viewport_rect().size.x, 0)).x, body.y - 60), Color(Game.SAPPHIRE_CORE, 0.6), 6.0)
	draw_line(body + Vector2(0, -40), body + Vector2(0, -60), Color(Game.SAPPHIRE_CORE, 0.6), 4.0)

	_draw_arm(body, Vector2.ZERO, ang, s)
	if phase == 2 and state == S.ATTACK and kind == "swing":
		_draw_arm(body, L(_blade(-ang, arm)), -ang, s)

	draw_set_transform(body, 0.0, _visual * s)
	draw_colored_polygon(_diamond(Vector2.ZERO, 34, 40), body_color())
	draw_colored_polygon(_diamond(Vector2(-8, -8), 14, 16), Color(Game.SAPPHIRE_CORE, 0.35))
	draw_colored_polygon(_diamond(Vector2.ZERO, 12 + 4 * eye_t, 14 + 4 * eye_t), eye_color())
	draw_set_transform(Vector2.ZERO)


## Arm from the hanging body down to a blade whose floor point is `at`.
func _draw_arm(body: Vector2, at: Vector2, a: float, s: float) -> void:
	var stuck := state == S.REST
	var blade := at + Vector2(0, -BLADE_LIFT * (0.3 if stuck else 1.0))
	draw_colored_polygon(Transform2D(0.0, at) * Game.ellipse(30, 8), Color(Game.DEEP_MOSS, 0.5))
	draw_line(body, blade, body_color(), 6.0)
	# crescent across the arm's swing direction
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
	draw_polyline(outer, Color(Game.SAPPHIRE_CORE, 0.6), 2.0)
	if stuck:
		draw_arc(at, 30, 0, TAU, 24, Color(Game.SAPPHIRE_CORE, 0.6), 2.0)


## The band the blade will sweep, from angle a0 to a1 at radius r.
func _arc_band(piv: Vector2, r: float, a0: float, a1: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		pts.append(piv + Vector2(0, 1).rotated(lerpf(a0, a1, k / 24.0)) * r)
	draw_polyline(pts, warn_color(), BLADE_HIT * 1.4)
