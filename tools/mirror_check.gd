extends Node
## Smoke check for the Mirror, the final exam: it copies ricochet (mirrored),
## blink and the ultimate; echoes lead the player; a clash cracks it and three
## shatter a phase; each memory's counter works (parry and pick keys, riposte
## the blade, spikes and beams, flip the clock); shards break and only the
## real one takes damage.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/mirror_check.tscn


func _ready() -> void:
	Game.current_boss = 5
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	var p: Node = main.player
	b.set_physics_process(false)      # driven by hand below
	p.set_physics_process(false)
	b.player = p
	var mid: Vector2 = main.arena_rect.get_center()

	assert(b.max_hp == 52 and b.phases() == [44, 35, 26, 17, 9], "health / phases wrong")

	# ricochet: copied a second later, from the mirror point, mirrored direction
	p.global_position = mid + Vector2(-300, 40)
	p._move_dir = Vector2(1, -1).normalized()
	p.state = b.P_RICOCHET
	b._watch()
	p.state = b.P_FREE
	b._watch()
	for l in b._later:
		l.t = 0.0
	b.state = b.S.IDLE
	assert(b._start_later() and b.state == b.S.RICO, "ricochet wasn't copied")
	assert(absf(b.global_position.x - (mid.x + 300.0)) < 2.0, "ricochet copy didn't start from the mirror point")
	assert(b._move_dir.x < 0.0 and b._move_dir.y < 0.0, "ricochet copy isn't mirrored")

	# blink: to the mirror point of the landing, then a cut toward the player
	b._later.clear()
	p.state = b.P_BLINK
	b._watch()
	p.global_position = mid + Vector2(-250, 0)
	p.state = b.P_FREE
	b._watch()
	for l in b._later:
		l.t = 0.0
	b.state = b.S.IDLE
	assert(b._start_later() and b.state == b.S.BLINK, "blink wasn't copied")
	assert(absf(b.global_position.x - (mid.x + 250.0)) < 2.0, "blink copy didn't land on the mirror point")

	# ultimate: answered with a star of cuts through the player
	b._later.clear()
	p.state = b.P_ULT
	b._watch()
	p.state = b.P_FREE
	b._watch()
	for l in b._later:
		l.t = 0.0
	b.state = b.S.IDLE
	var hp: int = p.hp
	p.invulnerable = false
	assert(b._start_later() and b.state == b.S.STAR, "ultimate wasn't answered")
	for i in 30:
		b._think(1.0 / 30.0)
		p.invulnerable = false
	assert(p.hp < hp, "the star of cuts never caught a player standing still")
	p.hp = p.MAX_HP

	# echoes aim where the player is heading
	b.global_position = mid
	p.global_position = mid + Vector2(0, 200)
	p.velocity = Vector2(260, 0)
	b._windup("light", b.ECHO_DELAY)
	assert(b._aim.x > 0.3, "echo didn't lead the moving player")
	p.velocity = Vector2.ZERO

	# clash: a thrust crossing its strike cracks it; three skip to the next phase
	b.state = b.S.STRIKE
	b._atk = "light"
	b._aim = Vector2.DOWN
	b.on_thrust(mid + Vector2(-60, 100), mid + Vector2(60, 100), 34.0)
	assert(b.cracks == 1 and b.state == b.S.STUN, "clash didn't crack and stun it")
	for i in 2:
		b.state = b.S.STRIKE
		b.on_thrust(mid + Vector2(-60, 100), mid + Vector2(60, 100), 34.0)
	assert(b.phase == 2 and b.hp == 44, "three cracks didn't shatter it into phase 2 (phase %d, hp %d)" % [b.phase, b.hp])

	# phase 2, the Turnkey: a parried key hurts it; three picked keys stun it
	assert(b._keys.size() == b.KEYS, "no keys in the Turnkey's memory")
	b.state = b.S.IDLE
	var k0: Dictionary = b._keys[0]
	k0.mode = "fly"
	k0.p = mid + Vector2(0, 150)
	b.on_thrust(mid + Vector2(-40, 150), mid + Vector2(40, 150), 34.0)
	assert(k0.mode == "back", "flying key wasn't parried")
	hp = b.hp
	for i in 60:
		b._memories(1.0 / 60.0)
	assert(b.hp == hp - b.PARRY_DMG, "parried key didn't hurt it")
	b.state = b.S.IDLE
	for i in 3:
		var k: Dictionary = b._keys[i + 1] if i < 3 else b._keys[0]
		k.mode = "orbit"
		k.p = mid + Vector2(i * 80, 300)
		b.on_thrust(k.p - Vector2(30, 0), k.p + Vector2(30, 0), 34.0)
	assert(b.state == b.S.STUN, "three picked keys didn't stun it")

	# phase 3, the Pendulum: riposte the blade in reach and it's stunned
	b.take_hit(b.hp - 35, mid, true)
	assert(b.phase == 3, "phase 3 didn't start at 35")
	b.state = b.S.IDLE
	var tip: Vector2 = b._blade_tip()
	p.global_position = tip + Vector2(0, 120)
	b.on_thrust(p.global_position, tip, 34.0)
	assert(b.state == b.S.STUN and b._blade_stop > 0.0, "blade riposte didn't stun it")

	# phase 4, the Prism: spikes block and deflect; a beam splits through one
	b.take_hit(b.hp - 26, mid, true)
	assert(b.phase == 4, "phase 4 didn't start at 26")
	b._spikes = [{"p": b.global_position + Vector2(0, 200), "t": 4.0, "age": 1.0}]
	assert(b.push_out(b.global_position + Vector2(0, 205), 22.0).distance_to(b.global_position + Vector2(0, 200)) >= 43.9, "spike didn't block")
	assert(b.deflects(b.global_position + Vector2(10, 200), 24.0) != Vector2.ZERO, "spike didn't deflect")
	assert(b._beam(b.global_position, Vector2.DOWN).size() == 3, "beam didn't split through the spike")

	# phase 5, the Hourglass: an empty clock brings Time's Up; a centre thrust through the lit neck flips it
	b.take_hit(b.hp - 17, mid, true)
	assert(b.phase == 5, "phase 5 didn't start at 17")
	b.state = b.S.IDLE
	b._clock = 0.0001
	b._memories(0.1)
	assert(b.state == b.S.TIMESUP, "empty clock didn't bring Time's Up")
	b.state = b.S.IDLE
	b._clock = 0.3
	b._neck_t = 1.0
	b.on_thrust(b.global_position + Vector2(-150, 0), b.global_position + Vector2(10, 0), 34.0)
	assert(b._clock == 1.0 and b.state == b.S.STUN, "centre thrust through the lit neck didn't flip the clock")

	# phase 6, Shatter: three shards; a shard breaks from a hit, only the real one takes damage
	b.take_hit(b.hp - 9, mid, true)
	assert(b.phase == 6 and b._shards.size() == 3, "Shatter didn't bring three shards")
	b.state = b.S.IDLE
	var sh: Dictionary = b._shards[0]
	sh.pup.global_position = mid + Vector2(400, 0)
	hp = b.hp
	b.on_thrust(mid + Vector2(340, 0), mid + Vector2(420, 0), 34.0)
	assert(not sh.alive and b.hp == hp, "shard didn't break, or the hit leaked to the real one")

	Game.current_boss = 0
	print("mirror_check: copies, echoes, clash, keys, blade, spikes, clock and shards all behave")
	get_tree().quit()
