extends "res://scripts/bosses/boss_base.gd"
## The Hourglass (cell IV). Sand pours from its upper half and buries the
## floor from the edges in, shrinking where the player can stand. A heavy hit
## flips it and the sand pulls back; light hits only chip at it.
##
## Pour: the neck runs bright and the floor shrinks. Sandfall: columns drop on
## marked spots around the player. Grind: it tips over and rolls along a line,
## bouncing off the edge. Phase 2: everything faster, and a flip wins back
## only half as much floor.
##
## The floor shrinks through Main.floor_scale (1 = full floor); this script
## draws the buried band. global_position is where it stands.
## Timer: the neck.

enum S { IDLE, TELEGRAPH, ATTACK, RECOVER }

const MOVE := 50.0
const HIT_R := 70.0
const FALL_R := 62.0
const ROLL_SPEED := 880.0
const POUR := 0.16           # floor lost per pour
const MIN_FLOOR := 0.5
const FLIP_GAIN := 0.3
const ATK := {
	"pour":     {"windup": 0.7, "active": 2.2, "recover": 0.8},
	"sandfall": {"windup": 1.0, "active": 0.3, "recover": 0.9},
	"grind":    {"windup": 0.8, "active": 0.75, "recover": 1.0},
}

var state := S.IDLE
var kind := ""
var _timer := 0.0
var _total := 1.0
var _wait := 1.4
var _aim := Vector2.DOWN
var _spots: Array[Vector2] = []
var _hit_done := false
var _sand_top := 1.0          # sand left in the upper bulb, drawn only
var _rot := 0.0               # body rotation: tipping, rolling and flipping
var _flip_to := 0.0
var _floor_goal := 1.0


func _ready() -> void:
	max_hp = 12
	super()


func _on_hit(amount: int) -> void:
	# a heavy hit flips it: sand pulls back off the floor
	if amount >= 3:
		_floor_goal = minf(1.0, _floor_goal + FLIP_GAIN * (0.5 if phase == 2 else 1.0))
		_flip_to += PI
		_sand_top = 1.0 - _sand_top
		_request_shake(8.0)
		if state == S.ATTACK and kind == "pour":
			_end_attack()


func _think(delta: float) -> void:
	var main := get_parent()
	if "floor_scale" in main:
		main.floor_scale = move_toward(main.floor_scale, _floor_goal, delta * 0.12)
	match state:
		S.IDLE:
			eye_t = move_toward(eye_t, 0.0, delta * 2.0)
			var to := player_pos() - global_position
			velocity = to.normalized() * MOVE if to.length() > 220.0 else velocity.move_toward(Vector2.ZERO, 200.0 * delta)
			_rot = lerp_angle(_rot, _flip_to, delta * 6.0)
			_wait -= delta
			if _wait <= 0.0:
				var picks := ["sandfall", "grind", "pour"]
				if _floor_goal <= MIN_FLOOR + 0.01:
					picks.erase("pour")
				_begin(picks.pick_random())
		S.TELEGRAPH:
			velocity = Vector2.ZERO
			_timer -= delta
			eye_t = clampf(1.0 - _timer / _total, 0.0, 1.0)
			if kind == "grind":
				_aim = (player_pos() - global_position).normalized()
				_rot = lerp_angle(_rot, _flip_to + PI * 0.5 * signf(_aim.x if _aim.x != 0.0 else 1.0), delta * 5.0)
			if _timer <= 0.0:
				_activate()
		S.ATTACK:
			_attack(delta)
		S.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			eye_t = move_toward(eye_t, 0.0, delta * 1.5)
			_rot = lerp_angle(_rot, _flip_to, delta * 5.0)
			_timer -= delta
			if _timer <= 0.0:
				state = S.IDLE
				_wait = randf_range(0.5, 1.0) if phase == 2 else randf_range(0.9, 1.5)
	move_and_slide()
	var c := clamp_floor(global_position)
	if c != global_position:
		if state == S.ATTACK and kind == "grind":
			_aim = _aim.bounce((global_position - c).normalized())
		global_position = c


func _begin(k: String) -> void:
	kind = k
	state = S.TELEGRAPH
	_total = spd(ATK[k]["windup"])
	_timer = _total
	_hit_done = false
	telegraph(k)
	if k == "sandfall":
		_spots.clear()
		_spots.append(player_pos())
		for i in (5 if phase == 2 else 3):
			_spots.append(clamp_floor(player_pos() + Vector2(randf_range(90.0, 220.0), 0).rotated(randf() * TAU)))


func _activate() -> void:
	state = S.ATTACK
	_total = ATK[kind]["active"]
	_timer = _total
	match kind:
		"pour":
			_floor_goal = maxf(MIN_FLOOR, _floor_goal - POUR * (1.5 if phase == 2 else 1.0))
		"sandfall":
			_request_shake(10.0)
			for s in _spots:
				_burst(s, Game.SAPPHIRE_CORE, 10)
				if not _hit_done and player_pos().distance_to(s) < FALL_R:
					hurt_player(1, s)
					_hit_done = true
		"grind":
			velocity = _aim * ROLL_SPEED


func _attack(delta: float) -> void:
	_timer -= delta
	match kind:
		"pour":
			_sand_top = maxf(0.0, _sand_top - delta * 0.35)
		"grind":
			velocity = _aim * ROLL_SPEED
			_rot += delta * 14.0 * signf(_aim.x if _aim.x != 0.0 else 1.0)
			if not _hit_done and player_pos().distance_to(global_position) < HIT_R:
				hurt_player(1)
				_hit_done = true
				_request_shake(10.0)
	if _timer <= 0.0:
		_end_attack()


func _end_attack() -> void:
	state = S.RECOVER
	_timer = spd(ATK[kind]["recover"])
	if kind == "grind":
		velocity = -_aim * 160.0


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := death_scale() if dead else 1.0
	var main := get_parent()

	# the buried band: everything between the full floor and the shrunk one
	if "floor_scale" in main and main.floor_scale < 0.999 and "arena_poly" in main:
		var full: PackedVector2Array = main.arena_poly
		var c: Vector2 = main.arena_rect.get_center()
		var inner := PackedVector2Array()
		for p in full:
			inner.append(c + (p - c) * float(main.floor_scale))
		var n := full.size()
		for i in n:
			var j := (i + 1) % n
			draw_colored_polygon(PackedVector2Array([L(full[i]), L(full[j]), L(inner[j]), L(inner[i])]),
				Color(Game.SAPPHIRE_CORE, 0.42))
		draw_polyline(_close(inner), Color(Game.SAPPHIRE_CORE, 0.75), 3.0)

	# telegraphs
	if state == S.TELEGRAPH:
		match kind:
			"sandfall":
				for sp in _spots:
					draw_circle(L(sp), FALL_R * (0.4 + 0.6 * eye_t), warn_color())
			"grind":
				var n := Vector2(-_aim.y, _aim.x) * HIT_R
				var run: float = ROLL_SPEED * ATK["grind"]["active"]
				draw_colored_polygon(PackedVector2Array([n, n + _aim * run, -n + _aim * run, -n]), warn_color())
			"pour":
				draw_arc(Vector2.ZERO, 120, 0, TAU, 40, warn_color(), 4.0)

	_shadow(60.0 * s, 16.0 * s)
	# body: two bulbs on frames, turned by _rot about its middle
	draw_set_transform(Vector2(0, -90), _rot, _visual * s)
	var body := body_color()
	draw_rect(Rect2(-56, -88, 112, 14), Color(Game.SAPPHIRE_CORE, 0.9))
	draw_rect(Rect2(-56, 74, 112, 14), Color(Game.SAPPHIRE_CORE, 0.9))
	draw_line(Vector2(-50, -74), Vector2(-50, 74), Color(Game.SAPPHIRE_CORE, 0.8), 5.0)
	draw_line(Vector2(50, -74), Vector2(50, 74), Color(Game.SAPPHIRE_CORE, 0.8), 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-44, -74), Vector2(44, -74), Vector2(0, 0)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(44, 74), Vector2(-44, 74)]), body)
	# sand: what is left on top, what has run through below
	var top := clampf(_sand_top, 0.0, 1.0)
	if top > 0.02:
		var hgt := 66.0 * top
		var w := 38.0 * top
		draw_colored_polygon(PackedVector2Array([Vector2(-w, -hgt), Vector2(w, -hgt), Vector2(0, 0)]), Color(Game.SAPPHIRE_CORE, 0.75))
	var bot := 1.0 - top
	if bot > 0.02:
		var hgt2 := 66.0 * bot
		draw_colored_polygon(PackedVector2Array([Vector2(-44 + 44 * (1.0 - bot), 74 - hgt2), Vector2(44 - 44 * (1.0 - bot), 74 - hgt2),
			Vector2(44, 74), Vector2(-44, 74)]), Color(Game.SAPPHIRE_CORE, 0.75))
	if state == S.ATTACK and kind == "pour":
		draw_line(Vector2(0, 0), Vector2(0, 70), Color(Game.SAPPHIRE_CORE, 0.85), 3.0)
	draw_circle(Vector2.ZERO, 9 + 3 * eye_t, eye_color())
	draw_set_transform(Vector2.ZERO)


func _close(p: PackedVector2Array) -> PackedVector2Array:
	return p + PackedVector2Array([p[0]])
