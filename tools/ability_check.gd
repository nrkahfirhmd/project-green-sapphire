extends Node
## Smoke check for the rapier kit: the thrusts reach what they claim, the
## ricochet bounces and stays on the floor, the blink teleports along facing
## and cuts through the boss, and the ultimate lands all six cuts, through
## the Turnkey's shield too. A dodge mustn't cut the hurt i-frames short,
## and one that meets a hit while invulnerable pays out a perfect dodge.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/ability_check.tscn


func _ready() -> void:
	await _thrusts()
	await _ricochet()
	await _blink()
	await _ultimate()
	await _iframes()
	Game.current_boss = 0
	print("ability_check: thrusts, ricochet, blink, ultimate and i-frames all behave")
	get_tree().quit()


func _iframes() -> void:
	var f := await _fight(3)
	var p: Node = f[1]
	var b: Node = f[2]
	p.global_position = b.global_position + Vector2(-400, 0)
	var hp: int = p.hp
	p.take_hit(1, p.global_position + Vector2(10, 0))
	assert(p.hp == hp - 1, "the hit didn't land")
	await _frames(12)                   # past the hurt hit-stop
	p._start_dodge()
	await _frames(30)                   # the dodge's own i-frames are long over
	assert(p.invulnerable, "a dodge cut the hurt i-frames short")
	await _frames(40)
	assert(not p.invulnerable, "hurt i-frames never ended")
	p._start_dodge()
	var charge: int = p.ult_charge
	p.take_hit(1, p.global_position + Vector2(10, 0))
	assert(p.hp == hp - 1 and p.ult_charge == charge + 1, "a perfect dodge didn't pay out")
	f[0].queue_free()
	await get_tree().process_frame


## A fight in `cell` with the intro skipped and the boss frozen in place.
func _fight(cell: int) -> Array:
	Game.current_boss = cell
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._release()
	var b: Node = main.boss
	b.set_physics_process(false)
	b.collision_layer = 0
	return [main, main.player, b]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _thrusts() -> void:
	var f := await _fight(3)
	var p: Node = f[1]
	var b: Node = f[2]
	# boss 210 away: past a light thrust (reach 120 + lunge 30 + boss 40),
	# well inside a heavy one (200 + 80 + 40)
	# from below: 210 above the Prism would be off the floor
	p.global_position = b.global_position + Vector2(0, 210)
	p.facing = Vector2.UP
	var hp: int = b.hp
	p._start_attack("light")
	await _frames(30)
	assert(b.hp == hp, "light thrust reached 210")
	p.global_position = b.global_position + Vector2(0, 210)
	p._start_attack("heavy")
	await _frames(50)
	assert(b.hp == hp - 3, "heavy thrust missed at 210")
	# and 90 units off to the side, a thrust straight up misses
	hp = b.hp
	p.global_position = b.global_position + Vector2(90, 100)
	p._start_attack("light")
	await _frames(30)
	assert(b.hp == hp, "light thrust hit 90 units off its line")
	f[0].queue_free()
	await get_tree().process_frame


func _ricochet() -> void:
	var f := await _fight(3)
	var main: Node = f[0]
	var p: Node = f[1]
	var b: Node = f[2]
	var hp: int = b.hp
	p.global_position = b.global_position + Vector2(-200, 0)
	p._start_ricochet(Vector2.RIGHT)
	var first_dir: Vector2 = p._move_dir
	var turned := false
	var was_inv := false
	for i in 120:
		await get_tree().physics_frame
		if i == 5:
			was_inv = p.invulnerable
		# on a bounce it sits exactly on the edge, so allow for rounding
		assert(main.clamp_to_arena(p.global_position).distance_to(p.global_position) < 1.0, "ricochet left the floor")
		if p._move_dir != first_dir:
			turned = true
	assert(turned, "ricochet never bounced")
	assert(b.hp < hp, "ricochet passed the boss without hitting it")
	assert(was_inv, "ricochet should be invulnerable while it runs")
	assert(p.state == 0, "ricochet outlasted its time")
	main.queue_free()
	await get_tree().process_frame


func _blink() -> void:
	var f := await _fight(3)
	var p: Node = f[1]
	var b: Node = f[2]
	var hp: int = b.hp
	var start: Vector2 = b.global_position + Vector2(-150, 0)
	p.global_position = start
	p.facing = Vector2.RIGHT
	p._start_blink()
	await _frames(20)
	assert(absf(p.global_position.x - (start.x + p.BLINK_DIST)) < 2.0 and absf(p.global_position.y - start.y) < 2.0,
		"blink didn't land BLINK_DIST along facing: %s" % p.global_position)
	assert(b.hp == hp - p.BLINK_DMG, "blink didn't cut through the boss")
	f[0].queue_free()
	await get_tree().process_frame


func _ultimate() -> void:
	# the Turnkey's core is shielded while idle; the ultimate cuts through anyway
	var f := await _fight(1)
	var p: Node = f[1]
	var b: Node = f[2]
	assert(not b._can_be_hit(), "turnkey should start shielded")
	var hp: int = b.hp
	p.ult_charge = p.ULT_COST
	p.global_position = b.global_position + Vector2(0, 200)
	assert(p.ult_ready(), "ultimate not ready with a full charge")
	p._start_ult()
	await _frames(70)
	assert(b.hp == hp - p.ULT_SLASHES, "ultimate landed %d of %d cuts" % [hp - b.hp, p.ULT_SLASHES])
	assert(p.ult_charge == 0, "ultimate didn't spend its charge")
	f[0].queue_free()
	await get_tree().process_frame
