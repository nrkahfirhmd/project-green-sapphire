extends Node2D
## Arena, camera shake, particle bursts, run timer, win/lose, restart.
## A win drops a sapphire where the boss died; picking it up ends the run, and
## CONTINUE takes the player back to the jail with it.

signal run_over(win: bool)

const ARENA_MARGIN := Vector2(90, 80)
# Extra headroom at the top: under the tilted camera the boss body draws about
# 150px above its own floor position, and it must not run off screen.
const ARENA_TOP := 260.0
const ARENA_SEED := 11
const ARENA_FACETS := 10
const JAIL := "res://scenes/hub.tscn"
## Which boss, scenery and floor shape each cell's fight uses. A fight started
## without a cell (from the editor or a check) is cell III's.
const BOSSES := {
	1: {"name": "THE TURNKEY", "boss": "res://scripts/bosses/turnkey.gd", "env": "res://scripts/envs/treasure_env.gd", "floor": "octagon", "radius": 28.0},
	2: {"name": "THE PENDULUM", "boss": "res://scripts/bosses/pendulum.gd", "env": "res://scripts/envs/library_env.gd", "floor": "hall", "radius": 0.0},
	3: {"name": "THE PRISM", "boss": "res://scripts/boss.gd", "env": "res://scripts/arena_env.gd", "floor": "gem", "radius": 46.0},
	4: {"name": "THE HOURGLASS", "boss": "res://scripts/bosses/hourglass.gd", "env": "res://scripts/envs/desert_env.gd", "floor": "round", "radius": 40.0},
	5: {"name": "THE MIRROR", "boss": "res://scripts/bosses/mirror.gd", "env": "res://scripts/envs/mind_env.gd", "floor": "circle", "radius": 30.0},
}
const DEFAULT_CELL := 3
const PICKUP_DIST := 50.0

var arena_rect: Rect2            # bounding box of the arena; scenery lays out around it
var arena_poly: PackedVector2Array   # the walkable floor itself
var floor_scale := 1.0           # the Hourglass's sand shrinks the floor toward its centre
var boss: CharacterBody2D
var _shake := 0.0
var _elapsed := 0.0
var _hits_taken := 0
var _over := false
var _won := false
var _crystal := Vector2.INF      # dropped sapphire on the floor; INF when there is none
var _cam_tw: Tween

@onready var camera: Camera2D = $Camera2D
@onready var player: CharacterBody2D = $Player


func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	arena_rect = Rect2(ARENA_MARGIN.x, ARENA_TOP,
		vp.x - ARENA_MARGIN.x * 2.0, vp.y - ARENA_TOP - ARENA_MARGIN.y)
	camera.position = vp * 0.5
	player.position.x = vp.x * 0.5
	var spec: Dictionary = BOSSES.get(Game.current_boss, BOSSES[DEFAULT_CELL])
	_build_arena_poly(spec["floor"])
	_spawn(spec)
	$UI/HUD.boss_name = spec["name"]

	player.hit_taken.connect(func(): _hits_taken += 1)
	player.died.connect(_on_player_died)
	boss.died.connect(_on_boss_died)
	boss.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	if not _over:
		_elapsed += delta

	if _crystal != Vector2.INF and player.global_position.distance_to(_crystal) < PICKUP_DIST:
		_take_crystal()

	if Input.is_action_just_pressed("restart"):
		if _won:
			get_tree().change_scene_to_file(JAIL)
		else:
			get_tree().reload_current_scene()

	# screen shake decay
	if _shake > 0.0:
		_shake = max(0.0, _shake - delta * 42.0)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 0.3)

	queue_redraw()


## The boss and its scenery for this cell, built in code so one fight scene
## serves every cell. The boss stands a little behind the middle of the floor.
func _spawn(spec: Dictionary) -> void:
	boss = CharacterBody2D.new()
	boss.name = "Boss"
	boss.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	boss.position = Vector2(arena_rect.get_center().x, arena_rect.position.y + 170.0)
	boss.set_script(load(spec["boss"]))
	if spec["radius"] > 0.0:
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = spec["radius"]
		boss.add_child(shape)
	add_child(boss)
	var env := Node2D.new()
	env.name = "Environment"
	env.set_script(load(spec["env"]))
	add_child(env)


## The floor's outline inside arena_rect. "gem" is the Prism's ten irregular
## facets with deep cuts at the sides; the rest are plainer shapes that suit
## their rooms. Fixed seed, so a room's floor is the same every run.
func _build_arena_poly(shape: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ARENA_SEED
	var c := arena_rect.get_center()
	var h := arena_rect.size * 0.5
	arena_poly = PackedVector2Array()
	match shape:
		"octagon":
			for i in 8:
				var a := TAU * (i + 0.5) / 8.0
				arena_poly.append(c + Vector2(cos(a), sin(a)) * h)
		"hall":
			var r := arena_rect.grow(-6.0)
			var k := 80.0
			arena_poly = PackedVector2Array([r.position + Vector2(k, 0), Vector2(r.end.x - k, r.position.y),
				Vector2(r.end.x, r.position.y + k), Vector2(r.end.x, r.end.y - k), r.end - Vector2(k, 0),
				Vector2(r.position.x + k, r.end.y), Vector2(r.position.x, r.end.y - k), r.position + Vector2(0, k)])
		"round", "circle":
			var n := 24 if shape == "round" else 40
			for i in n:
				var a := TAU * i / n
				var r := rng.randf_range(0.9, 1.0) if shape == "round" else 0.98
				arena_poly.append(c + Vector2(cos(a), sin(a)) * h * r)
		_:
			for i in ARENA_FACETS:
				var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / ARENA_FACETS
				var d := Vector2(cos(a), sin(a))
				var r := rng.randf_range(0.78, 1.0)
				# deep cuts only at the sides, so the spawn points top and bottom stay well inside
				if absf(d.x) > 0.7 and rng.randf() < 0.55:
					r = rng.randf_range(0.5, 0.62)
				arena_poly.append(c + d * h * r)


## The walkable floor right now: the outline, shrunk toward the middle while
## the Hourglass's sand covers its edges.
func _floor() -> PackedVector2Array:
	if floor_scale >= 0.999:
		return arena_poly
	var c := arena_rect.get_center()
	var out := PackedVector2Array()
	for p in arena_poly:
		out.append(c + (p - c) * floor_scale)
	return out


## Nearest point on the arena floor: p itself when it is already inside.
func clamp_to_arena(p: Vector2) -> Vector2:
	var poly := _floor()
	if Geometry2D.is_point_in_polygon(p, poly):
		return p
	var best := p
	var best_d := INF
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


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
	Game.burst(self, pos, color, n, speed)


# --- outcomes --------------------------------------------------------
func _on_phase_changed(_phase: int) -> void:
	add_shake(20.0)
	punch(1.14, 0.12, 0.35)


func _on_player_died() -> void:
	_finish(false)


func _on_boss_died() -> void:
	punch(1.2, 0.15, 0.5)
	_crystal = clamp_to_arena(boss.global_position)
	# the sapphire drops where the boss died; its body must not keep the player off it
	boss.collision_layer = 0
	boss.collision_mask = 0


func _take_crystal() -> void:
	spawn_burst(_crystal, Game.PALE_JADE, 24, 320.0)
	add_shake(10.0)
	if Game.current_boss > 0:
		Game.crystals[Game.current_boss] = "carried"
	_crystal = Vector2.INF
	_finish(true)


func _finish(win: bool) -> void:
	if _over:
		return
	_over = true
	_won = win
	run_over.emit(win)
	Game.hit_stop(0.15)
	var hud := $UI/HUD
	Game.record_run(_elapsed, _hits_taken)
	hud.show_result(win, _elapsed, _hits_taken)


func _draw() -> void:
	# arena floor + border. The floor is lifted a little off the pure Deep Moss
	# clear colour so the ground shadows under both fighters have something to
	# darken; still only the two locked greens, mixed.
	draw_colored_polygon(arena_poly, Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, 0.13))
	draw_polyline(arena_poly + PackedVector2Array([arena_poly[0]]), Color(Game.SAPPHIRE_CORE, 0.5), 2.0)

	# the dropped sapphire: a floating gem over its shadow. Its lit face is Pale
	# Jade because it is a "look now" moment -- the one thing to go and get.
	if _crystal != Vector2.INF:
		var bob := sin(_elapsed * 3.0) * 5.0
		draw_set_transform(_crystal)
		draw_colored_polygon(Game.ellipse(16, 5), Color(Game.DEEP_MOSS, 0.6))
		var top := Vector2(0, -58 + bob)
		var mid := -36.0 + bob
		var bot := Vector2(0, -14 + bob)
		draw_colored_polygon(PackedVector2Array([top, Vector2(-13, mid), bot]), Game.SAPPHIRE_CORE)
		draw_colored_polygon(PackedVector2Array([top, Vector2(13, mid), bot]),
			Color(Game.PALE_JADE, 0.6 + 0.4 * sin(_elapsed * 5.0)))
		draw_set_transform(Vector2.ZERO)
