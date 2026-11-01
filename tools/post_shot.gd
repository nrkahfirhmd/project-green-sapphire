extends Node
## Dev-only: saves the fight in cell 1 caught mid-way through each post effect
## (shock, scramble, dissolve, low health) to user://post/ or --out=DIR.
##
##   Godot --path . --resolution 1950x900 tools/post_shot.tscn -- [--out=DIR]

func _ready() -> void:
	var out := "user://post"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	Game.current_boss = 1
	var node: Node = load("res://scenes/main.tscn").instantiate()
	add_child(node)
	await get_tree().create_timer(2.0).timeout
	var boss: Node2D = get_tree().get_first_node_in_group("boss")
	var pl: Node2D = get_tree().get_first_node_in_group("player")
	boss.set_physics_process(false)
	Post.shock(boss.global_position, 1.0)
	await get_tree().create_timer(0.25).timeout
	await _save(out, "shock")
	Post.scramble(pl.global_position + Vector2(0, -30), 0.16)
	await get_tree().create_timer(0.03).timeout
	await _save(out, "scramble")
	Post.fade = 0.5
	await get_tree().create_timer(0.4).timeout
	await _save(out, "dissolve")
	Post.fade = 0.0
	pl.hp = 1
	await get_tree().create_timer(1.2).timeout
	await _save(out, "lowhp")
	print("post_shot: saved to ", out)
	get_tree().quit()


func _save(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
