extends CharacterBody2D
## Shared plumbing for the cell bosses: the signals Main, the HUD and the
## touch controls listen to, health and phase 2, the hit flash, and helpers for
## shake, bursts and hurting the player. The Prism (boss.gd) predates this and
## carries its own copy.
##
## A boss's global_position is the spot the player's sword has to reach; each
## boss draws itself around that point. Every boss has one timer shape whose
## colour comes from eye_color(): Deep Moss -> Sapphire Core -> Pale Jade.

signal died
signal health_changed(current: int, max: int)
signal phase_changed(phase: int)
signal telegraph_started(kind: String)

var max_hp := 12
var hp := 12
var phase := 1
var phase_hp: Array = []     # health at which phases 2, 3... start; empty = phase 2 at half
var dead := false
var eye_t := 0.0             # 0..1 countdown to the next attack
var player: Node2D
var _flash := 0.0
var _visual := Vector2.ONE
var _kick := Vector2.ZERO    # recoil from the last hit, springs back to zero
var _shard_acc := 0.0
var _t := 0.0                # time alive, for idle motion
var _death_t := 0.0


func _ready() -> void:
	add_to_group("boss")
	hp = max_hp
	health_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if dead:
		_death_t += delta
		_shatter(delta)
		velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
		move_and_slide()
	else:
		_think(delta)
	queue_redraw()


## Per-boss behaviour, called every physics frame while alive.
func _think(_delta: float) -> void:
	pass


## False while shielded or out of reach: the sword bounces off.
func _can_be_hit() -> bool:
	return true


## Per-boss reaction to a hit that landed (after health is taken).
func _on_hit(_amount: int) -> void:
	pass


## `pierce` (the player's ultimate) lands even while shielded.
func take_hit(amount: int, from_pos: Vector2, pierce := false) -> void:
	if dead:
		return
	if not pierce and not _can_be_hit():
		_burst(from_pos.lerp(global_position, 0.6), Game.SAPPHIRE_CORE, 6)
		_request_shake(2.0)
		_recoil(from_pos, 5.0)
		Haptics.play("blocked")
		return
	hp = maxi(0, hp - amount)
	_flash = 0.12
	_pop_visual(Vector2(1.18, 0.84))
	_recoil(from_pos, 8.0 + 5.0 * amount)
	_burst(from_pos.lerp(global_position, 0.7), Game.SAPPHIRE_CORE, 12)
	_on_hit(amount)
	health_changed.emit(hp, max_hp)
	var marks := phases()
	while phase - 1 < marks.size() and hp <= int(marks[phase - 1]) and hp > 0:
		phase += 1
		phase_changed.emit(phase)
		_request_shake(18.0)
		Game.hit_stop(0.12)
	if hp <= 0:
		dead = true
		died.emit()


## Health thresholds for each new phase, high to low. The HUD draws one bar
## per phase from these.
func phases() -> Array:
	return phase_hp if not phase_hp.is_empty() else [max_hp / 2]


func telegraph(kind: String) -> void:
	telegraph_started.emit(kind)
	Haptics.play("telegraph")
	_pop_visual(Vector2(0.88, 1.14))


## Phase 2 runs every timing faster.
func spd(v: float) -> float:
	return v * (0.68 if phase == 2 else 1.0)


func eye_color(t := eye_t) -> Color:
	if t < 0.5:
		return Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, t * 2.0)
	return Game.SAPPHIRE_CORE.lerp(Game.PALE_JADE, (t - 0.5) * 2.0)


## Same hit flash as the Prism (a known palette deviation, kept for parity).
func body_color() -> Color:
	return Color.WHITE if _flash > 0.0 else Game.PALE_JADE


## Telegraph fill: Pale Jade, brighter as the attack nears.
func warn_color(t := eye_t) -> Color:
	return Color(Game.PALE_JADE, 0.22 + 0.5 * t)


## Where to draw the body from: the hit recoil, and a tremble as it dies.
## Every boss adds this to its body's draw transform.
func kick() -> Vector2:
	var k := _kick
	if dead and _death_t < 0.8:
		var j := 7.0 * (1.0 - _death_t / 0.8)
		k += Vector2(randf_range(-j, j), randf_range(-j, j))
	return k


## Knocked back from where the blow came from.
func _recoil(from_pos: Vector2, dist: float) -> void:
	var away := global_position - from_pos
	_kick = (away.normalized() if away.length() > 1.0 else Vector2.UP) * dist


## The first second of death: the body flickers white and throws off shards.
func _shatter(delta: float) -> void:
	if _death_t > 1.0:
		return
	if fmod(_death_t, 0.12) < 0.06 and _death_t < 0.6:
		_flash = 0.02
	_shard_acc -= delta
	if _shard_acc <= 0.0:
		_shard_acc = 0.09
		var at := global_position + Vector2(randf_range(-60, 60), randf_range(-150, 0))
		_burst(at, Game.PALE_JADE if randf() < 0.5 else Game.SAPPHIRE_CORE, 6)


func death_scale() -> float:
	return maxf(0.0, 1.0 - _death_t * 1.1)


func player_pos() -> Vector2:
	return player.global_position if player and is_instance_valid(player) else global_position + Vector2(9999, 0)


func hurt_player(dmg := 1, from := global_position) -> void:
	if player and is_instance_valid(player) and player.has_method("take_hit"):
		player.take_hit(dmg, from)


func arena_rect() -> Rect2:
	return get_parent().arena_rect


func clamp_floor(p: Vector2) -> Vector2:
	return get_parent().clamp_to_arena(p) if get_parent().has_method("clamp_to_arena") else p


## World point -> this node's drawing space.
func L(p: Vector2) -> Vector2:
	return p - global_position


func _pop_visual(target: Vector2) -> void:
	_visual = target
	var tw := create_tween()
	tw.tween_property(self, "_visual", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _request_shake(amount: float) -> void:
	if get_parent().has_method("add_shake"):
		get_parent().add_shake(amount)


func _burst(pos: Vector2, col: Color, n := 10) -> void:
	if get_parent().has_method("spawn_burst"):
		get_parent().spawn_burst(pos, col, n)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


func _diamond(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -ry), c + Vector2(rx, 0), c + Vector2(0, ry), c + Vector2(-rx, 0)])


## Shadow on the floor under the boss's own point.
func _shadow(rx: float, ry: float, a := 0.5) -> void:
	var s := Game.ellipse(rx, ry)
	draw_colored_polygon(s, Color(Game.DEEP_MOSS, a))
