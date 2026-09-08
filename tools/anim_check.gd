extends Node
## Smoke check for the code-drawn rigs: poses the player and the boss through
## every animated state and redraws each one, so a bad _draw shows up as a
## script error here instead of mid-fight.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/anim_check.tscn
##
## Needs a real window — a --script run skips autoloads and Game never resolves.


func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var p := get_tree().get_first_node_in_group("player")
	var b := get_tree().get_first_node_in_group("boss")
	assert(p != null and b != null, "player or boss missing from the scene")
	# drive the poses by hand instead of letting the state machines advance
	p.set_physics_process(false)
	b.set_physics_process(false)
	b.global_position = Vector2(800, 430)
	p.global_position = Vector2(800, 700)

	# the rig poses off facing — mirror, front or back, sword in front of the
	# body or behind it — so every direction is its own draw path
	var facings := [
		Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT,
		Vector2(1, -1).normalized(), Vector2(-1, 1).normalized(),
	]
	for d in facings:
		p.state = 0
		p.facing = d
		p._face_x = 1.0 if d.x >= 0.0 else -1.0
		p._walk_amp = 1.0
		p._walk = 1.1
		await _settle()

	# both attacks, every phase
	for atk in ["light", "heavy"]:
		for phase in ["windup", "active", "recovery"]:
			p.state = 2
			p._atk_name = atk
			p._atk_phase = phase
			p._atk_dur = 0.1
			p._atk_timer = 0.05
			await _settle()

	# dodge mid-tumble, with afterimages, and a damage flash
	p.state = 1
	p._roll = 2.2
	p._flash = 0.12
	p._ghosts = [{"pos": Vector2(740, 700), "f": 0.0, "age": 0.10},
		{"pos": Vector2(770, 700), "f": 0.0, "age": 0.05}]
	await _settle()
	p.state = 0
	p._ghosts = []

	# boss: every state against every attack, in both phases
	for ph in [1, 2]:
		for st in 5:
			for k in ["slam", "ring", "charge"]:
				b.phase = ph
				b.state = st
				b._kind = k
				b._eye_t = 0.7
				b._t = 0.2
				b._arm_t = 0.9
				b._blink = 0.08
				b._death_t = 0.3
				b._flash = 0.05
				b._aim = Vector2.DOWN
				await _settle()

	print("anim_check: every animated state drew without error")
	get_tree().quit()


func _settle() -> void:
	for n in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("boss"):
		n.queue_redraw()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
