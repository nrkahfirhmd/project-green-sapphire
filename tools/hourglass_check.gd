extends Node
## Smoke check for the Hourglass: precise flips only through the lit neck,
## light off-centre thrusts crack and spill the glass, Time's Up when the
## clock runs dry, Rewind heals unless broken, sand trails slow, quicksand
## pulls (phase 2 only), and phase 2 echoes replay attacks.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/hourglass_check.tscn


func _ready() -> void:
	Game.current_boss = 4
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	var p: Node = main.player
	b.set_physics_process(false)      # driven by hand below
	p.set_physics_process(false)
	b.player = p
	var c: Vector2 = b.global_position

	assert(b.max_hp == 40 and b.phases() == [20], "health / phases wrong")

	# a dead-centre thrust while the neck is dark does nothing special
	b.sand = 0.4
	b.on_thrust(c + Vector2(-150, 0), c + Vector2(10, 0), 34.0)
	assert(b.state != b.S.STUN and b.sand == 0.4, "flipped with the neck dark")
	# ...while it's lit (after an attack), it flips: bulb refills, floor won back, stunned
	b._floor_goal = 0.7
	b._neck_t = 1.0
	b.on_thrust(c + Vector2(-150, 0), c + Vector2(10, 0), 34.0)
	assert(b.state == b.S.STUN and b.sand == 1.0 and b._floor_goal > 0.7, "centre thrust through the lit neck didn't flip")

	# light thrusts off-centre crack a bulb; the third spills it
	b.state = b.S.IDLE
	b.cracks = [0, 0]
	for i in 2:
		b.on_thrust(c + Vector2(-150, -40), c + Vector2(10, -40), 34.0)
	assert(b.cracks[0] + b.cracks[1] == 2 and b.state == b.S.IDLE, "two light thrusts should leave two cracks")
	b.on_thrust(c + Vector2(-150, -40), c + Vector2(10, -40), 34.0)
	assert(b.state == b.S.STUN and b.cracks[0] + b.cracks[1] == 0, "third crack didn't spill the bulb")
	b.state = b.S.IDLE
	b.on_thrust(c + Vector2(-150, -40), c + Vector2(10, -40), 70.0)
	assert(b.cracks[0] + b.cracks[1] == 0, "a heavy thrust shouldn't crack")

	# time's up: the clock runs dry and the burst catches a nearby player
	var hp: int = p.hp
	p.global_position = c + Vector2(200, 0)
	p.invulnerable = false
	b.sand = 0.0
	b._wait = 99.0
	b._think(0.0)
	assert(b.kind == "timesup" and b.state == b.S.TELEGRAPH, "empty clock didn't start Time's Up")
	b._activate()
	assert(p.hp == hp - 2, "Time's Up didn't hit")
	assert(b.sand == 1.0, "the clock didn't refill after Time's Up")

	# rewind heals what it lost since... unless two hits break it
	b.hp = 30
	b._history = [{"t": 0.0, "p": c + Vector2(-100, 0), "hp": 34}]
	b.state = b.S.IDLE
	b._begin("rewind")
	b._activate()
	assert(b.hp == 34, "rewind didn't heal back")
	b._history = [{"t": 0.0, "p": c, "hp": 38}]
	b.state = b.S.IDLE
	b._begin("rewind")
	b.take_hit(1, c)
	b.take_hit(1, c)
	assert(b.state == b.S.STUN, "two hits during the warning didn't break the rewind")

	# sand trail slows; quicksand pulls, and only exists from phase 2
	b._trail = [{"p": Vector2(700, 600), "t": 2.0}]
	assert(b.slow_at(Vector2(710, 600)) < 1.0 and b.slow_at(Vector2(900, 600)) == 1.0, "sand trail slow wrong")
	b.phase = 1
	var seen := {}
	for i in 200:
		seen[b._pick()] = true
	assert(not seen.has("quicksand"), "quicksand before phase 2")
	b.phase = 2
	b._pits = [{"p": Vector2(1000, 600), "t": 3.0}]
	assert(b.pull_at(Vector2(1050, 600)).x < 0.0, "quicksand didn't pull toward its middle")

	# phase 2: a sandfall echoes 2 s later
	b._echoes = []
	b._spots.assign([Vector2(800, 650)])
	b.kind = "sandfall"
	b._activate()
	assert(b._echoes.size() == 1, "phase 2 sandfall didn't schedule an echo")
	b._tick_ground(b.ECHO_DELAY + 0.1)
	assert(b._echoes.is_empty() and not b._ghosts.is_empty(), "the echo didn't replay")

	Game.current_boss = 0
	print("hourglass_check: neck flip, cracks, time's up, rewind, sand, quicksand and echoes all behave")
	get_tree().quit()
