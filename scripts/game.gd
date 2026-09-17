extends Node
## Global singleton: locked palette, hit-stop, session-best run stats, settings.

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

## Safe-area rect in viewport units. On iOS the notch and the home indicator
## cover the screen edges, which is exactly where the touch controls and the
## HUD readouts want to sit. Off-device this is simply the whole viewport.
func safe_area(viewport_size: Vector2) -> Rect2:
	var full := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile"):
		return full
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

# --- Session-best tracking (design bible: victory/defeat screen) --------
var best_time := INF
var best_hits := 999
var has_best := false

func record_run(elapsed: float, hits: int) -> void:
	if not has_best or elapsed < best_time:
		best_time = elapsed
	if not has_best or hits < best_hits:
		best_hits = hits
	has_best = true

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
