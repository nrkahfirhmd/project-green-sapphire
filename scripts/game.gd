extends Node
## Global singleton: locked palette, hit-stop, settings, jail progress, each
## cell's boss name and the session's best runs.

# --- Settings (persisted to user://) ---------------------------------
const _CFG_PATH := "user://settings.cfg"
var volume := 1.0            # 0..1, Master bus
var music_volume := 1.0      # 0..1, Music bus
var sfx_volume := 1.0        # 0..1, SFX bus, ambience included
var shake := 1.0             # 0..1, how much of each camera shake lands
var reduced_motion := false  # no shake, tone rings, trails, punch-ins or screen flashes; hit-stop stays, it's timing
var haptic_enabled := true
var button_size := 1.15      # touch buttons: 1, 1.15 or 1.35
var button_layout := {}      # touch button action -> its offset from the safe area's bottom-right, at size 1; unset ones sit at the default
var prologue_done := false   # PLAY skips the prologue once it has been played (or skipped)
var met: Array = []          # cells whose warden has said its first words

func _ready() -> void:
	_load_settings()
	apply_volume()

func apply_volume() -> void:
	_set_bus("Master", volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)

func _set_bus(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, v <= 0.001)

## Sets one of the settings above, applies it and saves.
func change(key: String, value: Variant) -> void:
	set(key, value)
	apply_volume()
	_save_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CFG_PATH) != OK:
		return
	volume = cfg.get_value("audio", "volume", volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	shake = cfg.get_value("motion", "shake", shake)
	reduced_motion = cfg.get_value("motion", "reduced", reduced_motion)
	haptic_enabled = cfg.get_value("input", "haptic", haptic_enabled)
	button_size = maxf(cfg.get_value("input", "button_size", button_size), 1.0)   # 0.9 (the old S) is gone
	button_layout = cfg.get_value("input", "layout", button_layout)
	prologue_done = cfg.get_value("story", "prologue_done", prologue_done)
	met = cfg.get_value("story", "met", met)
	bests = cfg.get_value("records", "bests", bests)
	runs = cfg.get_value("records", "runs", runs)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("motion", "shake", shake)
	cfg.set_value("motion", "reduced", reduced_motion)
	cfg.set_value("input", "haptic", haptic_enabled)
	cfg.set_value("input", "button_size", button_size)
	cfg.set_value("input", "layout", button_layout)
	cfg.set_value("story", "prologue_done", prologue_done)
	cfg.set_value("story", "met", met)
	cfg.set_value("records", "bests", bests)
	cfg.set_value("records", "runs", runs)
	cfg.save(_CFG_PATH)

## What the four roles below look like on screen, in the same order. This is the
## only place to change to recolour the game; boot_splash and the clear colour in
## project.godot match the first.
const SCREEN_PALETTE: Array[Color] = [Color("243023"), Color("3B4939"), Color("69A062"), Color("BBE2B6")]

# --- Locked 4-colour palette (design bible) -------------------------------
# Each layer owns a colour, so depth and focus read at a glance:
#   INK   the dark around the stage, bosses at rest, shadows
#   FLOOR the stage
#   CORE  light on the stage and scenery, UI text
#   CREAM the player, and anything about to hurt
const DEEP_MOSS := Color("1B211A")     # INK: surroundings, boss bodies at rest, sword grip
const FLOOR := Color("628141")         # the stage, boss eye idle
const SAPPHIRE_CORE := Color("8BAE66") # light on scenery, UI text, eye mid-charge
const PALE_JADE := Color("EBD5AB")     # CREAM: player, blade, EVERY telegraph flash
const SHADOW := DEEP_MOSS              # ground shadows: true black would read as a false tint in the dither pass

## Off-device, the safe area of an iPhone 15/16 Pro in landscape (59 pt sides,
## 21 pt bottom), in canvas units: desktop runs and the editor then place the
## UI exactly where the phone will. The notch can be on either side, so both
## sides are inset.
const SIM_INSET_SIDE := 135.0
const SIM_INSET_BOTTOM := 48.0

## Safe-area rect in viewport units. On iOS the notch and the home indicator
## cover the screen edges, which is exactly where the touch controls and the
## HUD readouts want to sit.
func safe_area(viewport_size: Vector2) -> Rect2:
	var full := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile"):
		return Rect2(SIM_INSET_SIDE, 0.0, viewport_size.x - SIM_INSET_SIDE * 2.0, viewport_size.y - SIM_INSET_BOTTOM)
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return full
	# get_display_safe_area() reports screen pixels; the viewport is stretched,
	# so convert before anyone positions anything with it
	var safe := DisplayServer.get_display_safe_area()
	var k := viewport_size / win
	var r := Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k).intersection(full)
	return r if r.get_area() > 0.0 else full


## The one light hangs high over the floor, so every shadow lies straight
## under its caster: a flat ellipse at floor point `at`. Something `height`
## above the floor casts a smaller, fainter one, and the gap between the two
## is what reads as floating. Never thinner than a few dither blocks, or the
## dither pass breaks it into chips.
func shadow(ci: CanvasItem, at: Vector2, rx: float, height := 0.0, fade := 1.0) -> void:
	var k := clampf(1.0 - height / 600.0, 0.5, 1.0)
	var ry := maxf(rx * k * 0.3, 7.0)
	var e := ellipse(maxf(rx * k, ry * 2.4), ry)
	ci.draw_colored_polygon(Transform2D(0.0, at) * e, Color(SHADOW, 0.85 * k * k * fade))


## Ellipse polygon centred on the origin. Ground shadows have to be flatter
## than a circle to sit on the floor under the tilted camera.
func ellipse(rx: float, ry: float, segments := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

# --- Story ----------------------------------------------------------
var wake_in_jail := false    # the prologue just ended: the jail opens on the waking lines

func finish_prologue() -> void:
	wake_in_jail = true
	prologue_done = true
	_save_settings()

func mark_met(cell: int) -> void:
	if not met.has(cell):
		met.append(cell)
		_save_settings()

# --- Jail progress (session only) ---------------------------------------
# Each cell's boss drops a sapphire. It is "carried" until the player sets it
# on the altar in the jail, then "placed". Four placed opens the gate to boss 5.
var current_boss := 0     # the cell the current fight came from; 0 = none
var crystals := {}        # boss id -> "carried" | "placed"

func crystals_placed() -> int:
	var n := 0
	for id in [1, 2, 3, 4]:
		if crystals.get(id, "") == "placed":
			n += 1
	return n

# --- Particles -------------------------------------------------------
## One-shot burst of small squares in a palette colour, parented to `at`.
func burst(at: Node, pos: Vector2, color: Color, n := 10, speed := 220.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = 0.45
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2.ZERO
	p.damping_min = 200.0
	p.damping_max = 400.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	at.add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## A shockwave on the floor: a flat ring (squashed for the tilted camera)
## growing to `radius` and thinning out over `dur`. Drawn under the fighters.
func ring(at: Node, pos: Vector2, radius: float, color := SAPPHIRE_CORE, dur := 0.4, width := 6.0) -> void:
	var r := Ring.new()
	r.position = pos
	r.radius = radius
	r.color = color
	r.dur = dur
	r.width = width
	at.add_child(r)
	at.move_child(r, 0)


class Ring extends Node2D:
	var radius := 100.0
	var color := Color.WHITE
	var dur := 0.4
	var width := 6.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_t / dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)          # fast out, slowing as it spreads
		var r := lerpf(radius * 0.2, radius, e)
		var pts := Game.ellipse(r, r * 0.5, 40)
		pts.append(pts[0])
		draw_polyline(pts, Color(color, 1.0 - k), maxf(1.0, width * (1.0 - k)))


# --- Cells, and the result screen's bests --------------------------------
const BOSS_NAMES := {1: "THE TURNKEY", 2: "THE PENDULUM", 3: "THE PRISM", 4: "THE HOURGLASS", 5: "THE MIRROR"}

var bests := {}           # cell -> {"time": float, "hits": int}, wins only, kept across sessions
var runs: Array = []      # the fastest whole runs, best first: {"time", "hits", "iron"}
const RUNS_KEPT := 5
var iron := false         # this run is permadeath: one defeat and the sapphires are lost
var total_time := 0.0     # summed over won fights, for the ending
var total_hits := 0


## Records a won fight and says whether it set a new best time or hit count.
func record_win(cell: int, elapsed: float, hits: int) -> Dictionary:
	var prev: Dictionary = bests.get(cell, {})
	var new_time := prev.is_empty() or elapsed < float(prev["time"])
	var new_hits := prev.is_empty() or hits < int(prev["hits"])
	bests[cell] = {"time": elapsed if new_time else prev["time"], "hits": hits if new_hits else prev["hits"]}
	total_time += elapsed
	total_hits += hits
	_save_settings()
	return {"new_time": new_time and not prev.is_empty(), "new_hits": new_hits and not prev.is_empty()}


## Files the finished run among the fastest; returns its place (0 = best), or
## -1 when it didn't make the list.
func record_run() -> int:
	var run := {"time": total_time, "hits": total_hits, "iron": iron}
	runs.append(run)
	runs.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	runs = runs.slice(0, RUNS_KEPT)
	_save_settings()
	return runs.find(run)


## A fresh run of the jail: sapphires and totals cleared, bests kept.
func new_game() -> void:
	crystals.clear()
	current_boss = 0
	total_time = 0.0
	total_hits = 0

# --- Hit-stop: brief global freeze on impact (~0.05-0.1s) --------------
var _hitstop_id := 0

func hit_stop(duration: float) -> void:
	_hitstop_id += 1
	var my_id := _hitstop_id
	Engine.time_scale = 0.0
	# ignore_time_scale = true so the timer still ticks while frozen
	await get_tree().create_timer(duration, true, false, true).timeout
	if my_id == _hitstop_id:
		Engine.time_scale = 1.0


## Slow motion for `duration` real seconds (a boss's death), easing back to
## full speed over its last third. A later hit-stop or slow-mo takes over.
func slow_mo(scale: float, duration: float) -> void:
	_hitstop_id += 1
	var my_id := _hitstop_id
	Engine.time_scale = scale
	await get_tree().create_timer(duration * 0.66, true, false, true).timeout
	var steps := 8
	for i in steps:
		if my_id != _hitstop_id:
			return
		Engine.time_scale = lerpf(scale, 1.0, float(i + 1) / steps)
		await get_tree().create_timer(duration * 0.34 / steps, true, false, true).timeout


# --- Scene transitions -----------------------------------------------
## Every scene change is an iris: a circle of Deep Moss closes onto the player
## (or the middle of the screen when there is none), the scene swaps behind
## it, and it opens again from the new scene's player. A change already
## running wins; a second request is dropped.
const IRIS_CLOSE := 0.45
const IRIS_OPEN := 0.5
const IRIS_WIDE := 1.4             # a radius that clears every corner
var _fading := false

func go(path: String) -> void:
	if _fading:
		return
	_fading = true
	var pace := 0.1 if reduced_motion else 1.0   # a near cut instead of the closing circle
	Sfx.play("fade", 0.0, 0.0)
	var layer := CanvasLayer.new()
	layer.layer = 100                  # over the dither pass and the HUD
	var iris := ColorRect.new()
	iris.mouse_filter = Control.MOUSE_FILTER_STOP
	iris.set_anchors_preset(Control.PRESET_FULL_RECT)
	iris.material = ShaderMaterial.new()
	iris.material.shader = preload("res://shaders/iris.gdshader")
	iris.material.set_shader_parameter("radius", IRIS_WIDE)
	iris.material.set_shader_parameter("centre", _focus())
	layer.add_child(iris)
	get_tree().root.add_child(layer)
	var close := iris.create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	close.tween_method(func(r: float): iris.material.set_shader_parameter("radius", r),
		IRIS_WIDE, 0.0, IRIS_CLOSE * pace).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await close.finished
	Engine.time_scale = 1.0
	get_tree().paused = false
	if path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	# open again from wherever the new scene's player stands
	iris.material.set_shader_parameter("centre", _focus())
	var open := iris.create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	open.tween_interval(0.08)
	open.tween_method(func(r: float): iris.material.set_shader_parameter("radius", r),
		0.0, IRIS_WIDE, IRIS_OPEN * pace).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await open.finished
	layer.queue_free()
	_fading = false


## Where the iris centres, in screen UV: the player, else the middle.
func _focus() -> Vector2:
	var p := get_tree().get_first_node_in_group("player") as CanvasItem
	var vp := get_viewport().get_visible_rect().size
	if p and p.is_inside_tree() and p.visible:
		var at := p.get_global_transform_with_canvas().origin + Vector2(0, -50)   # the body, not the feet
		return Vector2(clampf(at.x / vp.x, 0.0, 1.0), clampf(at.y / vp.y, 0.0, 1.0))
	return Vector2(0.5, 0.5)
