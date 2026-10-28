extends Control
## Fight HUD (handoff screens 04, 06, 08).
##
## Drawn: hearts and the run timer at the top left of the safe area; the boss
## block at the top centre (name, health bar, spare-bar squares); low-HP
## bands on all four screen edges; the boss-intro band.
## Built from Controls: the result screens, so their buttons take touches.
##
## Boss health is shown as one bar per phase (the boss's phase thresholds
## split it): the current bar drains, and a spare square empties each time a
## phase's bar runs out and the bar refills for the next. Damage drains over
## 0.18 s with a Core trail following after 0.3 s.

signal intro_released            # the intro has started fading; play can begin
signal continue_pressed
signal retry_pressed
signal jail_pressed

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")

const BAR := Vector2(560, 22)

var cell := 3
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


func _on_p_health(cur: int, mx: int) -> void:
	if cur < _p_hp:
		_lost = cur
		_lost_t = 0.0
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
		# the bar ran out and a spare took over: square pops, bar refills
		_spare_pop = 1.0
		_shown = 0.0
		_trail = 0.0
		_fill_tw = create_tween()
		_fill_tw.tween_property(self, "_shown", target, 0.4).set_ease(Tween.EASE_OUT)
		_trail_tw = create_tween()
		_trail_tw.tween_property(self, "_trail", target, 0.4).set_ease(Tween.EASE_OUT)
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
			Sfx.play("intro")
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
	var top := band.position.y + 40.0
	var line: String = "CELL " + Game.NUMERALS[cell]
	var w := UI.text_width(line, 24, 600, 0.5)
	UI.text(self, Vector2(cx, top), line, 24, col, 600, 0.5, 0)
	UI.diamond(self, Vector2(cx - w * 0.5 - 30.0, top + 16.0), 14, col)
	UI.diamond(self, Vector2(cx + w * 0.5 + 22.0, top + 16.0), 14, col)
	UI.text(self, Vector2(cx, top + 46.0), Game.BOSS_NAMES.get(cell, ""), 112, col, 600, 0.25, 0)


# --- result (screen 06) ----------------------------------------------
## `flags` from Game.record_win on a win; empty on a loss.
func show_result(win: bool, time: float, hits: int, flags: Dictionary) -> void:
	timing = false
	_result = ResultScreen.new(self, win, time, hits, flags)
	add_child(_result)


class ResultScreen extends Control:
	var _fade := 0.0
	var _hud: Control

	func _init(hud: Control, win: bool, time: float, hits: int, flags: Dictionary) -> void:
		_hud = hud
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var numeral: String = Game.NUMERALS[hud.cell]
		var name_: String = Game.BOSS_NAMES.get(hud.cell, "")
		var best: Dictionary = Game.bests.get(hud.cell, {})
		var sheet: Control
		var first: BaseButton
		if win:
			var col := W.vbox(28)
			col.add_child(W.Text.new("CELL %s · %s FALLS" % [numeral, name_], 18, 400, 0.3, Color(UI.CORE, 0.75)))
			col.add_child(W.Text.new("VICTORY", 80, 600, 0.3))
			col.add_child(W.Shape.new(Vector2(0, 110), func(c: Control, s: Vector2):
				var m := s * 0.5
				UI.diamond(c, m, 76, UI.CORE, false)
				UI.diamond(c, m, 44, UI.CORE)
				c.draw_rect(Rect2(m.x - 80 - 80, m.y - 1, 80, 2), UI.CORE)
				c.draw_rect(Rect2(m.x + 80, m.y - 1, 80, 2), UI.CORE)))
			col.add_child(W.Text.new("SAPPHIRE %s WON" % numeral, 18, 400, 0.3, Color(UI.CORE, 0.75)))
			col.add_child(_stats(time, hits, best, flags))
			first = Btn.new("CONTINUE", Vector2(400, 100), 28)
			first.pressed.connect(func(): hud.continue_pressed.emit())
			var cc := CenterContainer.new()
			cc.add_child(first)
			col.add_child(cc)
			sheet = W.top_centred(col, 80)
		else:
			var col := W.vbox(28)
			col.add_child(W.Text.new("DEFEAT", 80, 600, 0.3, Color(UI.CORE, 0.75)))
			var line: String = "%s   ·   TIME %s   ·   HITS %d" % [name_, UI.fmt_time(time), hits]
			if not best.is_empty():
				line += "   ·   BEST %s" % UI.fmt_time(best["time"])
			col.add_child(W.Text.new(line, 18, 400, 0.15, Color(UI.CORE, 0.75)))
			var row := W.hbox(24, BoxContainer.ALIGNMENT_CENTER)
			first = Btn.new("RETRY", Vector2(480, 120), 32)
			var back := Btn.new("BACK TO JAIL", Vector2(360, 120), 28)
			first.pressed.connect(func(): hud.retry_pressed.emit())
			back.pressed.connect(func(): hud.jail_pressed.emit())
			row.add_child(first)
			row.add_child(back)
			col.add_child(row)
			sheet = W.top_centred(col, 220)
		add_child(sheet)
		# overlay fades in, the sheet rises 24 units into place; a defeat waits 0.4 s
		modulate.a = 0.0
		var top := sheet.offset_top
		sheet.offset_top = top + 24.0
		ready.connect(func():
			var t := create_tween().set_parallel()
			var delay := 0.0 if win else 0.4
			t.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay).set_ease(Tween.EASE_OUT)
			t.tween_property(sheet, "offset_top", top, 0.25).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			first.grab_focus.call_deferred())

	## Label / THIS RUN / BEST, values right-aligned; a NEW chip on a new best.
	func _stats(time: float, hits: int, best: Dictionary, flags: Dictionary) -> Control:
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 56)
		g.add_theme_constant_override("v_separation", 14)
		var dim := Color(UI.CORE, 0.6)
		for h in ["", "THIS RUN", "BEST"]:
			g.add_child(_cell(h, 14, dim, 400))
		var rows := [["TIME", UI.fmt_time(time), UI.fmt_time(best.get("time", time)), flags.get("new_time", false)],
			["HITS TAKEN", str(hits), str(best.get("hits", hits)), flags.get("new_hits", false)]]
		for r in rows:
			g.add_child(_cell(r[0], 18, dim, 400, false))
			g.add_child(_cell(r[1], 22, UI.CORE, 600, true, r[3]))
			g.add_child(_cell(r[2], 22, UI.CORE, 600))
		var cc := CenterContainer.new()
		cc.add_child(g)
		return cc

	func _cell(t: String, px: int, col: Color, weight: int, right := true, new_chip := false) -> Control:
		var box := W.hbox(10, BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN)
		box.custom_minimum_size.x = 200 if right else 220
		if new_chip:
			box.add_child(W.Shape.new(Vector2(52, 24), func(c: Control, s: Vector2):
				c.draw_rect(Rect2(Vector2.ZERO, s), UI.CORE)
				UI.text(c, Vector2(s.x * 0.5, (s.y - UI.text_height(14)) * 0.5), "NEW", 14, UI.MOSS, 600, 0.1, 0)))
		box.add_child(W.Text.new(t, px, weight, 0.1, col))
		return box

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UI.MOSS, 0.72))


# --- draw ------------------------------------------------------------
func _draw() -> void:
	var s := UI.safe(self)
	var c := UI.CORE

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
		var j := 6.0 * (1.0 - _lost_t / 0.25)          # the row shakes as a heart goes
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

	# boss block: "III · NAME", the bar, and one square per spare bar
	var bx := size.x * 0.5 - BAR.x * 0.5 + sin(_jolt * 30.0) * 7.0 * _jolt
	var by := 20.0
	UI.text(self, Vector2(size.x * 0.5, by), "%s · %s" % [Game.NUMERALS[cell], Game.BOSS_NAMES.get(cell, "")], 20, c, 600, 0.15, 0)
	var bar := Rect2(bx, by + UI.text_height(20) + 8.0, BAR.x, BAR.y)
	_round(bar, UI.MOSS)
	if _trail > _shown:
		_round(Rect2(bar.position, Vector2(BAR.x * _trail, BAR.y)), Color(c, 0.5))
	if _shown > 0.0:
		_round(Rect2(bar.position, Vector2(BAR.x * _shown, BAR.y)), UI.JADE)
	_round(bar, Color(0, 0, 0, 0), c)
	var spares := _spares(_b_hp)
	for i in _bars() - 1:
		var sq := Rect2(Vector2(bar.end.x - 24.0 - i * 34.0, bar.end.y + 8.0), Vector2(24, 24))
		var full := i < spares
		var pop := 1.0 + 0.3 * _spare_pop if (i == spares and _spare_pop > 0.0) else 1.0
		sq = sq.grow(12.0 * (pop - 1.0))
		_round(sq, UI.JADE if full else Color(0, 0, 0, 0), c, 5)

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
