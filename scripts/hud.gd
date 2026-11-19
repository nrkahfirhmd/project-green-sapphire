extends Control
## Fight HUD (handoff screens 04, 06, 08).
##
## Drawn: hearts and the run timer at the top left of the safe area; the boss
## block at the top centre (name, health bar, bars-left count); low-HP
## bands on all four screen edges; the boss-intro band.
## Built from Controls: the result screens, so their buttons take touches.
##
## Boss health is shown as one bar per phase (the boss's phase thresholds
## split it): the current bar drains, and "×N" beside it counts the bars left,
## this one included. When a bar runs out the next one is simply there, full,
## and the count drops: a bar growing back from empty read as the boss
## healing. Damage drains over 0.18 s with a Core trail following after 0.3 s.

signal intro_released            # the intro has started fading; play can begin
signal continue_pressed
signal retry_pressed
signal jail_pressed

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")

const BAR := Vector2(560, 22)

var cell := 3
# the boss's own sting under the title card (media/sfx/intro_<boss>.wav)
const INTRO_STING := {1: "turnkey", 2: "pendulum", 3: "prism", 4: "hourglass", 5: "mirror"}
var _p_hp := 4
var _p_max := 4
var _lost := -1                  # index of the heart that was just lost
var _lost_t := 0.0               # 0..0.35 s of its flash
var _b_hp := 12
var _b_max := 12
var _marks: Array = []           # the boss's phase thresholds, high to low
var _shown := 1.0                # fill of the current bar, 0..1, tweened
var _trail := 1.0                # the trailing chunk behind it
var _spare_pop := 0.0            # 1 -> 0 as an emptied spare square settles
var _pulse := 0.0
var _jolt := 0.0                 # boss bar knocked sideways by a hit, 1 -> 0
var _beat := 0.0                 # last-heart heartbeat clock
var _hurt := 0.0                 # Jade edge flash when the player is hit, 1 -> 0
var _hint := ""                  # a one-line teaching caption, bottom centre
var _hint_t := 0.0
var elapsed := 0.0
var timing := false
var _intro := -1.0               # seconds into the intro, -1 when not showing
var _result: Control
var _fill_tw: Tween
var _trail_tw: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame     # let Main spawn player/boss
	var player := get_tree().get_first_node_in_group("player")
	var boss := get_tree().get_first_node_in_group("boss")
	if player:
		player.health_changed.connect(_on_p_health)
	if boss:
		_marks = boss.phases() if boss.has_method("phases") else [boss.max_hp / 2] if "max_hp" in boss else []
		boss.health_changed.connect(_on_b_health)
		# its first health_changed fired before this connected
		_b_hp = boss.hp
		_b_max = boss.max_hp


## Show a short teaching caption for a few seconds (bosses call this).
func hint(text: String) -> void:
	_hint = text
	_hint_t = 3.5


func _on_p_health(cur: int, mx: int) -> void:
	if cur < _p_hp:
		_lost = cur
		_lost_t = 0.0
		_hurt = 1.0
	_p_hp = cur
	_p_max = mx


## Bar edges, high to low: max, each phase threshold, 0.
func _edges() -> Array:
	var e: Array = [_b_max]
	e.append_array(_marks if not _marks.is_empty() else [_b_max / 2])
	e.append(0)
	return e


func _bars() -> int:
	return _edges().size() - 1


## How full the bar holding `hp` is.
func _bar_fill(hp: int) -> float:
	var e := _edges()
	var i := _bars() - 1 - _spares(hp)
	var hi := float(e[i])
	var lo := float(e[i + 1])
	return clampf((hp - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


## Full bars still waiting behind the one that holds `hp`.
func _spares(hp: int) -> int:
	var e := _edges()
	var n := 0
	for k in range(1, e.size() - 1):
		if hp > int(e[k]):
			n += 1
	return n


func _on_b_health(cur: int, mx: int) -> void:
	if cur < _b_hp:
		_jolt = 1.0
	var before := _spares(_b_hp)
	_b_max = mx
	var emptied := _spares(cur) < before
	_b_hp = cur
	var target := _bar_fill(cur)
	if _fill_tw:
		_fill_tw.kill()
	if _trail_tw:
		_trail_tw.kill()
	if emptied:
		# the bar ran out and the next took over: the count pops, the bar is just full
		_spare_pop = 1.0
		_shown = target
		_trail = target
		return
	_fill_tw = create_tween()
	_fill_tw.tween_property(self, "_shown", target, 0.18).set_ease(Tween.EASE_OUT)
	_trail_tw = create_tween()
	_trail_tw.tween_interval(0.3)
	_trail_tw.tween_property(self, "_trail", target, 0.25).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if timing:
		elapsed += delta
	_lost_t += delta
	_spare_pop = maxf(0.0, _spare_pop - delta / 0.3)
	_jolt = maxf(0.0, _jolt - delta / 0.25)
	_hurt = maxf(0.0, _hurt - delta / 0.35)    # scaled delta: it holds through the hit-stop
	_hint_t = maxf(0.0, _hint_t - delta)
	_pulse += delta
	# down to the last heart: it thumps, and the phone with it, once a second
	if _p_hp == 1 and timing and _result == null:
		_beat += delta
		if _beat >= 1.0:
			_beat = 0.0
			Haptics.play("heartbeat")
			Sfx.play("heartbeat", 0.0, 0.0)
	else:
		_beat = 0.0
	if _intro >= 0.0:
		var was := _intro
		_intro += delta
		if was < 0.15 and _intro >= 0.15:
			Haptics.play("intro")       # the boss's name lands
			Sfx.play("intro_" + INTRO_STING.get(cell, "turnkey"), 0.0, 0.0)
		if was < 1.4 and _intro >= 1.4:
			intro_released.emit()
		if _intro >= 1.6:
			_intro = -1.0
	queue_redraw()


# --- boss intro (screen 08) ------------------------------------------
## 1.6 s: the band opens (0.15), the name slides in (0.25), holds (1.0),
## everything fades (0.2). Play is released as the fade starts.
func play_intro() -> void:
	_intro = 0.0


func _draw_intro() -> void:
	var t := _intro
	var a := 1.0 if t < 1.4 else clampf(1.0 - (t - 1.4) / 0.2, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.4 * a))
	var open := clampf(t / 0.15, 0.0, 1.0)
	open = 1.0 - pow(1.0 - open, 3.0)
	var band := Rect2(0, 450.0 - 120.0 * open, size.x, 240.0 * open)
	band.position.y += (size.y - 900.0) * 0.5
	draw_rect(band, Color(UI.MOSS, 0.92 * a))
	draw_rect(Rect2(0, band.position.y, size.x, 2), Color(UI.CORE, a))
	draw_rect(Rect2(0, band.end.y - 2, size.x, 2), Color(UI.CORE, a))
	if open < 1.0:
		return
	var n := clampf((t - 0.15) / 0.25, 0.0, 1.0)
	var cx := size.x * 0.5 + 40.0 * (1.0 - n)
	var col := Color(UI.CORE, n * a)
	# the name alone: the cells can be taken in any order, so they aren't numbered
	var name_: String = Game.BOSS_NAMES.get(cell, "")
	var y := band.get_center().y - UI.text_height(112) * 0.5
	var w := UI.text_width(name_, 112, 600, 0.25) - roundi(0.25 * 112)
	UI.text(self, Vector2(cx, y), name_, 112, col, 600, 0.25, 0)
	for side in [-1.0, 1.0]:
		UI.diamond(self, Vector2(cx + side * (w * 0.5 + 56.0), band.get_center().y), 18, col)
		draw_rect(Rect2(cx + side * (w * 0.5 + 76.0) - (120.0 * n if side < 0.0 else 0.0), band.get_center().y - 1.0, 120.0 * n, 2.0), col)


# --- result (screen 06) ----------------------------------------------
## `flags` from Game.record_win on a win; empty on a loss.
func show_result(win: bool, time: float, hits: int, flags: Dictionary) -> void:
	timing = false
	_result = ResultScreen.new(self, win, time, hits, flags)
	add_child(_result)


class ResultScreen extends Control:
	## The victory reveal, in seconds: the sapphire lands, VICTORY drops in
	## letter by letter, the time counts up, the hearts kept pop in, then the
	## stamps and CONTINUE. A tap or ui_accept skips to the end.
	const REVEAL := 1.6
	const GEM_R := 110.0

	var _hud: Control
	var _win := false
	var _t := 0.0
	var _time := 0.0
	var _hits := 0
	var _max_hp := 4
	var _first := false          # no earlier win in this cell to compare with
	var _flags := {}
	var _best := {}
	var _name := ""
	var _btn: BaseButton
	var _pops := 0               # hearts whose pop has sounded
	var _left := 0.0             # defeat: the boss's health left, 0..1
	var _final := false          # the Mirror, the last warden: all five stones, the run's totals

	func _init(hud: Control, win: bool, time: float, hits: int, flags: Dictionary) -> void:
		_hud = hud
		_win = win
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var name_: String = Game.BOSS_NAMES.get(hud.cell, "")
		var best: Dictionary = Game.bests.get(hud.cell, {})
		var sheet: Control
		var first: BaseButton
		if win:
			_time = time
			_hits = hits
			_max_hp = hud._p_max
			_flags = flags
			_best = best
			_name = name_
			_final = hud.cell == 5
			# record_win has already stored this run, so a first clear is a best
			# that equals it without being flagged new
			_first = not flags.get("new_time", false) and is_equal_approx(float(best.get("time", time)), time)
			_btn = Btn.new("TO THE ALTAR" if _final else "CONTINUE", Vector2(400, 100), 28)
			_btn.pressed.connect(func(): hud.continue_pressed.emit())
			_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_btn.modulate.a = 0.0
			add_child(_btn)
			if Game.reduced_motion:
				_t = REVEAL - 0.001     # the next frame crosses REVEAL and hands CONTINUE its focus
		else:
			# drawn in _draw: who still stands, DEFEAT, how much of it was left
			_name = name_
			_time = time
			_best = best
			_left = float(hud._b_hp) / maxf(1.0, float(hud._b_max))
			var row := W.hbox(24, BoxContainer.ALIGNMENT_CENTER)
			first = Btn.new("RETRY", Vector2(480, 120), 32)
			var back := Btn.new("BACK TO JAIL", Vector2(360, 120), 28)
			first.pressed.connect(func(): hud.retry_pressed.emit())
			back.pressed.connect(func(): hud.jail_pressed.emit())
			row.add_child(first)
			row.add_child(back)
			sheet = W.top_centred(row, 560)
			add_child(sheet)
		# overlay fades in; a defeat's sheet waits 0.4 s, then rises 24 units into place
		modulate.a = 0.0
		ready.connect(func():
			var t := create_tween().set_parallel()
			var delay := 0.0 if win else 0.4
			t.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay).set_ease(Tween.EASE_OUT)
			if sheet:
				var top := sheet.offset_top
				sheet.offset_top = top + 24.0
				t.tween_property(sheet, "offset_top", top, 0.25).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				first.grab_focus.call_deferred())

	func _process(delta: float) -> void:
		var was := _t
		_t += delta
		if not _win:
			queue_redraw()
			return
		# a soft tick as each kept heart pops in
		while _pops < _max_hp - _hits and _t >= _heart_at(_pops):
			if was < _heart_at(_pops) and _t < REVEAL:
				Sfx.play("tap", -12.0, 0.0, 1.0 + 0.12 * _pops)
			_pops += 1
		_btn.position = Vector2(_col_x(), _col_top() + (520.0 if _final else 440.0))
		_btn.modulate.a = _k(1.25, 1.55)
		if was < REVEAL and _t >= REVEAL:
			_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			_btn.grab_focus()
		queue_redraw()

	## Any tap or accept during the reveal jumps to its end.
	func _gui_input(event: InputEvent) -> void:
		if _win and _t < REVEAL and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			_t = REVEAL - 0.001
			accept_event()

	func _unhandled_input(event: InputEvent) -> void:
		if _win and _t < REVEAL and event.is_action_pressed("ui_accept"):
			_t = REVEAL - 0.001
			get_viewport().set_input_as_handled()

	func _k(a: float, b: float) -> float:
		return clampf((_t - a) / (b - a), 0.0, 1.0)

	## Ease out with a little overshoot, for things that land.
	static func _back(x: float) -> float:
		var c := 1.7
		return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

	func _heart_at(i: int) -> float:
		return 0.8 + i * 0.09

	func _col_x() -> float:
		return size.x * 0.5 - 110.0

	func _col_top() -> float:
		return size.y * 0.5 - 250.0

	func _draw() -> void:
		if not _win:
			_draw_defeat()
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.92))
		var c := UI.CORE
		var g := Vector2(size.x * 0.5 - 390.0, size.y * 0.5 - 30.0)
		_draw_emblem(g)
		if _final:
			var fa := _k(1.1, 1.4)
			UI.text(self, Vector2(g.x, g.y + GEM_R * 1.55 + 46.0), "ALL FIVE SAPPHIRES", 16, Color(c, fa), 400, 0.3, 0)
		else:
			_draw_progress(Vector2(g.x, g.y + GEM_R * 1.55 + 54.0))

		# the column: who fell, VICTORY letter by letter, a rule drawn across
		var x0 := _col_x()
		var y := _col_top()
		var ca := _k(0.2, 0.45)
		var who := "THE LAST WARDEN FALLS" if _final else "%s FALLS" % _name
		UI.text(self, Vector2(x0 - 16.0 * (1.0 - ca), y), who, 20, Color(c, ca), 400, 0.3)
		y += 34.0
		var x := x0
		var word := "VICTORY"
		for i in word.length():
			var ch := word[i]
			var k := _k(0.25 + i * 0.05, 0.55 + i * 0.05)
			var e := 1.0 - pow(1.0 - k, 3.0)
			UI.text(self, Vector2(x, y - 28.0 * (1.0 - e)), ch, 112, Color(c, k), 600, 0.24)
			x += UI.text_width(ch, 112, 600, 0.24)
		y += UI.text_height(112) + 10.0
		var rule := (x - x0) * (1.0 - pow(1.0 - _k(0.6, 1.0), 3.0))
		draw_rect(Rect2(x0, y - 1.0, rule, 2.0), c)
		if rule > 0.0:
			UI.diamond(self, Vector2(x0 + rule, y), 12, c)
		y += 36.0

		# time, counting up to the run's
		UI.text(self, Vector2(x0, y), "TIME", 16, c, 400, 0.3)
		var shown := _time * (1.0 - pow(1.0 - _k(0.6, 1.2), 3.0))
		UI.text(self, Vector2(x0, y + 28.0), UI.fmt_time(shown), 56, c, 600, 0.05)
		var under := y + 28.0 + UI.text_height(56) + 8.0
		if _flags.get("new_time", false):
			_stamp(Vector2(x0, under), "NEW BEST")
		elif _first:
			_stamp(Vector2(x0, under), "FIRST CLEAR")
		else:
			UI.text(self, Vector2(x0, under + 4.0), "BEST %s" % UI.fmt_time(float(_best.get("time", _time))), 16, c, 400, 0.2)

		# hearts kept: full ones pop in one by one, the lost ones stay outlined
		var hx := x0 + 340.0
		UI.text(self, Vector2(hx, y), "HEARTS KEPT", 16, c, 400, 0.3)
		var kept := _max_hp - _hits
		for i in _max_hp:
			var at := Vector2(hx + i * 52.0, y + 46.0)
			var full := i < kept
			var k := _k(_heart_at(i), _heart_at(i) + 0.25) if full else _k(0.7, 0.9)
			if k <= 0.0:
				continue
			if full:
				UI.heart(self, at, c, false, 1.4)
				UI.heart(self, at, Color(c, k), true, 1.4 * _back(k))
			else:
				UI.heart(self, at, Color(c, k), false, 1.4)
		if _hits == 0:
			_stamp(Vector2(hx, under), "FLAWLESS")
		else:
			var bh := int(_best.get("hits", _hits))
			var line := "HITS %d" % _hits + ("   NEW BEST" if _flags.get("new_hits", false) else "   BEST %d" % bh)
			UI.text(self, Vector2(hx, under + 4.0), line, 16, c, 400, 0.2)

		# the last fight closes the run: its totals under a rule
		if _final:
			var ty := under + 58.0
			var ta := _k(1.35, 1.6)
			draw_rect(Rect2(x0, ty - 1.0, 560.0 * ta, 1.0), Color(c, ta))
			UI.text(self, Vector2(x0, ty + 14.0), "THE WHOLE RUN", 16, Color(c, ta), 400, 0.3)
			UI.text(self, Vector2(x0, ty + 42.0), UI.fmt_time(Game.total_time), 24, Color(c, ta), 600, 0.05)
			UI.text(self, Vector2(hx, ty + 42.0), "%d HIT%s TAKEN" % [Game.total_hits, "" if Game.total_hits == 1 else "S"], 24, Color(c, ta), 600, 0.05)

	## Defeat, centred and quick: who still stands, DEFEAT, and a bar that
	## fills to the health the boss had left, so a near miss reads as one.
	## The overlay waits 0.4 s (the fade tween); the bar fills after it.
	func _draw_defeat() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.88))
		var c := UI.CORE
		var cx := size.x * 0.5
		var y := 170.0
		UI.text(self, Vector2(cx, y), "%s STANDS" % _name, 20, c, 400, 0.3, 0)
		y += 34.0
		UI.text(self, Vector2(cx, y), "DEFEAT", 104, c, 600, 0.24, 0)
		y += UI.text_height(104) + 26.0
		var bw := 560.0
		var x0 := cx - bw * 0.5
		var fill := _left * (1.0 - pow(1.0 - _k(0.55, 1.15), 3.0))
		UI.text(self, Vector2(x0, y), "HEALTH IT HAD LEFT", 16, c, 400, 0.3)
		UI.text(self, Vector2(x0 + bw, y), "%d %%" % roundi(fill * 100.0), 16, c, 600, 0.2, 1)
		var bar := Rect2(x0, y + 30.0, bw, 16.0)
		draw_rect(bar, UI.MOSS)
		if fill > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bw * fill, bar.size.y)), UI.JADE)
		draw_rect(bar, c, false, UI.STROKE)
		y = bar.end.y + 34.0
		var line := "TIME %s" % UI.fmt_time(_time)
		if not _best.is_empty():
			line += "      BEST %s" % UI.fmt_time(float(_best["time"]))
		UI.text(self, Vector2(cx, y), line, 18, c, 400, 0.2, 0)

	## The sapphire won, in a diamond frame: slow rays behind, a Jade ring
	## thrown out as it lands with a small overshoot.
	func _draw_emblem(g: Vector2) -> void:
		var c := UI.CORE
		var appear := _k(0.05, 0.4)
		var spin := 0.0 if Game.reduced_motion else _t * 0.12
		for i in 12:
			var a := TAU * i / 12.0 + spin
			var far := GEM_R * 3.0
			draw_colored_polygon(PackedVector2Array([g, g + Vector2.from_angle(a - 0.05) * far, g + Vector2.from_angle(a + 0.05) * far]),
				Color(c, 0.1 * appear))
		var h := GEM_R * 1.55
		UI.diamond(self, g, h / 0.7071, Color(c, appear), false)
		UI.diamond(self, g, h * 0.86 / 0.7071, Color(c, 0.4 * appear), false, 1.0)
		for d in [Vector2(0, -h), Vector2(h, 0), Vector2(0, h), Vector2(-h, 0)]:
			UI.diamond(self, g + d, 12, Color(c, appear))
		if not Game.reduced_motion:
			var r0 := 0.66 if _final else 0.18     # the finale's ring waits for the last stone
			var k := _k(r0, r0 + 0.57)
			if k > 0.0 and k < 1.0:
				var r := lerpf(GEM_R * 0.8, GEM_R * 2.6, 1.0 - pow(1.0 - k, 2.0))
				draw_arc(g, r, 0.0, TAU, 64, Color(UI.JADE, 0.8 * (1.0 - k)), 1.0 + 3.0 * (1.0 - k))
		if _final:
			_draw_five(g)
			return
		var s := _back(_k(0.1, 0.5))
		if s > 0.0:
			_gem(g, GEM_R * s, _t)

	## The finale's emblem: the five sapphires land round a ring one by one,
	## the Mirror's last, then threads draw a five-point star between them and
	## a Jade spark wakes in the middle, where they will become one.
	func _draw_five(g: Vector2) -> void:
		var at: Array[Vector2] = []
		for i in 5:
			at.append(g + Vector2.from_angle(-PI * 0.5 + TAU * i / 5.0) * GEM_R * 0.78)   # inside the frame's sides
		var th := _k(0.75, 1.15)
		if th > 0.0:
			for i in 5:
				var a: Vector2 = at[i]
				var b: Vector2 = at[(i + 2) % 5]
				draw_line(a, a.lerp(b, th), Color(UI.JADE, 0.45), 2.0)
		for i in 5:
			var k := _k(0.1 + i * 0.12, 0.4 + i * 0.12)
			if k > 0.0:
				_gem(at[i], 30.0 * _back(k), _t + i * 1.3)
		var spark := _k(1.1, 1.4)
		if spark > 0.0:
			var beat := 0.0 if Game.reduced_motion else 0.12 * sin(_t * 4.0)
			UI.diamond(self, g, 30, Color(UI.JADE, spark), false)
			UI.diamond(self, g, 16 * _back(spark) * (1.0 + beat), UI.JADE)

	## An eight-sided cut stone, facets lit in turn as it spins.
	func _gem(at: Vector2, r: float, spin: float) -> void:
		if r < 3.0:
			return     # too small to triangulate its facets
		var outer := PackedVector2Array()
		var table := PackedVector2Array()
		for k in 8:
			var a := TAU * k / 8.0 + PI / 8.0
			outer.append(at + Vector2(cos(a), sin(a) * 1.12) * r)
			table.append(at + Vector2(cos(a), sin(a) * 1.12) * r * 0.52)
		draw_colored_polygon(outer, UI.MOSS)
		for k in 8:
			var j := (k + 1) % 8
			var light := 0.5 + 0.5 * sin(spin * 2.0 + k * 0.785)
			draw_colored_polygon(PackedVector2Array([outer[k], outer[j], table[j], table[k]]),
				Color(UI.JADE if light > 0.75 else UI.CORE, 0.6 + 0.4 * light))
		draw_colored_polygon(table, Color(UI.CORE, 0.9))
		for k in 8:
			draw_line(at, table[k], Color(UI.MOSS, 0.6), maxf(1.0, r * 0.025))
		draw_polyline(outer + PackedVector2Array([outer[0]]), UI.JADE, maxf(1.5, r * 0.03))
		var gl := at + Vector2(sin(spin * 1.7) * r * 0.3, -r * 0.2)
		draw_line(gl - Vector2(r * 0.18, 0), gl + Vector2(r * 0.18, 0), UI.JADE, maxf(1.0, r * 0.04))
		draw_line(gl - Vector2(0, r * 0.18), gl + Vector2(0, r * 0.18), UI.JADE, maxf(1.0, r * 0.04))

	## Five slots, one per warden: held sapphires filled, this one in Jade,
	## popping in once the stone has landed.
	func _draw_progress(at: Vector2) -> void:
		var c := UI.CORE
		var a := _k(0.9, 1.1)
		for i in 5:
			var id := i + 1
			var p := at + Vector2((i - 2) * 46.0, 0)
			if id == _hud.cell:
				UI.diamond(self, p, 22, Color(c, a), false)
				var k := _k(1.0, 1.3)
				if k > 0.0:
					UI.diamond(self, p, 22 * _back(k), UI.JADE)
			elif Game.crystals.has(id):
				UI.diamond(self, p, 22, Color(c, a))
			else:
				UI.diamond(self, p, 22, Color(c, a), false)
		var n := 0
		for id in range(1, 6):
			if Game.crystals.has(id) or id == _hud.cell:
				n += 1
		UI.text(self, at + Vector2(0, 30), "SAPPHIRES %d OF 5" % n, 16, Color(c, a), 400, 0.3, 0)

	## A solid Core chip with Moss text, stamped in from 1.6x after the count.
	func _stamp(at: Vector2, t: String) -> void:
		var k := _k(1.2, 1.45)
		if k <= 0.0:
			return
		var w := UI.text_width(t, 14, 600, 0.15) + 20.0
		var r := Rect2(at, Vector2(w, 26))
		var sc := lerpf(1.6, 1.0, 1.0 - pow(1.0 - k, 3.0))
		draw_set_transform(r.get_center() * (1.0 - sc), 0.0, Vector2(sc, sc))
		draw_rect(r, Color(UI.CORE, k))
		UI.text(self, Vector2(r.get_center().x, at.y + (26.0 - UI.text_height(14)) * 0.5), t, 14, Color(UI.MOSS, k), 600, 0.15, 0)
		draw_set_transform(Vector2.ZERO)


# --- draw ------------------------------------------------------------
func _draw() -> void:
	if _result != null:
		return     # the result screen covers the fight; its bars and hearts would show through
	var s := UI.safe(self)
	var c := UI.CORE

	# a teaching caption, fading in and out
	if _hint_t > 0.0 and _hint != "":
		var ha := minf(1.0, minf(_hint_t / 0.4, (3.5 - _hint_t) / 0.25))
		var hy := size.y - 210.0
		var hw := UI.text_width(_hint, 26, 600, 0.12) + 60.0
		draw_rect(Rect2(size.x * 0.5 - hw * 0.5, hy - 14.0, hw, UI.text_height(26) + 28.0), Color(UI.MOSS, 0.85 * ha))
		UI.text(self, Vector2(size.x * 0.5, hy), _hint, 26, Color(UI.JADE, ha), 600, 0.12, 0)

	# a hit: thick Jade edges that hold through the freeze, then fade
	if _hurt > 0.0:
		var hw := 40.0 * _hurt
		var hc := Color(UI.JADE, 0.55 * _hurt)
		draw_rect(Rect2(0, 0, size.x, hw), hc)
		draw_rect(Rect2(0, size.y - hw, size.x, hw), hc)
		draw_rect(Rect2(0, 0, hw, size.y), hc)
		draw_rect(Rect2(size.x - hw, 0, hw, size.y), hc)

	# low-HP bands, edge to edge: 2 hearts pulse slowly, 1 heart fast
	if _p_hp > 0 and _p_hp <= 2 and _result == null:
		var lo := 0.15 if _p_hp == 2 else 0.25
		var hi := 0.45 if _p_hp == 2 else 0.70
		var period := 1.0 if _p_hp == 2 else 0.5
		var a := lerpf(lo, hi, 0.5 + 0.5 * sin(TAU * _pulse / period))
		var col := Color(UI.JADE, a)
		var w := 14.0
		draw_rect(Rect2(0, 0, size.x, w), col)
		draw_rect(Rect2(0, size.y - w, size.x, w), col)
		draw_rect(Rect2(0, 0, w, size.y), col)
		draw_rect(Rect2(size.x - w, 0, w, size.y), col)

	# hearts and timer, right of the pause button
	var hp0 := s.position + Vector2(152, 32)
	if _lost_t < 0.25:
		var j := 0.0 if Game.reduced_motion else 6.0 * (1.0 - _lost_t / 0.25)          # the row shakes as a heart goes
		hp0 += Vector2(randf_range(-j, j), randf_range(-j, j))
	for i in _p_max:
		var at := hp0 + Vector2(i * 38.0, 0)
		if i == _lost and _lost_t < 0.35:
			# the lost heart flashes Jade, settles from 1.2x, then fades out
			var k := clampf(_lost_t / 0.15, 0.0, 1.0)
			var a := 1.0 if _lost_t < 0.15 else 1.0 - (_lost_t - 0.15) / 0.2
			UI.heart(self, at, Color(c, 0.6), false)
			UI.heart(self, at, Color(UI.JADE, a), true, lerpf(1.2, 1.0, k))
		elif i < _p_hp:
			# lub-dub on the last heart, in time with the haptic heartbeat
			var thump := 1.0
			if _p_hp == 1:
				thump += 0.18 * maxf(0.0, 1.0 - _beat / 0.12) + 0.1 * maxf(0.0, 1.0 - absf(_beat - 0.18) / 0.1)
			UI.heart(self, at, c, true, thump)
		else:
			UI.heart(self, at, Color(c, 0.6), false)
	UI.text(self, s.position + Vector2(152, 70), UI.fmt_time(elapsed), 24, c, 400)

	# boss block: its name, the bar, and how many bars are left
	var bx := size.x * 0.5 - BAR.x * 0.5 + sin(_jolt * 30.0) * 7.0 * _jolt
	var by := 20.0
	UI.text(self, Vector2(size.x * 0.5, by), Game.BOSS_NAMES.get(cell, ""), 20, c, 600, 0.15, 0)
	var bar := Rect2(bx, by + UI.text_height(20) + 8.0, BAR.x, BAR.y)
	_round(bar, UI.MOSS)
	if _trail > _shown:
		_round(Rect2(bar.position, Vector2(BAR.x * _trail, BAR.y)), Color(c, 0.5))
	if _shown > 0.0:
		_round(Rect2(bar.position, Vector2(BAR.x * _shown, BAR.y)), UI.JADE)
	_round(bar, Color(0, 0, 0, 0), c)
	if _bars() > 1:
		var lift := 0.0 if Game.reduced_motion else 8.0 * _spare_pop
		var cy := bar.get_center().y - UI.text_height(28) * 0.5 - lift
		UI.text(self, Vector2(bar.end.x + 16.0, cy), "×%d" % (_spares(_b_hp) + 1), 28, UI.JADE if _spare_pop > 0.0 else c, 600, 0.05)

	if _intro >= 0.0:
		_draw_intro()


func _round(r: Rect2, fill: Color, border := Color(0, 0, 0, 0), radius := 6) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.draw_center = fill.a > 0.0
	draw_style_box(sb, r)
