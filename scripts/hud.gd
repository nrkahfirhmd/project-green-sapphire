extends Control
## HUD: player HP pips, boss segmented HP bar, telegraph warning,
## run timer, low-HP screen-edge pulse, victory/defeat panel.

var _p_hp := 4
var _p_max := 4
var _b_hp := 12
var _b_max := 12
var _phase := 1
var _tele := 0.0            # telegraph warning flash timer
var _pulse_t := 0.0
var _elapsed := 0.0
var _result_shown := false
var _result_win := false
var _result_time := 0.0
var _result_hits := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame     # let Main spawn player/boss
	var player := get_tree().get_first_node_in_group("player")
	var boss := get_tree().get_first_node_in_group("boss")
	if player:
		player.health_changed.connect(_on_p_health)
	if boss:
		boss.health_changed.connect(_on_b_health)
		boss.phase_changed.connect(func(p): _phase = p)
		boss.telegraph_started.connect(func(_k): _tele = 0.6)


func _on_p_health(cur: int, mx: int) -> void:
	_p_hp = cur
	_p_max = mx

func _on_b_health(cur: int, mx: int) -> void:
	_b_hp = cur
	_b_max = mx


func _process(delta: float) -> void:
	if not _result_shown:
		_elapsed += delta
	_tele = max(0.0, _tele - delta)
	# low-HP pulse: frequency rises as HP drops (no red hue to lean on)
	var frac := float(_p_hp) / float(_p_max)
	if frac <= 0.5 and _p_hp > 0:
		var freq: float = lerpf(3.0, 9.0, 1.0 - frac / 0.5)
		_pulse_t += delta * freq
	queue_redraw()


func show_result(win: bool, elapsed: float, hits: int) -> void:
	_result_shown = true
	_result_win = win
	_result_time = elapsed
	_result_hits = hits


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _draw() -> void:
	var vp := size

	# --- boss segmented HP bar (top center) ---
	var seg_w := 26.0
	var gap := 4.0
	var total := _b_max * seg_w + (_b_max - 1) * gap
	var x0 := (vp.x - total) * 0.5
	var y0 := 26.0
	for i in _b_max:
		var r := Rect2(x0 + i * (seg_w + gap), y0, seg_w, 12.0)
		var filled := i < _b_hp
		if filled:
			draw_rect(r, Game.PALE_JADE)
		else:
			draw_rect(r, Game.DEEP_MOSS)
		draw_rect(r, Game.SAPPHIRE_CORE, false, 1.0)
	if _phase == 2:
		draw_string(ThemeDB.fallback_font, Vector2(x0, y0 + 34),
			"PHASE 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Game.PALE_JADE)

	# --- player HP pips (bottom left) ---
	for i in _p_max:
		var c := Vector2(40 + i * 30, vp.y - 40)
		if i < _p_hp:
			draw_circle(c, 10, Game.SAPPHIRE_CORE)
		else:
			draw_circle(c, 10, Game.DEEP_MOSS)
			draw_arc(c, 10, 0, TAU, 20, Game.SAPPHIRE_CORE, 1.5)

	# --- run timer (top left) ---
	draw_string(ThemeDB.fallback_font, Vector2(30, 40),
		_fmt_time(_elapsed), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Game.SAPPHIRE_CORE)

	# --- telegraph warning flash ---
	if _tele > 0.0:
		var a := _tele / 0.6
		draw_string(ThemeDB.fallback_font, Vector2(vp.x * 0.5 - 60, 90),
			"! INCOMING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(Game.PALE_JADE.r, Game.PALE_JADE.g, Game.PALE_JADE.b, a))

	# --- low-HP screen-edge pulse ---
	var frac := float(_p_hp) / float(_p_max)
	if frac <= 0.5 and _p_hp > 0:
		var a := (0.35 + 0.35 * sin(_pulse_t)) * (1.0 - frac / 0.5)
		var col := Color(Game.PALE_JADE.r, Game.PALE_JADE.g, Game.PALE_JADE.b, clampf(a, 0.0, 0.8))
		var w := 14.0
		draw_rect(Rect2(0, 0, vp.x, w), col)
		draw_rect(Rect2(0, vp.y - w, vp.x, w), col)
		draw_rect(Rect2(0, 0, w, vp.y), col)
		draw_rect(Rect2(vp.x - w, 0, w, vp.y), col)

	# --- result panel ---
	if _result_shown:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.1, 0.14, 0.1, 0.72))
		var f := ThemeDB.fallback_font
		var cx := vp.x * 0.5
		var title := "VICTORY" if _result_win else "DEFEAT"
		draw_string(f, Vector2(cx - 90, vp.y * 0.5 - 70), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Game.PALE_JADE)
		var lines := [
			"time    %s" % _fmt_time(_result_time),
			"hits taken    %d" % _result_hits,
		]
		if Game.has_best:
			lines.append("best time    %s" % _fmt_time(Game.best_time))
			lines.append("best hits    %d" % Game.best_hits)
		lines.append("")
		lines.append("press R to fight again")
		for i in lines.size():
			draw_string(f, Vector2(cx - 110, vp.y * 0.5 - 20 + i * 26), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Game.SAPPHIRE_CORE)
