extends Node
## Global singleton: locked palette, hit-stop, settings, jail progress, each
## cell's boss name and the session's best runs.

# --- Settings (persisted to user://) ---------------------------------
const _CFG_PATH := "user://settings.cfg"
var volume := 1.0            # 0..1, Master bus
var haptic_enabled := true

func _ready() -> void:
	_load_settings()
	apply_volume()

func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, volume <= 0.001)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	apply_volume()
	_save_settings()

func set_haptic(on: bool) -> void:
	haptic_enabled = on
	_save_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CFG_PATH) != OK:
		return
	volume = cfg.get_value("audio", "volume", volume)
	haptic_enabled = cfg.get_value("input", "haptic", haptic_enabled)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("input", "haptic", haptic_enabled)
	cfg.save(_CFG_PATH)

# --- Locked 3-color palette (design bible) -------------------------------
const DEEP_MOSS := Color("3B4939")     # arena, eye idle, sword grip
const SAPPHIRE_CORE := Color("69A062") # player, muted text, eye mid-charge
const PALE_JADE := Color("BBE2B6")     # boss body, blade, EVERY telegraph flash

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


## Ellipse polygon centred on the origin. Ground shadows have to be flatter
## than a circle to sit on the floor under the tilted camera.
func ellipse(rx: float, ry: float, segments := 22) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

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

# --- Cells, and the result screen's bests --------------------------------
const NUMERALS := ["", "I", "II", "III", "IV", "V"]
const BOSS_NAMES := {1: "THE TURNKEY", 2: "THE PENDULUM", 3: "THE PRISM", 4: "THE HOURGLASS", 5: "THE MIRROR"}

var bests := {}           # cell -> {"time": float, "hits": int}, wins only, this session
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
	return {"new_time": new_time and not prev.is_empty(), "new_hits": new_hits and not prev.is_empty()}


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
