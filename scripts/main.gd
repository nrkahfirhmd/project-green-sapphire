extends Node2D
## Arena, camera shake, particle bursts, run timer, win/lose, restart.

const ARENA_MARGIN := Vector2(90, 80)

var arena_rect: Rect2
var _shake := 0.0
var _elapsed := 0.0
var _hits_taken := 0
var _over := false

@onready var camera: Camera2D = $Camera2D
@onready var player: CharacterBody2D = $Player
@onready var boss: CharacterBody2D = $Boss


func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	arena_rect = Rect2(ARENA_MARGIN, vp - ARENA_MARGIN * 2.0)
	camera.position = vp * 0.5

	player.hit_taken.connect(func(): _hits_taken += 1)
	player.died.connect(_on_player_died)
	boss.died.connect(_on_boss_died)
	boss.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	if not _over:
		_elapsed += delta

	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()

	# screen shake decay
	if _shake > 0.0:
		_shake = max(0.0, _shake - delta * 42.0)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 0.3)

	queue_redraw()


func add_shake(amount: float) -> void:
	_shake = min(24.0, _shake + amount)


func spawn_burst(pos: Vector2, color: Color, n := 10, speed := 220.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = 0.45
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2.ZERO
	p.damping_min = 200.0
	p.damping_max = 400.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# --- outcomes --------------------------------------------------------
func _on_phase_changed(_phase: int) -> void:
	add_shake(20.0)
	# camera punch-in on the phase-2 transition
	var tw := create_tween()
	tw.tween_property(camera, "zoom", Vector2(1.12, 1.12), 0.12)
	tw.tween_property(camera, "zoom", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_player_died() -> void:
	_finish(false)


func _on_boss_died() -> void:
	_finish(true)
	var tw := create_tween()
	tw.tween_property(camera, "zoom", Vector2(1.2, 1.2), 0.15)
	tw.tween_property(camera, "zoom", Vector2.ONE, 0.5)


func _finish(win: bool) -> void:
	if _over:
		return
	_over = true
	Game.hit_stop(0.15)
	var hud := $UI/HUD
	Game.record_run(_elapsed, _hits_taken)
	hud.show_result(win, _elapsed, _hits_taken)


func _draw() -> void:
	# arena floor + border (Deep Moss ground, faint Sapphire Core edge)
	draw_rect(arena_rect, Game.DEEP_MOSS)
	draw_rect(arena_rect, Game.SAPPHIRE_CORE * Color(1, 1, 1, 0.5), false, 2.0)
