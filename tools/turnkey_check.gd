extends Node
## Smoke check for the Turnkey's rapier mechanics: picking three keys breaks
## the shield, a parried key hurts the core, the Wall barrier deflects a
## ricochet, an escaped Lock recasts on the player, the phases start at 18
## and 10, and only an aligned dial key opens the shield.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/turnkey_check.tscn


func _ready() -> void:
	Game.current_boss = 1
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	var p: Node = main.player
	b.set_physics_process(false)      # driven by hand below
	p.set_physics_process(false)
	b.player = p                      # normally found in its physics step
	var K: Dictionary = b.K

	assert(b.max_hp == 25 and b.phases() == [18, 10], "health / phases wrong")
	assert(not b._can_be_hit(), "core should start shielded")

	# picking: thrust three orbiting keys out
	for i in 3:
		var k: Vector2 = b.keys[i]
		b.on_thrust(k - Vector2(60, 0), k + Vector2(20, 0), 34.0)
	assert(b._can_be_hit(), "three keys out but the shield held")
	assert(b._mode[0] == K.KNOCK and b._mode[3] == K.ORBIT, "knocked the wrong keys")

	# parry: a key flying at the player goes back into the core for 1
	b._open_t = 0.0
	for i in 6:
		b._mode[i] = K.ORBIT
	b._mode[4] = K.FLY
	b.keys[4] = b.global_position + Vector2(300, 0)
	b._vel[4] = Vector2(-900, 0)
	var hp: int = b.hp
	b.on_thrust(b.keys[4] + Vector2(60, 0), b.keys[4] - Vector2(10, 0), 34.0)
	assert(b._mode[4] == K.BACK, "thrust didn't parry the flying key")
	for f in 30:
		b._keys(1.0 / 60.0)
	assert(b.hp == hp - 1, "parried key didn't hurt the core")
	assert(b._can_be_hit(), "parry should stagger the core open")

	# wall barrier: keys in the formation deflect a ricochet
	b.kind = "wall"
	b.state = b.S.ATTACK
	b._mode[5] = K.FORM
	b.keys[5] = Vector2(500, 500)
	assert(b.deflects(Vector2(520, 500), 24.0) != Vector2.ZERO, "wall key didn't deflect")
	b.kind = "volley"
	assert(b.deflects(Vector2(520, 500), 24.0) == Vector2.ZERO, "volley keys shouldn't be solid")

	# lock: escape the ring and it recasts once, centred on the player
	b.state = b.S.IDLE
	b._recast = false
	p.global_position = b.global_position + Vector2(0, 200)
	b._begin("lock")
	b.state = b.S.ATTACK
	b._elapsed = 5.0
	p.global_position = b._origin + Vector2(400, 0)
	b._attack(0.0)
	assert(b._recast and b.state == b.S.TELEGRAPH, "escaped lock didn't recast")
	assert(b._origin.distance_to(p.global_position) < 1.0, "recast isn't centred on the player")

	# phases at 18 and 10
	b._open_t = 5.0
	b.state = b.S.IDLE
	b.take_hit(7, b.global_position)
	assert(b.phase == 2, "phase 2 didn't start at 18")
	b._open_t = 5.0
	b.take_hit(8, b.global_position)
	assert(b.phase == 3, "phase 3 didn't start at 10")

	# dial: only the key lined up with the player opens the shield
	b._open_t = 0.0
	for i in 6:
		b._mode[i] = K.ORBIT
	b._begin("dial")
	b.state = b.S.ATTACK
	p.global_position = b.global_position + Vector2(400, 0)
	var on := -1
	var off := -1
	for i in 6:
		if b._mode[i] == K.DIAL:
			b.keys[i] = b.global_position + Vector2(300, 0).rotated(TAU * i / 6.0)
			if b._aligned(i):
				on = i
			elif off == -1:
				off = i
	assert(on != -1 and off != -1, "test setup: need one aligned and one unaligned dial key")
	var k_off: Vector2 = b.keys[off]
	b.on_thrust(k_off - Vector2(30, 0), k_off + Vector2(30, 0), 34.0)
	assert(not b._can_be_hit(), "an unaligned dial key opened the shield")
	var k_on: Vector2 = b.keys[on]
	b.on_thrust(k_on - Vector2(30, 0), k_on + Vector2(30, 0), 34.0)
	assert(b._can_be_hit(), "the aligned dial key didn't open the shield")

	Game.current_boss = 0
	print("turnkey_check: picking, parry, wall barrier, lock recast, phases and dial all behave")
	get_tree().quit()
