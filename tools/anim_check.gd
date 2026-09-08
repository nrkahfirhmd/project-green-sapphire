extends Node
## Smoke check for the code-drawn rigs: poses the player and the boss through
## every animated state and redraws each one, so a bad _draw shows up as a
## script error here instead of mid-fight.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/anim_check.tscn

func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())
	await get_tree().process_frame
	var p := get_tree().get_first_node_in_group("player")
	var b := get_tree().get_first_node_in_group("boss")
	p.set_physics_process(false)
	b.set_physics_process(false)
	b.global_position = Vector2(800, 300)

	# 1. idle / walk pose, player facing the boss
	p.global_position = Vector2(800, 620)
	p.facing = Vector2.UP
	p._walk_amp = 1.0
	p._walk = 1.1
	b._arm_t = 0.15
	await _settle()

	# 2. heavy swing mid-active, boss telegraphing a slam
	p.global_position = Vector2(760, 480)
	p.facing = Vector2(0.3, -1).normalized()
	p._walk_amp = 0.0
	p.state = 2; p._atk_name = "heavy"; p._atk_phase = "active"
	p._atk_dur = 0.08; p._atk_timer = 0.045
	b.state = 1; b._kind = "slam"; b._eye_t = 0.8; b._arm_t = 0.9
	b._aim = Vector2.DOWN
	await _settle()

	# 3. dodge roll mid-spin, boss phase 2 charging
	p.global_position = Vector2(620, 560)
	p.facing = Vector2.RIGHT
	p.state = 1; p._roll = 2.2
	p._ghosts = [{"pos": Vector2(560, 560), "f": 0.0, "age": 0.10},
		{"pos": Vector2(590, 560), "f": 0.0, "age": 0.05}]
	b.phase = 2; b.state = 1; b._kind = "charge"; b._eye_t = 0.95; b._arm_t = 1.0
	b._aim = Vector2(-0.4, 1).normalized()
	await _settle()

	print("anim_check: every animated state drew without error")
	get_tree().quit()


func _settle() -> void:
	for n in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("boss"):
		n.queue_redraw()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
