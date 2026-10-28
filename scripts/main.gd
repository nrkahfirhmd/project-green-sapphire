extends Node2D
## Arena, camera shake, particle bursts, run timer, win/lose, restart.
## A fight opens on the boss-intro card with input locked until it fades. A
## win drops a sapphire where the boss died; picking it up ends the run, and
## CONTINUE takes the player back to the jail with it. Esc or the pause
## button opens the pause sheet.

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
	1: {"boss": "res://scripts/bosses/turnkey.gd", "env": "res://scripts/envs/treasure_env.gd", "floor": "octagon", "radius": 28.0},
	2: {"boss": "res://scripts/bosses/pendulum.gd", "env": "res://scripts/envs/library_env.gd", "floor": "hall", "radius": 0.0},
	3: {"boss": "res://scripts/bosses/prism.gd", "env": "res://scripts/arena_env.gd", "floor": "gem", "radius": 46.0},
	4: {"boss": "res://scripts/bosses/hourglass.gd", "env": "res://scripts/envs/desert_env.gd", "floor": "round", "radius": 40.0},
	5: {"boss": "res://scripts/bosses/mirror.gd", "env": "res://scripts/envs/mind_env.gd", "floor": "circle", "radius": 30.0},
}
const DEFAULT_CELL := 3
const PICKUP_DIST := 50.0
const SHAKE_MAX := 26.0           # camera offset at full trauma
const DROP_TIME := 0.8           # the sapphire's fall from a beaten boss
const Pause := preload("res://scripts/ui/pause_menu.gd")
const UI := preload("res://scripts/ui/ui.gd")

var arena_rect: Rect2            # bounding box of the arena; scenery lays out around it
var arena_poly: PackedVector2Array   # the walkable floor itself
var floor_scale := 1.0           # the Hourglass's sand shrinks the floor toward its centre
var boss: CharacterBody2D
var cell := DEFAULT_CELL
var _playing := false            # false until the boss intro releases input
var _pause: Control
var _trauma := 0.0               # camera shake, 0..1; the offset grows with its square
var _noise := FastNoiseLite.new()
var _shake_t := 0.0
var _elapsed := 0.0
var _hits_taken := 0
var _over := false
var _won := false
var _crystal := Vector2.INF      # dropped sapphire on the floor; INF when there is none
var _drop_from := Vector2.ZERO   # the boss's floor point, where the sapphire was thrown from
var _drop_t := 1.0               # 0..1 through its fall; 1 when it's on the floor
var _picked := Vector2.INF       # where it was picked up, for the flash that follows
var _picked_t := 0.0
var _cam_tw: Tween

@onready var camera: Camera2D = $Camera2D
@onready var player: CharacterBody2D = $Player


func _ready() -> void:
	randomize()
	_noise.frequency = 0.9
	var vp := get_viewport_rect().size
	arena_rect = Rect2(ARENA_MARGIN.x, ARENA_TOP,
		vp.x - ARENA_MARGIN.x * 2.0, vp.y - ARENA_TOP - ARENA_MARGIN.y)
	camera.position = vp * 0.5
	player.position.x = vp.x * 0.5
	cell = Game.current_boss if BOSSES.has(Game.current_boss) else DEFAULT_CELL
	var spec: Dictionary = BOSSES[cell]
	Sfx.ambience("cell%d" % cell)
	_build_arena_poly(spec["floor"])
	_spawn(spec)

	var hud := $UI/HUD
	hud.cell = cell
	hud.continue_pressed.connect(_to_jail)
	hud.jail_pressed.connect(_to_jail)
	hud.retry_pressed.connect(func(): Game.go(""))
	hud.intro_released.connect(_release)
	_pause = Pause.new()
	_pause.setup("BACK TO JAIL", JAIL, func():
		return "%s · %s · %s" % [Game.NUMERALS[cell], Game.BOSS_NAMES[cell], UI.fmt_time(_elapsed)])
	$UI.add_child(_pause)

	# hold everything still behind the intro card
	player.set_physics_process(false)
	boss.set_physics_process(false)
	$UI/TouchControls.locked = true
	hud.play_intro()

	player.hit_taken.connect(func(): _hits_taken += 1)
	player.died.connect(_on_player_died)
	boss.died.connect(_on_boss_died)
	boss.phase_changed.connect(_on_phase_changed)


func _release() -> void:
	_playing = true
	player.set_physics_process(true)
	boss.set_physics_process(true)
	$UI/TouchControls.locked = false
	$UI/HUD.timing = true


func _to_jail() -> void:
	Game.go(JAIL)


func _process(delta: float) -> void:
	if _playing and not _over:
		_elapsed += delta

	if _crystal != Vector2.INF and player.global_position.distance_to(_crystal) < PICKUP_DIST:
		_take_crystal()

	if Input.is_action_just_pressed("restart"):
		if _won:
			_to_jail()
		else:
			Game.go("")

	# screen shake: smooth noise rather than per-frame jitter, so a big hit
	# rolls the camera instead of buzzing it; trauma falls off in ~0.6 s
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - delta * 1.7)
		_shake_t += delta * 60.0
		var k := SHAKE_MAX * _trauma * _trauma
		camera.offset = Vector2(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t)) * k * 1.6
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 0.3)

	if _drop_t < 1.0:
		_drop_t = minf(1.0, _drop_t + delta / DROP_TIME)
		if _drop_t >= 1.0:
			_on_crystal_landed()
	_picked_t += delta

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


## `amount` is the old pixel scale (2 a tap, 24 the most); it's felt too.
func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount / 30.0)
	Haptics.impact(amount / 20.0)
	Sfx.impact(amount / 20.0)


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


func spawn_ring(pos: Vector2, radius: float, color := Game.SAPPHIRE_CORE, dur := 0.4) -> void:
	Game.ring(self, pos, radius, color, dur)


# --- outcomes --------------------------------------------------------
func _on_phase_changed(_phase: int) -> void:
	Haptics.play("phase")
	Sfx.play("phase", 0.0, 0.0)
	add_shake(20.0)
	punch(1.14, 0.12, 0.35)
	spawn_ring(boss.global_position, 420.0, Game.PALE_JADE, 0.55)
	spawn_ring(boss.global_position, 260.0, Game.SAPPHIRE_CORE, 0.4)


func _on_player_died() -> void:
	Haptics.play("death")
	Sfx.play("death", 0.0, 0.0)
	Game.slow_mo(0.35, 0.7)
	spawn_ring(player.global_position, 220.0, Game.PALE_JADE, 0.6)
	_finish(false)


## The killing blow: the world slows, shockwaves roll out, and the sapphire
## is thrown out of the boss's body in an arc and bounces once on the floor.
func _on_boss_died() -> void:
	Haptics.play("boss_death")
	Sfx.play("boss_death", 0.0, 0.0)
	Game.slow_mo(0.3, 1.1)
	punch(1.2, 0.15, 0.5)
	for i in 3:
		get_tree().create_timer(0.12 * i, true, false, true).timeout.connect(
			spawn_ring.bind(boss.global_position, 260.0 + 140.0 * i, Game.PALE_JADE if i == 0 else Game.SAPPHIRE_CORE, 0.6))
	_crystal = clamp_to_arena(boss.global_position + Vector2(0, 60))
	_drop_from = boss.global_position
	_drop_t = 0.0
	# the sapphire drops where the boss died; its body must not keep the player off it
	boss.collision_layer = 0
	boss.collision_mask = 0


func _on_crystal_landed() -> void:
	Haptics.play("crystal_land")
	Sfx.play("crystal_land")
	spawn_ring(_crystal, 120.0, Game.PALE_JADE, 0.45)
	spawn_burst(_crystal, Game.SAPPHIRE_CORE, 10, 160.0)


func _take_crystal() -> void:
	Haptics.play("pickup")
	Sfx.play("pickup", 0.0, 0.0)
	spawn_burst(_crystal, Game.PALE_JADE, 24, 320.0)
	spawn_ring(_crystal, 200.0, Game.PALE_JADE, 0.5)
	add_shake(10.0)
	if Game.current_boss > 0:
		Game.crystals[Game.current_boss] = "carried"
	_picked = _crystal
	_picked_t = 0.0
	_crystal = Vector2.INF
	_finish(true)


## The sapphire's place on screen as it falls: up out of the body, down to
## the floor, one small bounce. Returns [ground point, lift above it].
func _crystal_air() -> Array:
	var t := _drop_t
	if t < 0.75:
		# a throw: leaves the body 120 up, peaks, lands at t = 0.75
		var u := t / 0.75
		return [_drop_from.lerp(_crystal, u), lerpf(120.0, 0.0, u) + 640.0 * u * (1.0 - u)]
	var v := (t - 0.75) / 0.25
	return [_crystal, 120.0 * v * (1.0 - v)]                       # one small bounce


func _finish(win: bool) -> void:
	if _over:
		return
	_over = true
	_won = win
	run_over.emit(win)
	Haptics.play("win" if win else "lose")
	Sfx.play("win" if win else "lose", 0.0, 0.0)
	_pause.enabled = false
	Game.hit_stop(0.15)
	var flags := Game.record_win(cell, _elapsed, _hits_taken) if win else {}
	$UI/HUD.show_result(win, _elapsed, _hits_taken, flags)


func _draw() -> void:
	# arena floor + border. The floor is lifted a little off the pure Deep Moss
	# clear colour so the ground shadows under both fighters have something to
	# darken; still only the two locked greens, mixed.
	draw_colored_polygon(arena_poly, Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, 0.13))
	draw_polyline(arena_poly + PackedVector2Array([arena_poly[0]]), Color(Game.SAPPHIRE_CORE, 0.5), 2.0)

	# the dropped sapphire: a Pale Jade diamond pulsing 1 <-> 1.25 every 0.8 s
	# and turning slowly (its width breathes like a gem spinning) over its
	# shadow. Jade because it is a "look now" moment, the one thing to go and
	# get. While it falls, its shadow waits on the floor where it will land.
	if _crystal != Vector2.INF:
		var air := _crystal_air()
		var ground: Vector2 = air[0]
		var lift: float = air[1]
		var ms := Time.get_ticks_msec()
		var k := 1.0 + 0.125 * (1.0 - cos(TAU * ms / 800.0))
		var h := 20.0 * k
		var w := h * (0.55 + 0.45 * absf(cos(ms / 600.0)))
		var bob := sin(ms / 400.0) * 4.0 if _drop_t >= 1.0 else 0.0
		var c := ground + Vector2(0, -38 - lift + bob)
		var sh := clampf(1.0 - lift / 200.0, 0.3, 1.0)
		draw_set_transform(_crystal)
		draw_colored_polygon(Game.ellipse(16 * sh, 5 * sh), Color(Game.DEEP_MOSS, 0.6))
		draw_set_transform(Vector2.ZERO)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, 0), c + Vector2(0, h), c + Vector2(-w, 0)]), Game.PALE_JADE)
		# a glint crossing its face
		var g := fmod(ms / 1400.0, 1.0)
		if g < 0.3:
			var gy := lerpf(-h, h, g / 0.3)
			var gx := w * (1.0 - absf(gy) / h)
			draw_line(c + Vector2(-gx, gy), c + Vector2(gx, gy), Game.SAPPHIRE_CORE, 3.0)

	# picked up: it rises off the player and fades
	if _picked != Vector2.INF and _picked_t < 0.5:
		var u := _picked_t / 0.5
		var c := player.global_position + Vector2(0, -60.0 - 90.0 * (1.0 - pow(1.0 - u, 3.0)))
		var h := 20.0 * (1.0 + u)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]), Color(Game.PALE_JADE, 1.0 - u))
