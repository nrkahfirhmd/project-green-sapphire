extends Node
## Dev-only: saves a screenshot of each fight scenery and the jail, with and
## without the ASCII pass (and the title screen with "home"), to user://shots/ (or the folder given by --out=).
##
##   Godot --path . --resolution 1950x900 tools/shot.tscn -- [1 2 3 4 5 hub home] [--out=DIR]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "user://shots"
	var which: Array = []
	for a in args:
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		else:
			which.append(a)
	if which.is_empty():
		which = ["1", "2", "3", "4", "5", "hub"]
	DirAccess.make_dir_recursive_absolute(out)
	for w in which:
		var scene := "res://scenes/%s.tscn" % w if w in ["hub", "home"] else "res://scenes/main.tscn"
		Game.current_boss = int(w) if w.is_valid_int() else 0
		var node: Node = load(scene).instantiate()
		add_child(node)
		await get_tree().create_timer(2.5).timeout
		var ui := node.get_node_or_null("UI")
		if ui:
			ui.visible = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(w + "_ascii.png"))
		node.get_node("Ascii").visible = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(w + "_raw.png"))
		node.queue_free()
		await get_tree().process_frame
	print("shot: saved ", which, " to ", out)
	get_tree().quit()
