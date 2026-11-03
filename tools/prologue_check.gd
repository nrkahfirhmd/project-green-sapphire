extends Node
## Smoke check for the prologue: the dialogue box types a line with its
## voice and haptic, finishes it on a press and moves on with the next, then
## closes; every story line names a known mood and voice; the tutorial counts
## what the player does; the knight can't be hurt until the spar and his
## thrust lands down its strip.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . tools/prologue_check.tscn

const Dialogue := preload("res://scripts/ui/dialogue.gd")
const Story := preload("res://scripts/story.gd")


func _ready() -> void:
	var done_before := Game.prologue_done     # leaving the prologue saves; put it back after
	_lines_are_valid()
	await _dialogue()
	await _prologue()
	Game.prologue_done = done_before
	Game.wake_in_jail = false
	Game._save_settings()
	print("prologue_check: dialogue, story lines, tutorial and knight all behave")
	get_tree().quit()


func _lines_are_valid() -> void:
	var all: Array = Story.WAKE + Story.MEET + Story.FIGHT + Story.ULTIMATE + Story.DEFEATED + Story.JAIL_WAKE
	for k in Story.TUTORIAL:
		all += Story.TUTORIAL[k]
	for l in all:
		assert(Dialogue.MOODS.has(l[1]), "unknown mood: %s" % l[1])
		assert(Dialogue.VOICES.has(l[0]), "unknown speaker: %s" % l[0])


func _dialogue() -> void:
	var d: Control = Dialogue.new()
	add_child(d)
	var ended := [false]
	d.finished.connect(func(): ended[0] = true)
	d.play([["FALLEN KNIGHT", "calm", "Quick cuts first. Strike at nothing, three times, and then again."], ["", "sad", "..."]])
	await get_tree().create_timer(0.4).timeout
	assert(d._shown > 0 and d._shown < d._glyphs.size(), "line didn't start typing")
	assert(Sfx.last == "talk_knight", "no voice blip, got %s" % Sfx.last)
	d.advance()
	assert(d._shown == d._glyphs.size(), "a press didn't finish the line")
	d.advance()
	assert(d._i == 1 and d._mood_name == "sad", "didn't move to the next line")
	await get_tree().create_timer(0.3).timeout
	d.advance()
	d.advance()
	assert(ended[0] and not d.playing, "didn't finish after the last line")
	# straight into another conversation: the first one's fall mustn't hide it
	d.play([["???", "calm", "Again."]])
	await get_tree().create_timer(0.4).timeout
	assert(d.visible and d._shown > 0, "a second conversation was hidden by the first one closing")
	d.queue_free()


func _prologue() -> void:
	var pro: Node = load("res://scenes/prologue.tscn").instantiate()
	add_child(pro)
	await get_tree().process_frame
	var k: CharacterBody2D = pro.knight
	var p: CharacterBody2D = pro.player

	# tutorial: a light attack counts toward the light step and nothing else
	pro.prompt = pro.STEPS[1]
	pro.count = 0.0
	pro._progress("attack_heavy", 1.0)
	assert(pro.count == 0.0, "the wrong action counted")
	for i in 3:
		pro._progress("attack_light", 1.0)
	assert(pro.count == 3.0, "three light attacks didn't fill the step")

	# before the spar the sword glances off him
	var hp: int = k.hp
	k.take_hit(3, k.global_position + Vector2(0, 40))
	assert(k.hp == hp, "knight hurt before the spar")

	# in the spar his thrust lands down its strip, but never hurts
	k.fighting = true
	k.player = p                  # set on his first physics frame, which the opening hold delays
	p.global_position = k.global_position + Vector2(0, 120)
	k._windup()
	assert(k.state == k.S.WINDUP, "no windup")
	p._inv_until = 0.0
	k._strike()
	assert(p.hp == p.MAX_HP, "the knight hurt the player")
	assert(p.velocity.length() > 100.0, "the knight's thrust didn't shove the player")
	k.take_hit(3, k.global_position + Vector2(0, 40))
	assert(k.hp == hp - 3, "knight not hurt in the spar")
	assert(pro.clamp_to_arena(pro._c + Vector2(5000, 0)).distance_to(pro._c + Vector2(pro.ROOM.x, 0)) < 1.0, "room clamp off")
	pro.queue_free()
	await get_tree().process_frame
