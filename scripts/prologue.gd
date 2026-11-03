extends Node2D
## The prologue (story beats 1-4, lines in scripts/story.gd): a dark round
## room. The player wakes in a pool of their own light; the fallen knight
## steps out of the dark and says where they are, teaches every control one
## at a time, then spars. Beaten, he names the way out, and the iris closes
## onto the jail, where the player wakes a second time (hub.gd).
##
## The room is lit only where someone stands: a soft pool under the player
## and one under the knight, laid down as stacked faint ellipses. Past them
## the floor stays black, which the ASCII pass turns deep green.
##
## A step waits on what the player actually does (player.state changing),
## not on keys, so keyboard and touch both count. While anyone talks
## everything holds still and the touch controls step aside. The player
## can't lose here: the knight's blows only shove (knight.gd).
##
## Leaving by any route (the end, or SKIP TO THE JAIL in the pause sheet)
## marks the prologue done, so PLAY goes straight to the jail after.

signal step_done

const JAIL := "res://scenes/hub.tscn"
const Story := preload("res://scripts/story.gd")
const Dialogue := preload("res://scripts/ui/dialogue.gd")
const Pause := preload("res://scripts/ui/pause_menu.gd")
const UI := preload("res://scripts/ui/ui.gd")
const KNIGHT := "res://scripts/bosses/knight.gd"
const ROOM := Vector2(700, 290)   # the floor's half-size; it is an ellipse
const LIGHT_R := 250.0
const WALK_NEED := 600.0          # units walked for the move step
const SHAKE_MAX := 20.0
## What each step teaches: the action (also the touch button it lights up),
## its name and key, and how many times. "move" counts distance instead.
const STEPS := [
	{"a": "move", "name": "MOVE", "key": "WASD", "touch": "LEFT STICK", "need": 1},
	{"a": "attack_light", "name": "LIGHT ATTACK", "key": "K", "need": 3},
	{"a": "attack_heavy", "name": "HEAVY ATTACK", "key": "L", "need": 2},
	{"a": "dodge", "name": "DODGE", "key": "SPACE", "need": 2},
	{"a": "blink", "name": "BLINK", "key": "I", "need": 1},
	{"a": "ricochet", "name": "RICOCHET", "key": "HOLD J, AIM WITH ARROWS, LET GO", "touch": "HOLD, DRAG BACK, LET GO", "need": 1},
]
const ULT_STEP := {"a": "ultimate", "name": "ULTIMATE", "key": "O", "need": 1}
# player.gd's State enum
const P_DODGE := 1
const P_ATTACK := 2
const P_RICOCHET := 3
const P_BLINK := 4
const P_ULT := 5

var arena_rect: Rect2
var knight: CharacterBody2D
var prompt: Dictionary = {}       # the step on screen, {} for none
var count := 0.0                  # how far through it
var _c: Vector2                   # the room's centre
var _dlg: Control
var _seen := 0                    # player.state last frame
var _last_pos := Vector2.ZERO
var _lit := 0.0                   # the knight's light, 0 dark .. 1
var _ult_told := false
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _shake_t := 0.0
var _cam_tw: Tween

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var touch: Control = $UI/TouchControls


func _ready() -> void:
	var vp := get_viewport_rect().size
	_c = Vector2(vp.x * 0.5, vp.y * 0.56)
	arena_rect = Rect2(_c - ROOM, ROOM * 2.0)
	camera.position = vp * 0.5
	_noise.frequency = 0.9
	player.global_position = _c + Vector2(-260, 70)
	_last_pos = player.global_position
	Sfx.ambience("cell5")
	Music.stop(1.0)

	knight = CharacterBody2D.new()
	knight.name = "Knight"
	knight.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	knight.position = _c + Vector2(250, -40)
	knight.set_script(load(KNIGHT))
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 22.0
	knight.add_child(shape)
	knight.modulate.a = 0.0
	add_child(knight)
	knight.died.connect(_on_knight_down)

	$UI.add_child(Prompt.new(self))
	_dlg = Dialogue.new()
	$UI.add_child(_dlg)
	_dlg.line_started.connect(_on_line)
	var pause := Pause.new()
	pause.setup("SKIP TO THE JAIL", JAIL, func(): return "A DARK ROOM")
	$UI.add_child(pause)
	_run()


func _exit_tree() -> void:
	Game.finish_prologue()


func _run() -> void:
	_hold(true)
	await get_tree().create_timer(1.4).timeout
	await _say(Story.WAKE)
	# his light comes up and he is there, sitting in it
	_hold(true)
	Sfx.play("lamp")
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_lit", 1.0, 1.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(knight, "modulate:a", 1.0, 1.6)
	await tw.finished
	await _say(Story.MEET)
	for step in STEPS:
		await _say(Story.TUTORIAL[step.a])
		await _teach(step)
	await _say(Story.FIGHT)
	knight.fighting = true
	Music.play("boss", 1.0)
	await knight.died
	prompt = {}
	touch.highlight = ""
	await get_tree().create_timer(1.6).timeout
	await _say(Story.DEFEATED)
	# he goes back into the dark, and so does everything else
	_hold(true)
	var out := create_tween().set_parallel()
	out.tween_property(knight, "modulate:a", 0.0, 1.4)
	out.tween_property(self, "_lit", 0.0, 1.4)
	await out.finished
	Game.go(JAIL)


## Everything holds still while the lines play, then lets go. Two physics
## frames of grace first, so the press that closed the box (light attack is
## one of the keys) can't also swing the sword.
func _say(lines: Array) -> void:
	_hold(true)
	_dlg.play(lines)
	await _dlg.finished
	await get_tree().physics_frame
	await get_tree().physics_frame
	_hold(false)


func _hold(on: bool) -> void:
	player.set_physics_process(not on)
	knight.set_physics_process(not on)
	touch.visible = not on
	if on:
		player.velocity = Vector2.ZERO


func _teach(step: Dictionary) -> void:
	prompt = step
	count = 0.0
	touch.highlight = step.a
	await step_done
	touch.highlight = ""
	await get_tree().create_timer(0.8).timeout     # long enough to see it fill
	prompt = {}


## Counts toward the step on screen; a whole step done says so.
func _progress(action: String, n: float) -> void:
	if prompt.is_empty() or prompt.a != action or count >= float(prompt.need):
		return
	count = minf(count + n, float(prompt.need))
	if count >= float(prompt.need):
		Haptics.play("toggle")
		Sfx.play("toggle")
		step_done.emit()
	elif action != "move":
		Haptics.play("tap")


func _process(delta: float) -> void:
	# what the player just started doing
	var s: int = player.state
	if s != _seen:
		_seen = s
		match s:
			P_ATTACK:
				_progress("attack_" + player._atk_name, 1.0)
			P_DODGE:
				_progress("dodge", 1.0)
			P_RICOCHET:
				_progress("ricochet", 1.0)
			P_BLINK:
				_progress("blink", 1.0)
			P_ULT:
				_progress("ultimate", 1.0)
	_progress("move", player.global_position.distance_to(_last_pos) / WALK_NEED)
	_last_pos = player.global_position

	# the first time the ultimate fills mid-fight, he points it out
	if knight.fighting and not knight.dead and not _ult_told and player.ult_ready() and not _dlg.playing:
		_ult_told = true
		_teach_ult()

	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - delta * 1.7)
		_shake_t += delta * 60.0
		var k := SHAKE_MAX * _trauma * _trauma
		camera.offset = Vector2(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t)) * k * 1.6
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 0.3)
	queue_redraw()


func _teach_ult() -> void:
	await _say(Story.ULTIMATE)
	_teach(ULT_STEP)


func _on_knight_down() -> void:
	Haptics.play("win")
	Game.slow_mo(0.35, 0.9)
	punch(1.15, 0.15, 0.5)
	Game.ring(self, knight.global_position, 300.0, Game.PALE_JADE, 0.6)
	knight.collision_layer = 0
	knight.collision_mask = 0


## Lines can be felt in the room, not only in the box.
func _on_line(_who: String, mood: String) -> void:
	if mood == "anger":
		add_shake(8.0)
	elif mood == "fear":
		add_shake(2.0)


# --- the room, for player.gd and the knight ----------------------------
## Inside the floor's ellipse; past it, back to its edge along the radius.
func clamp_to_arena(p: Vector2) -> Vector2:
	var q := (p - _c) / ROOM
	return p if q.length() <= 1.0 else _c + q.normalized() * ROOM


func add_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount / 30.0)
	Haptics.impact(amount / 20.0)
	Sfx.impact(amount / 20.0)


func punch(zoom_scale := 1.08, t_in := 0.07, t_out := 0.20) -> void:
	if _cam_tw and _cam_tw.is_valid():
		_cam_tw.kill()
	camera.zoom = Vector2.ONE
	_cam_tw = create_tween()
	_cam_tw.tween_property(camera, "zoom", Vector2(zoom_scale, zoom_scale), t_in)
	_cam_tw.tween_property(camera, "zoom", Vector2.ONE, t_out).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func spawn_burst(pos: Vector2, color: Color, n := 10, speed := 220.0) -> void:
	Game.burst(self, pos, color, n, speed)


func spawn_ring(pos: Vector2, radius: float, color := Game.SAPPHIRE_CORE, dur := 0.4) -> void:
	Game.ring(self, pos, radius, color, dur)


func _draw() -> void:
	draw_rect(Rect2(-ROOM * 2.0, get_viewport_rect().size + ROOM * 4.0), Game.SHADOW)
	var rim := Game.ellipse(ROOM.x, ROOM.y, 48)
	rim = Transform2D(0.0, _c) * rim
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(Game.SAPPHIRE_CORE, 0.12), 2.0)
	_pool(player.global_position, 1.0)
	if _lit > 0.0:
		_pool(knight.global_position, _lit)


## A pool of light on the floor: stacked faint ellipses, brightest at the feet.
func _pool(at: Vector2, k: float) -> void:
	var col := Color(Game.DEEP_MOSS.lerp(Game.SAPPHIRE_CORE, 0.13), 0.2 * k)
	for i in 6:
		var r := LIGHT_R * (1.0 - i / 6.0)
		draw_colored_polygon(Transform2D(0.0, at) * Game.ellipse(r, r * 0.5, 32), col)


## The step's prompt across the top (its name, its key or touch hint, and
## how far along), and the knight's health once the spar starts.
class Prompt extends Control:
	var scene: Node2D

	func _init(s: Node2D) -> void:
		scene = s
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := UI.CORE
		var cx := size.x * 0.5
		var y := 32.0
		var k: CharacterBody2D = scene.knight
		if k.fighting and not k.dead:
			UI.text(self, Vector2(cx, y), "FALLEN KNIGHT", 20, c, 600, 0.2, 0)
			var segs: int = k.max_hp
			var w := 600.0
			var seg := w / segs
			for i in segs:
				var r := Rect2(cx - w * 0.5 + i * seg + 2.0, y + 34.0, seg - 4.0, 12.0)
				if i < k.hp:
					draw_rect(r, UI.JADE)                 # boss health: one of Jade's five places
				else:
					draw_rect(r, Color(c, 0.4), false, UI.STROKE)
			y += 84.0
		var p: Dictionary = scene.prompt
		if p.is_empty():
			return
		var key: String = p.get("touch", "") if OS.has_feature("mobile") else p.key
		var txt: String = p.name + ("  ·  " + key if key != "" else "")
		UI.text(self, Vector2(cx, y), txt, 26, c, 600, 0.12, 0)
		var dy := y + UI.text_height(26) + 24.0
		var need: int = p.need
		if p.a == "move":
			var bw := 240.0
			draw_rect(Rect2(cx - bw * 0.5, dy - 4.0, bw, 8.0), Color(c, 0.3))
			draw_rect(Rect2(cx - bw * 0.5, dy - 4.0, bw * scene.count, 8.0), c)
		else:
			for i in need:
				UI.diamond(self, Vector2(cx + (i - (need - 1) * 0.5) * 32.0, dy), 18, c, i < int(scene.count))
