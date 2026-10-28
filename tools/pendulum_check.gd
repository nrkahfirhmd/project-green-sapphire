extends Node
## Smoke check for the Pendulum's rapier mechanics: a riposte drops the body
## and makes it the target, a riposte into the shelves jams it longer, a
## riposte needs the blade in reach, book piles bounce a ricochet, Unwind
## covers near and far, the phases start at 15 and 10, and riposting a clock
## hand stops the clock.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/pendulum_check.tscn


func _ready() -> void:
	Game.current_boss = 2
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	var p: Node = main.player
	b.set_physics_process(false)      # driven by hand below
	p.set_physics_process(false)
	b.player = p

	assert(b.max_hp == 20 and b.phases() == [15, 10], "health / phases wrong")
	assert(not b._can_be_hit(), "nothing should be hittable at the start")

	# riposte: a swinging blade in reach, met by a thrust, drops the body
	b._begin("swing")
	b.state = b.S.ATTACK
	b.ang = 0.0
	var tip: Vector2 = b._blade(b.ang, b.arm)
	p.global_position = tip + Vector2(0, 120)
	b.on_thrust(p.global_position, tip - Vector2(0, 20), 34.0)
	assert(b.state == b.S.DOWN, "thrust on the blade didn't riposte")
	assert(b._can_be_hit(), "dropped body should be hittable")
	assert(b._timer == b.DOWN_TIME, "riposte away from the shelves should use DOWN_TIME")
	b._think(0.0)
	assert(b.global_position.distance_to(b._body_floor()) < 1.0, "the target should be the body once it's down")

	# the same thrust with the blade far from the player does nothing
	b._idle()
	b._begin("swing")
	b.state = b.S.ATTACK
	tip = b._blade(b.ang, b.arm)
	p.global_position = tip + Vector2(0, 500)
	b.on_thrust(tip + Vector2(0, 60), tip - Vector2(0, 20), 34.0)
	assert(b.state == b.S.ATTACK, "riposted a blade that was out of reach")

	# riposted into the shelves (near the back wall): jammed for longer
	b.ang = PI * 0.5
	b.arm = 60.0
	tip = b._blade(b.ang, b.arm)
	p.global_position = tip + Vector2(0, 100)
	b.on_thrust(p.global_position, tip, 34.0)
	assert(b.state == b.S.DOWN and b._timer == b.JAM_TIME, "riposte into the shelves didn't jam")

	# book piles deflect a ricochet
	b._piles = [{"p": Vector2(600, 600), "t": 2.0}]
	assert(b.deflects(Vector2(620, 600), 24.0) != Vector2.ZERO, "book pile didn't deflect")
	assert(b.deflects(Vector2(800, 600), 24.0) == Vector2.ZERO, "deflected far from any pile")

	# unwind spirals out: its blade passes both close to the rail and far from it
	var near := INF
	var far := 0.0
	for k in 21:
		var d: float = b._blade(TAU * k / 20.0, lerpf(b.UNWIND_FROM, b.UNWIND_TO, k / 20.0)).distance_to(b.pivot)
		near = minf(near, d)
		far = maxf(far, d)
	assert(near <= 130.0 and far >= 470.0, "unwind doesn't cover near and far")

	# phases at 15 and 10
	b.state = b.S.DOWN
	b.take_hit(5, b.global_position)
	assert(b.phase == 2, "phase 2 didn't start at 15")
	b.take_hit(5, b.global_position)
	assert(b.phase == 3, "phase 3 didn't start at 10")

	# clockwork: riposting a hand stops the clock with the body down mid-hall
	b._idle()
	b._begin("clock")
	b.state = b.S.ATTACK
	var hand: Array = b._hands()[1]
	var h_tip: Vector2 = hand[1]
	p.global_position = h_tip + Vector2(0, 150)
	b.on_thrust(p.global_position, h_tip, 34.0)
	assert(b.state == b.S.DOWN, "riposting a clock hand didn't stop the clock")
	assert(b._anchor.distance_to(main.arena_rect.get_center()) < 1.0, "the body should drop mid-hall")

	Game.current_boss = 0
	print("pendulum_check: riposte, jam, reach, piles, unwind, phases and clockwork all behave")
	get_tree().quit()
