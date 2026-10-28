extends CharacterBody2D
## The Swordsman, armed with a rapier. Move (8-dir), dodge roll (i-frames +
## afterimage trail), and two thrusts on one shared system: light is a quick
## jab, heavy a slow lunge that reaches further and covers a wider strip.
##
## Abilities, all available from the start:
##   Ricochet (6 s cooldown): aim by holding the button and dragging back, let
##     go to launch. The player becomes the projectile, passing through the
##     boss and bouncing off the edge of the floor for up to 3 s.
##   Blink (3 s cooldown): a thrust that teleports BLINK_DIST along facing,
##     cutting anything on the line.
##   Ultimate (charged by damage dealt): six blink-slashes straight through
##     the boss from all sides. Its cuts pierce shields.
## The player is invulnerable while ricocheting, blinking or in the ultimate.
##
## Code-driven rig: upright 3/4 view, posed from facing, animated with tweens.
## Every action is also felt and heard: the patterns live in haptics.gd, the
## sounds in media/sfx/ (tools/make_sfx.py).

signal died
signal health_changed(current: int, max: int)
signal hit_taken

const MAX_HP := 4
const SPEED := 260.0

const DODGE_SPEED := 620.0
const DODGE_TIME := 0.18
const DODGE_IFRAME_TIME := 0.20
const DODGE_COOLDOWN := 0.5

const RIG := 1.5               # rig scale; boss body is ~144 tall, bible wants 2:1
const OUTLINE := 3.0           # Deep Moss backing width; keeps overlapping parts readable

const GHOST_LIFE := 0.30       # afterimage fade time
const GHOST_EVERY := 0.028     # afterimage spawn interval during dodge

# Shared thrust skeleton: windup -> active -> recovery. A thrust hits a strip
# `reach` long and `width` wide straight along facing, lunging `lunge` units.
const ATTACKS := {
	"light": {"windup": 0.06, "active": 0.07, "recovery": 0.16, "dmg": 1, "reach": 120.0, "width": 34.0, "lunge": 30.0, "shake": 4.0, "hitstop": 0.05, "punch": 0.0},
	"heavy": {"windup": 0.26, "active": 0.10, "recovery": 0.40, "dmg": 3, "reach": 200.0, "width": 70.0, "lunge": 80.0, "shake": 11.0, "hitstop": 0.10, "punch": 1.09},
}
const BOSS_R := 40.0           # rough boss radius for every hit test

const RICOCHET_SPEED := 1100.0
const RICOCHET_TIME := 3.0
const RICOCHET_COOLDOWN := 6.0
const RICOCHET_DMG := 1
const RICOCHET_REHIT := 0.3    # one hit per pass through the boss

const BLINK_DIST := 260.0
const BLINK_WIDTH := 70.0
const BLINK_DMG := 2
const BLINK_COOLDOWN := 3.0
const BLINK_WINDUP := 0.06
const BLINK_RECOVER := 0.18

const ULT_COST := 12           # damage to deal before the ultimate is ready
const ULT_SLASHES := 6
const ULT_EVERY := 0.11
const ULT_RADIUS := 170.0

const STREAK_LIFE := 0.3

# FREE, DODGE and ATTACK keep their values: the Mirror boss drives this rig by number
enum State { FREE, DODGE, ATTACK, RICOCHET, BLINK, ULT }

var hp := MAX_HP
var state: State = State.FREE
var facing := Vector2.DOWN
var invulnerable := false

var _dodge_cd := 0.0
var _atk_name := ""
var _atk_phase := ""          # "windup" | "active" | "recovery"
var _atk_timer := 0.0
var _atk_dur := 0.0           # duration of current phase, for progress
var _atk_hit_done := false
var _flash := 0.0             # Pale Jade damage flash, seconds remaining
var _visual := Vector2.ONE    # squash/stretch scale, tweened

var _walk := 0.0             # walk-cycle phase
var _walk_amp := 0.0         # 0..1 walk bounce strength
var _ghosts: Array = []      # [{pos:Vector2, f:float, age:float}]
var _ghost_acc := 0.0
var _idle_t := 0.0           # idle-breathing phase
var _face_x := 1.0           # horizontal mirror; keeps its last side when facing straight up/down
var _roll := 0.0             # dodge-roll spin, radians
var ult_charge := 0          # 0..ULT_COST
var _pull := Vector2.ZERO     # quicksand's pull this frame
var _rico_cd := 0.0
var _blink_cd := 0.0
var _aim := Vector2.ZERO     # latched ricochet aim while its button is held
var _aiming := false
var _move_dir := Vector2.DOWN  # direction of the current ricochet / blink
var _timer := 0.0            # generic timer for the ability states
var _rehit := 0.0
var _phase_i := 0            # blink: 0 windup, 1 recover; ult: slashes done
var _ult_base := 0.0
var _streaks: Array = []     # [{a:Vector2, b:Vector2, age:float}] slash lines on the floor
var body_color := Game.SAPPHIRE_CORE   # the Mirror boss reuses this rig in Pale Jade
var _look := Vector2.DOWN    # the facing the rig is drawn with; turns smoothly toward facing
var _lean := 0.0             # tilt into the run, radians
var _step := 0.0             # last walk-cycle sign, for footfalls
var _hurt_t := 99.0          # seconds since last hurt, for the i-frame flicker
var _dead_t := -1.0          # seconds since death, -1 alive

@onready var boss: Node = get_tree().get_first_node_in_group("boss")


func _ready() -> void:
	add_to_group("player")
	health_changed.emit(hp, MAX_HP)


## Felt and heard only for the real player, not the Mirror's copies of this
## rig (the Mirror makes its own sounds).
func _feel(pattern: String) -> void:
	if is_in_group("player"):
		Haptics.play(pattern)
		Sfx.play(pattern)


## Drawing state. In _process rather than physics so the Mirror's puppets
## (physics off, posed by hand) animate too.
func _process(delta: float) -> void:
	# turn smoothly, except mid-action, where the blade must match the hit
	if state == State.FREE or state == State.DODGE:
		_look = _look.slerp(facing, 1.0 - exp(-delta * 18.0))
		if _look.length() < 0.5:
			_look = facing           # slerp has no way round a half turn
		_look = _look.normalized()
	else:
		_look = facing
	var lean_to := clampf(velocity.x / SPEED, -1.0, 1.0) * 0.1 if state == State.FREE else 0.0
	_lean = lerpf(_lean, lean_to, 1.0 - exp(-delta * 10.0))
	_hurt_t += delta
	# blink out every other 0.05 s while the hurt i-frames last
	self_modulate.a = 0.35 if _hurt_t < 0.45 and fmod(_hurt_t, 0.1) < 0.05 else 1.0
	if _dead_t >= 0.0:
		_dead_t += delta
		_flash = maxf(0.0, _flash - delta)     # physics, which fades it, has stopped
		queue_redraw()


func _physics_process(delta: float) -> void:
	_dodge_cd = max(0.0, _dodge_cd - delta)
	if (_rico_cd > 0.0 and _rico_cd <= delta) or (_blink_cd > 0.0 and _blink_cd <= delta):
		_feel("ready")              # an ability came back
	_rico_cd = maxf(0.0, _rico_cd - delta)
	_blink_cd = maxf(0.0, _blink_cd - delta)
	_rehit = maxf(0.0, _rehit - delta)
	if not _streaks.is_empty():
		for st in _streaks:
			st.age += delta
		_streaks = _streaks.filter(func(st): return st.age < STREAK_LIFE)
	_idle_t += delta
	if absf(facing.x) > 0.15:
		_face_x = signf(facing.x)
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta)

	# age + prune afterimages
	if not _ghosts.is_empty():
		for g in _ghosts:
			g.age += delta
		_ghosts = _ghosts.filter(func(g): return g.age < GHOST_LIFE)

	match state:
		State.FREE:
			_do_free(delta)
		State.DODGE:
			_do_dodge(delta)
		State.ATTACK:
			_do_attack(delta)
		State.RICOCHET:
			_do_ricochet(delta)
		State.BLINK:
			_do_blink(delta)
		State.ULT:
			_do_ult(delta)

	if state != State.RICOCHET:      # the ricochet moves by hand, through the boss
		move_and_slide()
	_clamp_to_arena()
	queue_redraw()


func _do_free(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	var own := velocity - _pull      # last frame's pull isn't the player's own speed
	own = dir.normalized() * SPEED if dir != Vector2.ZERO else own.move_toward(Vector2.ZERO, SPEED * 0.35)
	# ground the boss has made treacherous: sand slows, quicksand pulls
	_pull = Vector2.ZERO
	if _boss_alive():
		if boss.has_method("slow_at"):
			own *= float(boss.slow_at(global_position))
		if boss.has_method("pull_at"):
			_pull = boss.pull_at(global_position)
	velocity = own + _pull

	# walk squash-and-stretch
	if velocity.length() > 30.0:
		_walk += delta * 16.0
		_walk_amp = move_toward(_walk_amp, 1.0, delta * 6.0)
		# a puff of dust each time a foot comes down
		var st := signf(sin(_walk))
		if st != _step and _walk_amp > 0.6:
			_burst(global_position + Vector2(_step * 6.0, 0), Color(Game.SAPPHIRE_CORE, 0.5), 3, 70.0)
		_step = st
	else:
		_walk_amp = move_toward(_walk_amp, 0.0, delta * 6.0)

	# ricochet: hold to aim (drag back on touch, arrows on a keyboard), let go to launch
	if Input.is_action_pressed("ricochet"):
		var aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if aim.length() > 0.2:
			_aim = aim.normalized()
		if not _aiming and _rico_cd <= 0.0:
			_feel("aim")
		_aiming = true
	elif _aiming:
		_aiming = false
		if _rico_cd <= 0.0:
			_start_ricochet(_aim if _aim != Vector2.ZERO else facing)
		_aim = Vector2.ZERO
		return

	if Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0:
		_start_dodge()
	elif Input.is_action_just_pressed("ultimate") and ult_ready():
		_start_ult()
	elif Input.is_action_just_pressed("blink") and _blink_cd <= 0.0:
		_start_blink()
	elif Input.is_action_just_pressed("attack_light"):
		_start_attack("light")
	elif Input.is_action_just_pressed("attack_heavy"):
		_start_attack("heavy")


func _start_dodge() -> void:
	state = State.DODGE
	_dodge_cd = DODGE_COOLDOWN
	_atk_timer = DODGE_TIME
	invulnerable = true
	velocity = facing * DODGE_SPEED
	_walk_amp = 0.0
	_ghost_acc = 0.0
	_roll = 0.0
	_pop_visual(Vector2(1.35, 0.7))   # stretch along travel
	_feel("dodge")
	_burst(global_position, Game.SAPPHIRE_CORE, 8)
	get_tree().create_timer(DODGE_IFRAME_TIME).timeout.connect(func(): invulnerable = false)


func _do_dodge(delta: float) -> void:
	_atk_timer -= delta
	_roll = (1.0 - clampf(_atk_timer / DODGE_TIME, 0.0, 1.0)) * TAU
	velocity = velocity.move_toward(facing * SPEED, 1400.0 * delta)
	_ghost_acc -= delta
	if _ghost_acc <= 0.0:
		_ghosts.append({"pos": global_position, "f": facing.angle(), "age": 0.0})
		_ghost_acc = GHOST_EVERY
	if _atk_timer <= 0.0:
		state = State.FREE
		_roll = 0.0
		_pop_visual(Vector2(0.85, 1.15))
		_burst(global_position, Color(Game.SAPPHIRE_CORE, 0.5), 5, 90.0)   # landing dust


func _start_attack(name: String) -> void:
	state = State.ATTACK
	_atk_name = name
	_atk_phase = "windup"
	_atk_timer = ATTACKS[name]["windup"]
	_atk_dur = _atk_timer
	_atk_hit_done = false
	velocity = Vector2.ZERO
	_walk_amp = 0.0
	var s := 1.25 if name == "heavy" else 1.12
	_pop_visual(Vector2(s, 2.0 - s))   # scale-pulse windup
	_feel("swing_heavy" if name == "heavy" else "swing_light")


func _do_attack(delta: float) -> void:
	var a: Dictionary = ATTACKS[_atk_name]
	if _atk_phase == "active":
		velocity = facing * float(a["lunge"]) / float(a["active"])   # the lunge
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0 * delta)
	_atk_timer -= delta
	if _atk_timer > 0.0:
		return
	match _atk_phase:
		"windup":
			_atk_phase = "active"
			_atk_timer = a["active"]
			_atk_dur = _atk_timer
			# spring forward into the lunge
			_pop_visual(Vector2(0.86, 1.16) if _atk_name == "heavy" else Vector2(0.93, 1.07))
		"active":
			if not _atk_hit_done:
				_resolve_hit(a)
				_atk_hit_done = true
			_atk_phase = "recovery"
			_atk_timer = a["recovery"]
			_atk_dur = _atk_timer
		"recovery":
			state = State.FREE
			_atk_name = ""


func _atk_progress() -> float:
	if _atk_dur <= 0.0:
		return 1.0
	return clampf(1.0 - _atk_timer / _atk_dur, 0.0, 1.0)


func _resolve_hit(a: Dictionary) -> void:
	if not _boss_alive():
		return
	var start := global_position - facing * float(a["lunge"])   # from where the lunge began
	var end := global_position + facing * float(a["reach"])
	_thrust_parts(start, end, float(a["width"]))
	if not _on_line(start, end, float(a["width"])):
		return
	if _hit_boss(a["dmg"], global_position):
		_feel("hit_heavy" if _atk_name == "heavy" else "hit_light")
		if _atk_name == "heavy":
			_ring(boss.global_position, 150.0, Game.PALE_JADE)
	Game.hit_stop(a["hitstop"])
	_request_shake(a["shake"])
	if a["punch"] > 0.0:
		_request_punch(a["punch"])
	_pop_visual(Vector2(0.8, 1.2))
	_burst(boss.global_position, Game.PALE_JADE, 8 if _atk_name == "light" else 16)


# --- hit helpers -----------------------------------------------------
func _boss_alive() -> bool:
	if boss == null or not is_instance_valid(boss):
		boss = get_tree().get_first_node_in_group("boss")
	return boss != null and boss.has_method("take_hit") and int(boss.hp) > 0


## True when the boss is within a strip `width` wide along a -> b.
func _on_line(a: Vector2, b: Vector2, width: float) -> bool:
	var q := Geometry2D.get_closest_point_to_segment(boss.global_position, a, b)
	return q.distance_to(boss.global_position) <= width * 0.5 + BOSS_R


## Some bosses have parts a thrust can strike besides the body (the Turnkey's
## keys); they decide what that does.
func _thrust_parts(a: Vector2, b: Vector2, width: float) -> void:
	if boss.has_method("on_thrust"):
		boss.on_thrust(a, b, width)


## Damage the boss; whatever actually lands charges the ultimate. True when
## it landed (a shield turns it away).
func _hit_boss(dmg: int, from: Vector2, pierce := false) -> bool:
	var before := int(boss.hp)
	boss.take_hit(dmg, from, pierce)
	if state != State.ULT:
		var was := ult_charge
		ult_charge = mini(ULT_COST, ult_charge + maxi(0, before - int(boss.hp)))
		if was < ULT_COST and ult_charge >= ULT_COST:
			_feel("ult_ready")
			_ring(global_position, 120.0, Game.PALE_JADE, 0.5)
	return int(boss.hp) < before


func ult_ready() -> bool:
	return ult_charge >= ULT_COST and _boss_alive()


## Cooldown left and its full length, for the touch buttons.
func cooldown(action: String) -> Vector2:
	match action:
		"dodge":
			return Vector2(_dodge_cd, DODGE_COOLDOWN)
		"ricochet":
			return Vector2(_rico_cd, RICOCHET_COOLDOWN)
		"blink":
			return Vector2(_blink_cd, BLINK_COOLDOWN)
	return Vector2.ZERO


## The fight or jail this player stands in: its parent, which also holds when
## a check scene (not the arena) is the current scene.
func _arena() -> Node:
	for m in [get_parent(), get_tree().current_scene]:
		if m and m.has_method("clamp_to_arena"):
			return m
	return null


func _floor_point(p: Vector2) -> Vector2:
	var m := _arena()
	return m.clamp_to_arena(p) if m else p


# --- ricochet ---------------------------------------------------------
func _start_ricochet(dir: Vector2) -> void:
	state = State.RICOCHET
	_move_dir = dir.normalized()
	facing = _move_dir
	_timer = RICOCHET_TIME
	_rico_cd = RICOCHET_COOLDOWN
	invulnerable = true
	velocity = Vector2.ZERO
	_walk_amp = 0.0
	_ghost_acc = 0.0
	_pop_visual(Vector2(1.4, 0.65))
	_feel("ricochet")
	_burst(global_position, Game.SAPPHIRE_CORE, 10)
	_ring(global_position, 110.0)


func _do_ricochet(delta: float) -> void:
	_timer -= delta
	_roll += delta * 18.0
	var p := global_position + _move_dir * RICOCHET_SPEED * delta
	var c := _floor_point(p)
	if c != p:
		# off the edge: reflect about the wall and carry on
		_move_dir = _move_dir.bounce((p - c).normalized())
		facing = _move_dir
		_bounced(c)
	elif _boss_alive() and boss.has_method("deflects"):
		# a boss's solid parts (the Turnkey's key barrier) bounce it too
		var n: Vector2 = boss.deflects(c, 24.0)
		if n != Vector2.ZERO and _move_dir.dot(n) < 0.0:
			_move_dir = _move_dir.bounce(n)
			facing = _move_dir
			_bounced(c)
	global_position = c
	if _rehit <= 0.0 and _boss_alive() and global_position.distance_to(boss.global_position) < BOSS_R + 24.0:
		if _hit_boss(RICOCHET_DMG, global_position):
			_feel("pierce")
		_rehit = RICOCHET_REHIT
		Game.hit_stop(0.04)
		_request_shake(6.0)
		_burst(boss.global_position, Game.PALE_JADE, 10)
	_ghost_acc -= delta
	if _ghost_acc <= 0.0:
		_ghosts.append({"pos": global_position, "f": facing.angle(), "age": 0.0})
		_ghost_acc = GHOST_EVERY
	if _timer <= 0.0:
		state = State.FREE
		_roll = 0.0
		_pop_visual(Vector2(0.85, 1.15))
		get_tree().create_timer(0.15).timeout.connect(func(): invulnerable = false)


## A ricochet bounce: squash against the wall, a small shockwave, a tap.
func _bounced(at: Vector2) -> void:
	_feel("bounce")
	_request_shake(5.0)
	_burst(at, Game.SAPPHIRE_CORE, 8)
	_ring(at, 70.0, Game.SAPPHIRE_CORE, 0.25)
	_pop_visual(Vector2(0.7, 1.3))


## Where a ricochet launched along `dir` would go, bounces included.
func ricochet_path(dir: Vector2, length := 700.0) -> PackedVector2Array:
	var pts := PackedVector2Array([global_position])
	var p := global_position
	var d := dir.normalized()
	var step := 16.0
	var travelled := 0.0
	while travelled < length:
		var n := p + d * step
		var c := _floor_point(n)
		if c != n:
			d = d.bounce((n - c).normalized())
			pts.append(c)
		p = c
		travelled += step
	pts.append(p)
	return pts


# --- blink -------------------------------------------------------------
func _start_blink() -> void:
	state = State.BLINK
	_move_dir = facing
	_phase_i = 0
	_timer = BLINK_WINDUP
	_blink_cd = BLINK_COOLDOWN
	invulnerable = true
	velocity = Vector2.ZERO
	_walk_amp = 0.0
	_pop_visual(Vector2(0.8, 1.2))
	_feel("blink")


func _do_blink(delta: float) -> void:
	velocity = Vector2.ZERO
	_timer -= delta
	if _timer > 0.0:
		return
	if _phase_i == 0:
		var a := global_position
		var b := _floor_point(a + _move_dir * BLINK_DIST)
		_teleport(a, b)
		_ring(a, 80.0, Game.SAPPHIRE_CORE, 0.3)
		_ring(b, 120.0, Game.PALE_JADE, 0.35)
		_pop_visual(Vector2(1.25, 0.8))
		if _boss_alive():
			_thrust_parts(a, b, BLINK_WIDTH)
		if _boss_alive() and _on_line(a, b, BLINK_WIDTH):
			_hit_boss(BLINK_DMG, a)
			Game.hit_stop(0.07)
			_request_shake(9.0)
			_burst(boss.global_position, Game.PALE_JADE, 14)
		_phase_i = 1
		_timer = BLINK_RECOVER
	else:
		state = State.FREE
		invulnerable = false
		_pop_visual(Vector2(1.15, 0.85))


## Move from a to b at once, leaving afterimages and a slash on the floor.
func _teleport(a: Vector2, b: Vector2) -> void:
	global_position = b
	_streaks.append({"a": a, "b": b, "age": 0.0})
	for k in 5:
		var f := k / 5.0
		_ghosts.append({"pos": a.lerp(b, f), "f": facing.angle(), "age": (1.0 - f) * GHOST_LIFE * 0.5})


# --- ultimate ------------------------------------------------------------
func _start_ult() -> void:
	state = State.ULT
	ult_charge = 0
	_phase_i = 0
	_timer = 0.0
	invulnerable = true
	velocity = Vector2.ZERO
	_walk_amp = 0.0
	_ult_base = (global_position - boss.global_position).angle()
	_feel("ult_start")
	_ring(boss.global_position, 300.0, Game.PALE_JADE, 0.5)
	_request_punch(1.1)


## Each cut starts on a circle round the boss and ends on the far side; the
## angle turns 144 degrees between cuts, tracing a star through the boss.
func _do_ult(delta: float) -> void:
	velocity = Vector2.ZERO
	_timer -= delta
	if _timer > 0.0:
		return
	if _phase_i >= ULT_SLASHES or not _boss_alive():
		state = State.FREE
		get_tree().create_timer(0.3).timeout.connect(func(): invulnerable = false)
		_pop_visual(Vector2(0.85, 1.15))
		_feel("ult_end")
		_ring(global_position, 260.0, Game.SAPPHIRE_CORE, 0.5)
		return
	var ang := _ult_base + PI + _phase_i * PI * 0.8
	var centre: Vector2 = boss.global_position
	var a := _floor_point(centre + Vector2(ULT_RADIUS, 0).rotated(ang))
	var b := _floor_point(centre - Vector2(ULT_RADIUS, 0).rotated(ang))
	facing = (b - a).normalized()
	_teleport(a, b)
	_hit_boss(1, a, true)
	_feel("ult_slash")
	Game.hit_stop(0.04)
	_request_shake(7.0)
	_burst(centre, Game.PALE_JADE, 10)
	_phase_i += 1
	_timer = ULT_EVERY


func take_hit(amount: int, from_pos: Vector2) -> void:
	if invulnerable or hp <= 0:
		return
	hp -= amount
	_flash = 0.18
	invulnerable = true
	_feel("hurt")
	_hurt_t = 0.0
	velocity = (global_position - from_pos).normalized() * 340.0
	_pop_visual(Vector2(1.3, 0.75))
	_request_shake(9.0)
	_request_punch(1.06)
	Game.hit_stop(0.06)
	_burst(global_position, Game.PALE_JADE, 14)
	hit_taken.emit()
	health_changed.emit(hp, MAX_HP)
	get_tree().create_timer(0.45).timeout.connect(func(): invulnerable = false)
	if hp <= 0:
		_dead_t = 0.0
		_hurt_t = 99.0
		died.emit()
		set_physics_process(false)


func _pop_visual(target: Vector2) -> void:
	_visual = target
	var tw := create_tween()
	tw.tween_property(self, "_visual", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _request_shake(amount: float) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("add_shake"):
		main.add_shake(amount)


func _request_punch(zoom_scale: float) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("punch"):
		main.punch(zoom_scale)


func _burst(pos: Vector2, col: Color, n := 10, speed := 220.0) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("spawn_burst"):
		main.spawn_burst(pos, col, n, speed)


func _ring(pos: Vector2, radius: float, col := Game.SAPPHIRE_CORE, dur := 0.4) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("spawn_ring"):
		main.spawn_ring(pos, radius, col, dur)


func _clamp_to_arena() -> void:
	var m := _arena()
	if m:
		global_position = m.clamp_to_arena(global_position)
	# some bosses leave solid things on the floor (the Prism's crystal spikes)
	if state != State.RICOCHET and boss and is_instance_valid(boss) and boss.has_method("push_out"):
		global_position = boss.push_out(global_position, 22.0)


# --- rig: upright 3/4 view, origin on the ground at the feet ------------
## The camera looks down at roughly 60 degrees rather than straight overhead,
## so the body stands up out of its ground position instead of rotating with
## facing; turning is a mirror plus a front/back pose, not a spin.
##
## The ground plane itself is drawn 1:1, which is what keeps every hit test in
## this file plain world-space math. Only things aimed along the ground -- the
## blade, its swing arc -- get squashed by TILT on the way to the screen.
const TILT := 0.5


## Ground-plane vector -> screen offset under the tilted camera.
func _project(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * TILT)


## How far the sword arm is extended, -1 pulled back .. 1 fully thrust.
func _extension() -> float:
	if state == State.BLINK:
		return 1.0 if _phase_i == 1 else -0.6
	if state == State.ULT or state == State.RICOCHET:
		return 1.0
	if state != State.ATTACK:
		return 0.0
	var p := _atk_progress()
	match _atk_phase:
		"windup":
			return lerpf(0.0, -1.0, ease(p, 0.6))
		"active":
			return lerpf(-1.0, 1.0, ease(p, 0.3))
		_:
			return lerpf(1.0, 0.0, ease(p, 1.6))


func _draw() -> void:
	var col := Game.PALE_JADE if _flash > 0.0 else body_color

	# afterimages and the ground shadow both lie on the floor, so they are
	# drawn outside the body transform
	for g in _ghosts:
		var a: float = (1.0 - float(g.age) / GHOST_LIFE) * 0.32
		var off: Vector2 = g.pos - global_position
		var gc := Color(Game.SAPPHIRE_CORE, a)
		_capsule(off + Vector2(0, -32 * RIG), off + Vector2(0, -14 * RIG), 8 * RIG, gc)
		draw_circle(off + Vector2(0, -39 * RIG), 6.5 * RIG, gc)

	# slash lines left by blinks and the ultimate, on the floor at hip height
	for st in _streaks:
		var k: float = 1.0 - float(st.age) / STREAK_LIFE
		var hip := Vector2(0, -24 * RIG)
		draw_line(st.a - global_position + hip, st.b - global_position + hip, Color(Game.PALE_JADE, k), 2.0 + 6.0 * k)

	# ricochet aim: a dotted path with its bounces, while the button is held
	if _aiming and state == State.FREE and _rico_cd <= 0.0:
		var path := ricochet_path(_aim if _aim != Vector2.ZERO else facing)
		for n in path.size() - 1:
			var a0: Vector2 = path[n] - global_position
			var a1: Vector2 = path[n + 1] - global_position
			var seg := a1 - a0
			var d := 0.0
			while d < seg.length():
				draw_circle(a0 + seg.normalized() * d, 3.0, Color(Game.SAPPHIRE_CORE, 0.8))
				d += 22.0

	draw_colored_polygon(Game.ellipse(13 * RIG, 5 * RIG), Color(Game.DEEP_MOSS, 0.55))

	# ultimate ready: a Jade ring breathing on the floor round the feet
	if ult_charge >= ULT_COST and state == State.FREE and _dead_t < 0.0:
		var k := 0.5 + 0.5 * sin(_idle_t * 5.0)
		var ring := Game.ellipse((18.0 + 5.0 * k) * RIG, (7.0 + 2.0 * k) * RIG, 28)
		ring.append(ring[0])
		draw_polyline(ring, Color(Game.PALE_JADE, 0.45 + 0.4 * k), 3.0)

	# body transform: breathing, walk bob, dodge tumble, hurt jitter
	var sq := _visual
	var breathe := 1.0 + sin(_idle_t * 2.4) * 0.022 * (1.0 - _walk_amp)
	sq *= Vector2(2.0 - breathe, breathe)
	var offset := Vector2.ZERO
	if _walk_amp > 0.0:
		offset.y = -absf(sin(_walk)) * 3.0 * RIG * _walk_amp
	if _flash > 0.0:
		var j := _flash * 14.0
		offset += Vector2(randf_range(-j, j), randf_range(-j, j))
	var spin := _lean
	if _dead_t >= 0.0:
		# dead: topples sideways about the feet with a little bounce, and lies there
		var k := clampf(_dead_t / 0.45, 0.0, 1.0)
		spin = -_face_x * PI * 0.5 * (1.0 - pow(1.0 - k, 3.0) + 0.06 * sin(k * PI))
		offset = Vector2.ZERO
		sq = Vector2.ONE
	elif state == State.DODGE or state == State.RICOCHET:
		# tumble about the waist; rotating about the feet would read as a topple
		spin = _roll * _face_x
		var pivot := Vector2(0, -22 * RIG)
		offset += pivot - pivot.rotated(spin)
		sq *= Vector2(1.0, 0.92)
	draw_set_transform(offset, spin, sq)

	# legs step along the travel direction
	var stride := sin(_walk) * 6.0 * RIG * _walk_amp
	_capsule_o(Vector2(-4.5 * RIG, -15 * RIG), Vector2(-4.5 * RIG + stride, 0.0), 3.5 * RIG, col)
	_capsule_o(Vector2(4.5 * RIG, -15 * RIG), Vector2(4.5 * RIG - stride, 0.0), 3.5 * RIG, col)

	# walking away from the camera puts the sword arm behind the body
	var behind := _look.y < -0.3
	if behind:
		_draw_sword(col)

	_capsule_o(Vector2(-7.5 * RIG * _face_x, -29 * RIG),
		Vector2(-9.5 * RIG * _face_x, -14 * RIG), 3.2 * RIG, col)
	_capsule_o(Vector2(0, -32 * RIG), Vector2(0, -14 * RIG), 8 * RIG, col)
	_circle_o(Vector2(0, -39 * RIG), 6.5 * RIG, col)

	# eyes exist only on the side of the head the camera can actually see
	if _look.y > -0.3 and _dead_t < 0.0:
		var ey := -40.0 * RIG + _look.y * 1.5 * RIG
		var ex := 2.4 * RIG
		var cx := _face_x * 1.4 * RIG
		draw_circle(Vector2(cx - ex, ey), 1.4 * RIG, Game.DEEP_MOSS)
		draw_circle(Vector2(cx + ex, ey), 1.4 * RIG, Game.DEEP_MOSS)

	if not behind:
		_draw_sword(col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sword arm and rapier. At rest the blade is held en garde, angled a little
## off facing; a thrust pulls the arm back, then drives hand and blade straight
## along facing. Worked out on the ground plane and projected, so a thrust
## toward the camera reads long and one away from it reads short.
func _draw_sword(col: Color) -> void:
	var ext := _extension()
	var off := 0.0 if state != State.FREE else (0.35 + sin(_idle_t * 2.2) * 0.05) * _face_x
	var gdir := Vector2(1, 0).rotated(_look.angle() + off)

	var shoulder := Vector2(8 * RIG * _face_x, -30 * RIG)
	var hand := shoulder + _project(gdir * (10.0 + 9.0 * ext) * RIG)
	_capsule_o(shoulder, hand, 3.2 * RIG, col)

	# a long thin blade from a small cup guard; it grows a little on the thrust
	var length := (46.0 + 16.0 * maxf(ext, 0.0)) * RIG
	var tip := hand + _project(gdir * length)
	var sdir := (tip - hand).normalized()
	var nrm := Vector2(-sdir.y, sdir.x)
	var hw := 1.8 * RIG
	var base := hand + sdir * 2.0 * RIG
	draw_colored_polygon(PackedVector2Array([base - nrm * (hw + OUTLINE), base + nrm * (hw + OUTLINE), tip + sdir * OUTLINE]), Game.DEEP_MOSS)
	draw_colored_polygon(PackedVector2Array([base - nrm * hw, base + nrm * hw, tip]), Game.PALE_JADE)
	var butt := hand - sdir * 5.0 * RIG
	_capsule(butt, hand, 1.6 * RIG + OUTLINE, col)
	_capsule(butt, hand, 1.6 * RIG, Game.DEEP_MOSS)
	draw_circle(hand + sdir * 1.5 * RIG, 3.6 * RIG + OUTLINE * 0.5, Game.DEEP_MOSS)
	draw_circle(hand + sdir * 1.5 * RIG, 3.6 * RIG, col)

	# a heavy thrust gathers: a four-point glint grows on the tip as it winds up
	if state == State.ATTACK and _atk_name == "heavy" and _atk_phase == "windup":
		var g := (3.0 + 9.0 * _atk_progress()) * RIG
		draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -g), tip + Vector2(g * 0.22, 0), tip + Vector2(0, g), tip + Vector2(-g * 0.22, 0)]), Game.PALE_JADE)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-g, 0), tip + Vector2(0, g * 0.22), tip + Vector2(g, 0), tip + Vector2(0, -g * 0.22)]), Game.PALE_JADE)

	# the thrust's real reach: a streak down the middle of the strip it hits,
	# with the heavy thrust's wider strip shown faintly around it
	if state == State.ATTACK and _atk_phase == "active":
		var a: Dictionary = ATTACKS[_atk_name]
		var t := _atk_progress()
		var from := Vector2(0, -24 * RIG)
		var to := from + _project(facing * float(a["reach"]))
		if _atk_name == "heavy":
			var side := _project(Vector2(-facing.y, facing.x) * float(a["width"]) * 0.5)
			draw_colored_polygon(PackedVector2Array([from + side, to + side, to - side, from - side]), Color(Game.PALE_JADE, 0.22 * (1.0 - t)))
		draw_line(from, to, Color(Game.PALE_JADE, 1.0 - t * 0.6), 5.0 - t * 3.0)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


## Capsule on a Deep Moss backing. Drawn back-to-front, these outlines are what
## keep the limbs from merging into one silhouette when viewed from straight above.
func _capsule_o(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	_capsule(a, b, r + OUTLINE, Game.DEEP_MOSS)
	_capsule(a, b, r, col)


func _circle_o(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + OUTLINE, Game.DEEP_MOSS)
	draw_circle(c, r, col)
