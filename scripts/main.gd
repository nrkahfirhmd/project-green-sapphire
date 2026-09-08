extends Node2D
## Arena, camera shake, particle bursts, run timer, win/lose, restart.

const ARENA_MARGIN := Vector2(90, 80)
# Extra headroom at the top: under the tilted camera the boss body draws about
# 150px above its own floor position, and it must not run off screen.
const ARENA_TOP := 260.0

var arena_rect: Rect2
var _shake := 0.0
var _elapsed := 0.0
var _hits_taken := 0
var _over := false
var _cam_tw: Tween

@onready var camera: Camera2D = $Camera2D
@onready var player: CharacterBody2D = $Player
@onready var boss: CharacterBody2D = $Boss


func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	arena_rect = Rect2(ARENA_MARGIN.x, ARENA_TOP,
		vp.x - ARENA_MARGIN.x * 2.0, vp.y - ARENA_TOP - ARENA_MARGIN.y)
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


# camera punch-in: quick zoom spike, used on big hits and transitions
func punch(zoom_scale := 1.08, t_in := 0.07, t_out := 0.20) -> void:
	if _cam_tw and _cam_tw.is_valid():
		_cam_tw.kill()
	camera.zoom = Vector2.ONE
	_cam_tw = create_tween()
	_cam_tw.tween_property(camera, "zoom", Vector2(zoom_scale, zoom_scale), t_in)
	_cam_tw.tween_property(camera, "zoom", Vector2.ONE, t_out).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	punch(1.14, 0.12, 0.35)


func _on_player_died() -> void:
	_finish(false)


func _on_boss_died() -> void:
	_finish(true)
	punch(1.2, 0.15, 0.5)


func _finish(win: bool) -> void:
	if _over:
		return
	_over = true
	Game.hit_stop(0.15)
	var hud := $UI/HUD
	Game.record_run(_elapsed, _hits_taken)
	hud.show_result(win, _elapsed, _hits_taken)


func _draw() -> void:
	# arena floor + border. The floor is lifted a little off the pure Deep Moss
	# clear colour so the ground shadows under both fighters have something to
	# darken; still only the two locked greens, mixed.
	draw_rect(arena_rect, Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, 0.13))
	draw_rect(arena_rect, Color(Game.SAPPHIRE_CORE, 0.5), false, 2.0)
