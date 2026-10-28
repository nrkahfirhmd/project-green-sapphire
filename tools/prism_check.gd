extends Node
## Smoke check for the Prism: six phases at 50/40/30/20/10 alternating tune
## and add, spikes that block the player and bounce a ricochet, Slam leaving
## its spike line, a beam splitting through a spike, Charge sticking on an old
## spike (not a fresh one), and Spectrum's gap being safe.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/prism_check.tscn


func _ready() -> void:
	Game.current_boss = 3
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	var p: Node = main.player
	b.set_physics_process(false)      # driven by hand below
	p.set_physics_process(false)
	b.player = p

	assert(b.max_hp == 60 and b.phases() == [50, 40, 30, 20, 10], "health / phases wrong")

	# what each phase brings: tune on odd phases, a new attack on even ones
	var pools := {}
	var speeds := {}
	for ph in range(1, 7):
		b.phase = ph
		speeds[ph] = b._tune()["speed"]
		var seen := {}
		for i in 200:
			seen[b._pick()] = true
		pools[ph] = seen
	assert(not pools[1].has("shardfall") and pools[2].has("shardfall"), "phase 2 should add Shardfall")
	assert(not pools[3].has("lens") and pools[4].has("lens"), "phase 4 should add Lens")
	assert(not pools[5].has("refraction") and pools[6].has("refraction"), "phase 6 should add Refraction")
	assert(speeds[1] == speeds[2] and speeds[3] < speeds[2] and speeds[3] == speeds[4] and speeds[5] < speeds[4] and speeds[5] == speeds[6],
		"tuning should only change on phases 3 and 5: %s" % speeds)
	b.phase = 1

	# spikes block walking and bounce a ricochet
	b._spikes = [{"p": Vector2(900, 600), "t": 4.0, "age": 1.0}]
	var pushed: Vector2 = b.push_out(Vector2(905, 600), 22.0)
	assert(pushed.distance_to(Vector2(900, 600)) >= b.SPIKE_R + 21.9, "spike didn't push the player out")
	assert(b.deflects(Vector2(920, 600), 24.0) != Vector2.ZERO, "spike didn't deflect a ricochet")

	# slam leaves a line of spikes along its aim
	b._spikes = []
	b._aim = Vector2.DOWN
	b.kind = "slam"
	b._activate()
	assert(b._spikes.size() >= 3, "slam left %d spikes" % b._spikes.size())

	# a beam through a spike bends and splits in two
	b._spikes = [{"p": b.global_position + Vector2(0, 200), "t": 4.0, "age": 1.0}]
	var straight: Array = b._beam(b.global_position, Vector2.RIGHT)
	var bent: Array = b._beam(b.global_position, Vector2.DOWN)
	assert(straight.size() == 1, "a beam with no spike in its way shouldn't split")
	assert(bent.size() == 3, "a beam through a spike should become three segments, got %d" % bent.size())

	# charge: an old spike stops it, a fresh one (its own trail) doesn't
	b.state = b.S.ATTACK
	b.kind = "charge"
	b._aim = Vector2.RIGHT
	b._spikes = [{"p": b.global_position + Vector2(40, 0), "t": 4.0, "age": 0.1}]
	b._attack(0.0)
	assert(b.state == b.S.ATTACK, "charge stuck on its own fresh shard")
	b._spikes[0].age = 1.0
	b._attack(0.0)
	assert(b.state == b.S.STUCK, "charge didn't stick on an old spike")

	# spectrum: standing in a ring's gap is safe, anywhere else on it is not
	var hp: int = p.hp
	b._spikes = []
	b.kind = "spectrum"
	b.state = b.S.ATTACK
	b._gaps.assign([0.0])
	b._ring_hit.assign([false])
	b._elapsed = b.RING_TIME * 0.5
	var r: float = lerpf(b.RING_FROM, b.RING_TO, 0.5)
	p.global_position = b.global_position + Vector2(r, 0)     # angle 0: in the gap
	b._attack(0.0)
	assert(p.hp == hp, "the ring's gap wasn't safe")
	p.global_position = b.global_position + Vector2(0, r)     # 90 degrees round: on the ring
	b._attack(0.0)
	assert(p.hp == hp - 1, "standing on the ring didn't hurt")

	Game.current_boss = 0
	print("prism_check: phases, spikes, slam line, beam split, charge stick and spectrum gap all behave")
	get_tree().quit()
