extends Node
## Smoke check for the sapphire loop: a beaten boss drops a sapphire the player
## can pick up, the altar takes carried sapphires, four of them unlock the gate,
## and the jail only lets the player walk into cells that are open.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/hub_check.tscn


func _ready() -> void:
	Game.crystals = {}
	await _fight_drops_a_sapphire()
	await _altar_and_gate()
	print("hub_check: drop, pickup, altar and gate all behave")
	get_tree().quit()


func _fight_drops_a_sapphire() -> void:
	Game.current_boss = 3
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var b := get_tree().get_first_node_in_group("boss")
	var p := get_tree().get_first_node_in_group("player")
	b.take_hit(99, b.global_position + Vector2(0, 50))
	await get_tree().process_frame
	assert(not Game.crystals.has(3), "sapphire counted before it was picked up")
	p.global_position = main._crystal
	await get_tree().process_frame
	assert(Game.crystals.get(3, "") == "carried", "walking onto the sapphire didn't pick it up")
	assert(main._won, "picking up the sapphire didn't end the run as a win")
	main.queue_free()
	await get_tree().process_frame


func _altar_and_gate() -> void:
	Game.current_boss = 0
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	add_child(hub)
	await get_tree().process_frame

	# cell III's sapphire is carried, so III is closed; I is open; the gate is shut
	var cell1: Rect2 = hub.doors[1].cell
	var cell3: Rect2 = hub.doors[3].cell
	var gate: Rect2 = hub.doors[5].cell
	assert(hub.clamp_to_arena(cell1.get_center()) == cell1.get_center(), "open cell I not walkable")
	# a closed door leaves the player on the hall's edge, which the door's own
	# rect shares, so "still in the hall" is the real test
	var hall: Rect2 = hub.hall.grow(0.5)
	assert(hall.has_point(hub.clamp_to_arena(cell3.get_center())), "cleared cell III still walkable")
	assert(hall.has_point(hub.clamp_to_arena(gate.get_center())), "locked gate walkable")
	var near: Vector2 = hub.clamp_to_arena(hub.altar + Vector2(10, 0))
	assert(near.distance_to(hub.altar) >= hub.ALTAR_R - 0.01, "walked through the altar")

	# standing at the altar sets the carried sapphire
	hub.player.global_position = hub.altar + Vector2(0, hub.ALTAR_R + 10.0)
	await get_tree().process_frame
	assert(Game.crystals[3] == "placed", "altar didn't take the carried sapphire")
	assert(not hub._gate_unlocked(), "gate unlocked with one sapphire")

	# the other three: the gate unlocks, lifts, and then lets the player through
	for id in [1, 2, 4]:
		Game.crystals[id] = "placed"
	assert(hub._gate_unlocked(), "four sapphires set but the gate is still locked")
	hub._gate_open = 1.0
	assert(hub.clamp_to_arena(gate.get_center()) == gate.get_center(), "open gate not walkable")
	hub.queue_free()
	Game.crystals = {}
