extends Node
## Global singleton: locked palette, hit-stop, session-best run stats.

# --- Locked 3-color palette (design bible) -------------------------------
const DEEP_MOSS := Color("3B4939")     # arena, eye idle, sword grip
const SAPPHIRE_CORE := Color("69A062") # player, muted text, eye mid-charge
const PALE_JADE := Color("BBE2B6")     # boss body, blade, EVERY telegraph flash

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
