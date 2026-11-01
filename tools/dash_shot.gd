extends Node
## Dev-only: real dodge dashes in cell 1, slowed down and caught at the
## launch, mid-dash and the brake, raw (no ASCII), to user://dash/ or --out=DIR.
##
##   Godot --path . --resolution 1950x900 tools/dash_shot.tscn -- [--out=DIR]

func _ready() -> void:
	var out := "user://dash"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	Game.current_boss = 1
	var node: Node = load("res://scenes/main.tscn").instantiate()
	add_child(node)
	node.get_node("Ascii").visible = false
	node.get_node("UI").visible = false
	await get_tree().create_timer(1.5).timeout
	get_tree().get_first_node_in_group("boss").process_mode = Node.PROCESS_MODE_DISABLED
	var p: Node2D = get_tree().get_first_node_in_group("player")
	for dir in [Vector2.RIGHT, Vector2.DOWN]:
		p.global_position = Vector2(760, 560) if dir == Vector2.RIGHT else Vector2(975, 420)
		p.facing = dir
		await get_tree().create_timer(0.4).timeout
		Engine.time_scale = 0.05
		p._start_dodge()
		var tag := "r" if dir == Vector2.RIGHT else "d"
		for i in 4:
			await get_tree().create_timer(0.05, true, false, false).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var at := p.get_global_transform_with_canvas().origin
			img.get_region(Rect2i(Vector2i(at) - Vector2i(260, 200), Vector2i(520, 280))).save_png(out.path_join("%s%d.png" % [tag, i]))
		Engine.time_scale = 1.0
	print("dash_shot: saved to ", out)
	get_tree().quit()
