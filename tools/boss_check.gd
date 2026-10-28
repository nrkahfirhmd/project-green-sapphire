extends Node
## Smoke check for all five cells' fights: each boss telegraphs, lands hits
## on a player standing still, can be hurt during its openings, dies, and
## drops a sapphire the player can walk onto to win the run.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/boss_check.tscn
##   ... tools/boss_check.tscn -- cell=4     (one cell; cell=2,3 for several)
##
## Runs in real time (hit-stop resets Engine.time_scale), so it takes a while.

const TIMEOUT := 50.0
const WATCH := 12.0          # let it attack this long before hitting back
const SWING_EVERY := 0.25


func _ready() -> void:
	var cells := [1, 2, 3, 4, 5]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cell="):
			cells = Array(arg.trim_prefix("cell=").split(",")).map(func(x): return int(x))
	for id in cells:
		await _fight(id)
	Game.current_boss = 0
	print("boss_check: every cell's boss attacks, takes hits, dies and drops its sapphire")
	get_tree().quit()


func _fight(id: int) -> void:
	Game.current_boss = id
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var b: Node = main.boss
	var p: Node = main.player
	var hits := [0]
	var tells := [0]
	var died := [false]
	p.hit_taken.connect(func(): hits[0] += 1)
	b.telegraph_started.connect(func(_k): tells[0] += 1)
	b.died.connect(func(): died[0] = true)
	# stand inside every boss's reach: attacks are random, the bottom edge is not
	p.global_position = main.arena_rect.get_center() + Vector2(0, 60)

	var t := 0.0
	var swing := 0.0
	while not died[0] and t < TIMEOUT:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		swing -= dt
		p.hp = p.MAX_HP          # keep the player standing; we only count hits
		if t > WATCH and swing <= 0.0:
			swing = SWING_EVERY
			b.take_hit(3, b.global_position + Vector2(0, 40))
	await get_tree().create_timer(0.3).timeout

	var tag := "cell %d (%s)" % [id, main.BOSSES[id]["name"]]
	print("  %s: %d telegraphs, %d hits on the player, died after %.1fs" % [tag, tells[0], hits[0], t])
	assert(died[0], "%s never died" % tag)
	assert(tells[0] >= 2, "%s barely attacked" % tag)
	assert(hits[0] >= 1, "%s never hit a player standing still" % tag)
	assert(main._crystal != Vector2.INF or main._won, "%s dropped no sapphire" % tag)
	assert(Geometry2D.is_point_in_polygon(main._crystal, main.arena_poly) or main.clamp_to_arena(main._crystal) == main._crystal,
		"%s dropped its sapphire off the floor" % tag)
	# pick it up, as a real run does before the next fight
	if main._crystal != Vector2.INF:
		p.global_position = main._crystal
	await get_tree().create_timer(0.3).timeout
	assert(main._won, "%s: walking onto the sapphire didn't win the run" % tag)
	main.queue_free()
	await get_tree().process_frame
