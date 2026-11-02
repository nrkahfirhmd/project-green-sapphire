extends Control
## The ending: the five sapphires become one, the gate opens, the prisoner
## walks out into the dawn, and the credits roll. Timed to the ending music
## (media/music/ending.wav, 76 bpm, a bar every 3.16 s), whose clock it runs
## on, so picture and score stay together.
##
##   0-25 s    piano      night in the hall: five sapphires on the altar,
##                         pulsing with the piano; moonlight; the prisoner
##   25-50 s   the answer  they lift and circle, threads of light between
##                         them; the credits begin
##   50-63 s   into the    the circle tightens into a spiral; gate V's bars
##             light       rise
##   63 s      the climax  they meet: a flash, a shockwave through the glyphs,
##                         one great green sapphire, rays turning
##   88-114 s  climax      the five keepers' ghosts circle it, then fly in on
##                         the beat, one by one
##   114-139 s coda        it rises and becomes a star; dawn pours through
##                         the gate and the prisoner walks out into it
##   133 s     the end     the end screen (the jail's original design): the
##                         sapphire's diamonds, THE END, the run's totals,
##                         RETURN HOME
##
## Drawn in the palette, under the same ASCII pass as the game; the credits,
## captions and buttons sit above it, crisp. SKIP jumps to the end card.

const UI := preload("res://scripts/ui/ui.gd")
const W := preload("res://scripts/ui/ui_widgets.gd")
const Btn := preload("res://scripts/ui/ui_button.gd")
const P := preload("res://scripts/paint.gd")
const HOME := "res://scenes/home.tscn"

const BEAT := 60.0 / 76.0
const RISE := 25.26          # sections, in seconds
const SPIRAL := 50.53
const WHOLE := 63.16
const GHOSTS := 88.42
const INTO := 104.2          # the ghosts start flying into the gem
const CODA := 113.68
const CARD := 133.0
const SONG_END := 142.6

const CREDITS := [
	["GREEN SAPPHIRE", 40, 600, 1.0],
	["", 30, 400, 0.0],
	["A GAME BY", 14, 400, 0.6], ["KAHFI R", 24, 600, 1.0], ["", 40, 400, 0.0],
	["DIRECTION & DESIGN", 14, 400, 0.6], ["FI", 22, 600, 1.0], ["", 30, 400, 0.0],
	["PROGRAMMING", 14, 400, 0.6], ["FI", 22, 600, 1.0], ["", 30, 400, 0.0],
	["ART & ASCII", 14, 400, 0.6], ["CLAUDE", 22, 600, 1.0], ["", 30, 400, 0.0],
	["MUSIC", 14, 400, 0.6], ["KV", 22, 600, 1.0], ["", 30, 400, 0.0],
	["SOUND DESIGN", 14, 400, 0.6], ["KV", 22, 600, 1.0], ["", 18, 400, 0.0],
	["FOLEY RECORDINGS (CC0, FREESOUND)", 12, 400, 0.6],
	["nicoproson  ·  Wagna  ·  Elements-Library", 14, 400, 0.85],
	["crashoverride6  ·  launchsite  ·  Breviceps", 14, 400, 0.85],
	["MindlessTrails  ·  nikviolinist97  ·  qubodup", 14, 400, 0.85],
	["monosfera  ·  ldezem  ·  PostProdDog  ·  Fission9", 14, 400, 0.85],
	["Sanderboah  ·  Aurelon  ·  LukaCafuka", 14, 400, 0.85],
	["221Beimesche  ·  jmdh  ·  RedwoodRunner", 14, 400, 0.85],
	["Flamiffer  ·  Hupguy  ·  KasDonatov", 14, 400, 0.85], ["", 30, 400, 0.0],
	# TODO: the playtesters' names, once confirmed
	["PLAYTESTERS", 14, 400, 0.6], ["[ NAME ]", 20, 600, 1.0], ["[ NAME ]", 20, 600, 1.0],
	["[ NAME ]", 20, 600, 1.0], ["", 30, 400, 0.0],
	["SPECIAL THANKS", 14, 400, 0.6], ["ANTONIO PALOMBA", 20, 600, 1.0], ["CHALLENGE MENTOR", 12, 400, 0.6],
	["", 40, 400, 0.0],
	["TYPE", 14, 400, 0.6], ["IBM Plex Mono (SIL Open Font License)", 16, 400, 0.85], ["", 30, 400, 0.0],
	["MADE WITH", 14, 400, 0.6], ["GODOT ENGINE", 22, 600, 1.0], ["", 40, 400, 0.0],
	["A PRODUCT OF", 14, 400, 0.6], ["APPLE DEVELOPER ACADEMY @ BINUS", 22, 600, 1.0], ["BALI", 16, 400, 0.85],
	["", 70, 400, 0.0],
	["AND YOU,", 20, 400, 0.9], ["FOR SETTING IT FREE", 26, 600, 1.0],
]
const CREDITS_FROM := 27.0
const CREDITS_TO := 127.0

var _t := 0.0
var _own_clock := 0.0            # used only if the music isn't running
var _art: Control
var _ui: Control
var _card: Control
var _skip: BaseButton
var _merged := false
var _impacts := 0                # ghosts that have flown into the gem
var _credits_h := 0.0
var _motes: Array = []           # {p: Vector2 (0..1), v, ph, s}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sfx.ambience("")
	Music.play("ending", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 70:
		_motes.append({"p": Vector2(rng.randf(), rng.randf()), "v": rng.randf_range(0.004, 0.016),
			"ph": rng.randf() * TAU, "s": rng.randf_range(1.5, 3.0)})
	for line in CREDITS:
		_credits_h += float(line[1]) + 16.0

	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)
	var ascii := ColorRect.new()
	ascii.name = "Ascii"
	ascii.add_to_group("ascii")
	ascii.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ascii.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ascii.material = ShaderMaterial.new()
	ascii.material.shader = preload("res://shaders/ascii.gdshader")
	add_child(ascii)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)

	_skip = Btn.new("SKIP", Vector2(170, 64), 20)
	_skip.pressed.connect(func(): _jump(CARD))
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.position = Vector2(-210, -100)
	add_child(_skip)


func _process(delta: float) -> void:
	var m := Music.position() if Music.current == "ending" else -1.0
	_own_clock += delta
	_t = m if m >= 0.0 else _own_clock
	if not _merged and _t >= WHOLE:
		_merged = true
		_merge()
	while _impacts < 5 and _t >= _ghost_hit(_impacts):
		_impact(_impacts)
		_impacts += 1
	if _t >= CARD and _card == null:
		_show_card()
	for mo in _motes:
		mo.p = Vector2(fposmod(mo.p.x + sin(_t * 0.3 + mo.ph) * 0.0004, 1.0), fposmod(mo.p.y - mo.v * delta, 1.0))
	_art.queue_redraw()
	_ui.queue_redraw()


func _jump(to: float) -> void:
	Music.seek(to)
	_own_clock = to
	_merged = true
	_impacts = 5
	_skip.hide()


# --- moments -----------------------------------------------------------
func _merge() -> void:
	var o := _orbit_centre()
	Post.shock(o, 1.1)
	Post.scramble(o, 0.18, 1.0)
	Haptics.play("phase")


func _ghost_hit(i: int) -> float:
	return INTO + i * BEAT * 2.0


func _impact(i: int) -> void:
	Post.shock(_orbit_centre(), 0.35 + i * 0.08)
	Haptics.play("tap")


func _show_card() -> void:
	# the end screen, in the jail's original design: only the heading's text
	# is new
	_skip.hide()
	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.draw.connect(func(): _card.draw_rect(Rect2(Vector2.ZERO, _card.size), Color(UI.MOSS, 0.82)))
	var col := W.vbox(32)
	col.add_child(W.Shape.new(Vector2(0, 220), func(c: Control, s: Vector2):
		var m := s * 0.5
		UI.diamond(c, m, 120, UI.CORE, false)
		for d in [Vector2(0, -85), Vector2(85, 0), Vector2(0, 85), Vector2(-85, 0)]:
			UI.diamond(c, m + d, 44, UI.CORE)
		UI.diamond(c, m, 52, UI.CORE)))
	col.add_child(W.Text.new("THE END", 56, 600, 0.2))
	col.add_child(W.Text.new("TOTAL TIME %s   ·   HITS TAKEN %d" % [UI.fmt_time(Game.total_time), Game.total_hits],
		16, 400, 0.2, Color(UI.CORE, 0.75)))
	var home := Btn.new("RETURN HOME", Vector2(440, 100), 28)
	home.pressed.connect(func():
		Game.new_game()
		Game.go(HOME))
	var cc := CenterContainer.new()
	cc.add_child(home)
	col.add_child(cc)
	_card.add_child(W.top_centred(col, 120))
	add_child(_card)
	_card.modulate.a = 0.0
	_card.create_tween().tween_property(_card, "modulate:a", 1.0, 2.0)
	home.grab_focus.call_deferred()


# --- the timeline --------------------------------------------------------
func _k(a: float, b: float) -> float:
	"""0 before a, 1 after b, eased between."""
	var x := clampf((_t - a) / maxf(b - a, 0.001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _pulse() -> float:
	return exp(-6.0 * fmod(maxf(_t, 0.0), BEAT))


func _cx() -> float:
	return size.x * 0.40         # the art sits left of centre; the credits roll on the right


func _orbit_centre() -> Vector2:
	return Vector2(_cx(), size.y * 0.38)


func _altar() -> Vector2:
	return Vector2(_cx(), size.y * 0.77)


## Where sapphire i is (0 the centre stone, 1-4 round it), and its size.
func _stone(i: int) -> Array:
	var sock: Vector2
	if i == 0:
		sock = _altar() + Vector2(0, -34)
	else:
		sock = _altar() + Vector2(96, 0).rotated(-PI * 0.75 + (i - 1) * PI * 0.5) * Vector2(1, 0.4) + Vector2(0, -24)
	var o := _orbit_centre()
	# rising: off the altar into a slow circle
	var ang := TAU * i / 5.0 + maxf(0.0, _t - RISE) * 0.35
	var r := 240.0
	# the spiral: tighter and faster, meeting at WHOLE
	var sp := _k(SPIRAL, WHOLE)
	if _t > SPIRAL:
		ang += pow(sp, 2.2) * TAU * 3.0
		r *= 1.0 - pow(sp, 1.6)
	var ring := o + Vector2(cos(ang), sin(ang) * 0.42) * r
	var lift := _k(RISE, RISE + 8.0)
	var pos := sock.lerp(ring, lift) + Vector2(0, -sin(_t * 1.3 + i) * 6.0 * lift)
	return [pos, 30.0 if i == 0 else 22.0]


# --- art ---------------------------------------------------------------
func _draw_art() -> void:
	var c := Game.SAPPHIRE_CORE
	var w := size.x
	var h := size.y
	var fy := h * 0.66                     # where the back wall meets the floor
	var gate_open := _k(SPIRAL + 2.0, WHOLE)
	var dawn := _k(WHOLE - 2.0, WHOLE + 4.0) * 0.6 + _k(CODA, CODA + 14.0) * 0.4
	var night := 1.0 - _k(WHOLE, WHOLE + 6.0) * 0.6

	_art.draw_rect(Rect2(Vector2.ZERO, size), Game.DEEP_MOSS)
	# the back wall: courses of stone, shadowed towards the top
	var y := 20.0
	var row := 0
	while y < fy:
		var off := 60.0 if row % 2 else 0.0
		var x := -off
		while x < w:
			_art.draw_rect(Rect2(x + 3, y + 3, 114, 34), Color(c, 0.13 + 0.05 * sin(x * 0.37 + y)))
			x += 120.0
		y += 40.0
		row += 1
	P.vband(_art, Rect2(0, 0, w, fy * 0.6), 0.7, 0.0, Game.DEEP_MOSS)

	# gate V in the middle of the wall, and what lies beyond it: dawn
	var gate := Rect2(_cx() - 200.0, h * 0.08, 400.0, fy - h * 0.08)
	_art.draw_rect(gate.grow(18), Color(c, 0.4))
	_art.draw_rect(gate, Game.DEEP_MOSS)
	P.vband(_art, gate, 0.05 + 0.55 * dawn, 0.02 + 0.85 * dawn)
	# beyond the bars, before the dawn: the night sky, its stars fading
	if dawn < 1.0:
		for k in 24:
			var sp := gate.position + Vector2(fmod(k * 137.0, gate.size.x), fmod(k * 89.0, gate.size.y * 0.8))
			var tw := 0.5 + 0.5 * sin(_t * 1.7 + k)
			_art.draw_circle(sp, 1.6 + tw, Color(c, (0.25 + 0.4 * tw) * (1.0 - dawn)))
	if dawn > 0.0:
		P.glow(_art, Vector2(gate.get_center().x, gate.end.y), 260.0, 0.5 * dawn, 0.6)
		# the light spills out of the gate across the floor
		P.shaft(_art, Vector2(gate.position.x, gate.end.y), gate.end,
			Vector2(gate.position.x - 260.0, h), Vector2(gate.end.x + 260.0, h), 0.35 * dawn)
	# the bars, rising
	var top := gate.position.y - gate_open * (gate.size.y + 20.0)
	var bx := gate.position.x + 16.0
	while bx < gate.end.x:
		_art.draw_line(Vector2(bx, maxf(top, gate.position.y)), Vector2(bx, top + gate.size.y), Color(c, 0.65), 8.0)
		bx += 28.0
	_art.draw_line(Vector2(gate.position.x, top + gate.size.y), Vector2(gate.end.x, top + gate.size.y), Color(c, 0.65), 7.0)
	_art.draw_rect(Rect2(gate.position.x - 16, gate.position.y - 30, gate.size.x + 32, 30), Color(c, 0.5))

	# the floor, lines running to the gate
	_art.draw_rect(Rect2(0, fy, w, h - fy), Color(c, 0.08))
	_art.draw_line(Vector2(0, fy), Vector2(w, fy), Color(c, 0.4), 3.0)
	for k in 13:
		var fx := (k - 6) * 220.0
		_art.draw_line(Vector2(_cx() + fx * 0.25, fy), Vector2(_cx() + fx * 1.6, h), Color(c, 0.1), 2.0)

	# moonlight from a high window, fading as the dawn comes
	if night > 0.0:
		P.shaft(_art, Vector2(w * 0.12, 0), Vector2(w * 0.2, 0), Vector2(_cx() - 140.0, h * 0.86), Vector2(_cx() + 40.0, h * 0.86), 0.22 * night)

	# the altar
	var al := _altar()
	_art.draw_colored_polygon(Transform2D(0.0, al + Vector2(0, 34)) * Game.ellipse(210, 56, 32), Color(c, 0.3))
	_art.draw_colored_polygon(Transform2D(0.0, al) * Game.ellipse(184, 50, 32), Color(c, 0.22))
	_art.draw_polyline(Transform2D(0.0, al) * Game.ellipse(184, 50, 32), Color(c, 0.55), 3.0)

	# rays from the gem, once it's whole, turning slowly
	var o := _orbit_centre()
	var whole := _k(WHOLE, WHOLE + 1.5)
	var rise := _k(CODA, CODA + 11.0)
	var gem_at := o.lerp(Vector2(_cx(), h * 0.07), rise)
	if whole > 0.0:
		var ray_a := whole * (1.0 - rise * 0.9)
		for k in 14:
			var ang := TAU * k / 14.0 + _t * 0.08
			var d := Vector2(cos(ang), sin(ang))
			var len := 900.0 if k % 2 == 0 else 600.0
			P.gradient(_art, PackedVector2Array([gem_at + d.orthogonal() * 14.0, gem_at - d.orthogonal() * 14.0, gem_at + d * len]),
				gem_at, gem_at + d * len, 0.22 * ray_a, 0.0)
		P.glow(_art, gem_at, 340.0, 0.35 * ray_a * (0.85 + 0.15 * _pulse()))

	# before the merge: the five stones, the threads between them, their light
	if _t < WHOLE:
		var stones: Array = []
		for i in 5:
			stones.append(_stone(i))
		var threads := _k(RISE + 6.0, RISE + 16.0)
		if threads > 0.0:
			for i in 5:
				var a: Vector2 = stones[i][0]
				var b: Vector2 = stones[(i + 2) % 5][0]          # a five-point star
				_art.draw_line(a, a.lerp(b, threads), Color(Game.PALE_JADE, 0.25 + 0.3 * _k(SPIRAL, WHOLE)), 2.0)
		for i in 5:
			var s: Array = stones[i]
			var glow := 0.18 + 0.12 * _pulse() + 0.3 * _k(SPIRAL, WHOLE)
			P.glow(_art, s[0], float(s[1]) * 4.0, glow)
			_gem(s[0], float(s[1]) * (1.0 + 0.08 * _pulse()), _t * 0.6 + i)
		# the last instant: a flash where they meet
		var flash := _k(WHOLE - 0.4, WHOLE)
		if flash > 0.0:
			P.glow(_art, o, 600.0 * flash, 0.8 * flash, 1.0, Game.PALE_JADE)
	else:
		# the green sapphire: whole, breathing on the beat, turning; then
		# rising and shrinking to a star
		var r := lerpf(150.0, 10.0, rise) * (1.0 + 0.05 * _pulse())
		_gem(gem_at, r * (0.6 + 0.4 * whole), _t * 0.25)
		var flash := 1.0 - _k(WHOLE, WHOLE + 1.2)
		if flash > 0.0:
			_art.draw_rect(Rect2(Vector2.ZERO, size), Color(Game.PALE_JADE, 0.6 * flash))
		if rise > 0.95:
			# a star now: four points that twinkle
			var tw := 14.0 + 6.0 * sin(_t * 3.0)
			for d in [Vector2.RIGHT, Vector2.DOWN]:
				_art.draw_line(gem_at - d * tw, gem_at + d * tw, Game.PALE_JADE, 3.0)

	# the keepers' ghosts: they circle, then fly into the gem on the beat
	if _t > GHOSTS and _t < INTO + 5 * BEAT * 2.0 + 1.0:
		for i in 5:
			var appear := _k(GHOSTS + i * 2.0, GHOSTS + i * 2.0 + 2.0)
			if appear <= 0.0:
				continue
			var hit := _ghost_hit(i)
			var fly := clampf((_t - (hit - 1.2)) / 1.2, 0.0, 1.0)
			if _t > hit:
				continue
			var ang := TAU * i / 5.0 + _t * 0.25
			var orbit := gem_at + Vector2(cos(ang), sin(ang) * 0.5) * 340.0
			var at := orbit.lerp(gem_at, fly * fly)
			_keeper(i, at, Color(Game.PALE_JADE, 0.6 * appear), 1.5 - 1.0 * fly)

	# the prisoner: standing before the altar, back to us; in the coda they
	# walk to the gate and into the dawn
	var walk := _k(CODA + 3.0, CARD - 2.0)
	var start := Vector2(_cx() - 250.0, h * 0.99)
	var end := Vector2(gate.get_center().x, gate.end.y - 4.0)
	var at := start.lerp(end, walk)
	var scale := lerpf(1.4, 0.36, walk)
	var gone := _k(CARD - 4.0, CARD - 1.0)
	if gone < 1.0:
		_prisoner(at, scale, walk > 0.0 and walk < 1.0, 1.0 - gone)

	# dust drifting up, more of it after the merge
	for mo in _motes:
		var a := (0.25 + 0.35 * whole) * (0.5 + 0.5 * sin(_t * 1.1 + float(mo.ph)))
		_art.draw_circle(Vector2(mo.p.x * w, mo.p.y * h), float(mo.s), Color(c, a))

	P.vignette(_art, size, 200.0, 0.75)
	# fade in from black, and out at the very end of the song
	var veil := 1.0 - _k(0.0, 3.5) + _k(SONG_END - 3.0, SONG_END)
	if veil > 0.0:
		_art.draw_rect(Rect2(Vector2.ZERO, size), Color(Game.DEEP_MOSS, clampf(veil, 0.0, 0.85)))


## A cut gem seen from the front: an octagonal girdle, a table, and crown
## facets whose light turns with `spin`, so it seems to rotate.
func _gem(at: Vector2, r: float, spin: float) -> void:
	var c := Game.SAPPHIRE_CORE
	var outer := PackedVector2Array()
	var table := PackedVector2Array()
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		outer.append(at + Vector2(cos(a), sin(a) * 1.12) * r)
		table.append(at + Vector2(cos(a), sin(a) * 1.12) * r * 0.52)
	_art.draw_colored_polygon(outer, Game.DEEP_MOSS)
	for k in 8:
		var j := (k + 1) % 8
		var light := 0.5 + 0.5 * sin(spin * 2.0 + k * 0.785)
		var col := Game.PALE_JADE if light > 0.75 else c
		_art.draw_colored_polygon(PackedVector2Array([outer[k], outer[j], table[j], table[k]]),
			Color(col, 0.45 + 0.5 * light))
	_art.draw_colored_polygon(table, Color(c, 0.85))
	# a star cut into the table
	for k in 8:
		_art.draw_line(at, table[k], Color(Game.DEEP_MOSS, 0.6), maxf(1.0, r * 0.025))
	_art.draw_polyline(outer + PackedVector2Array([outer[0]]), Game.PALE_JADE, maxf(1.5, r * 0.03))
	# a glint crossing the table
	var g := at + Vector2(sin(spin * 1.7) * r * 0.3, -r * 0.2)
	_art.draw_line(g - Vector2(r * 0.18, 0), g + Vector2(r * 0.18, 0), Game.PALE_JADE, maxf(1.0, r * 0.04))
	_art.draw_line(g - Vector2(0, r * 0.18), g + Vector2(0, r * 0.18), Game.PALE_JADE, maxf(1.0, r * 0.04))


## The keepers, in outline: key, blade, prism, hourglass, mirror.
func _keeper(i: int, at: Vector2, col: Color, s: float) -> void:
	var tf := Transform2D(sin(_t + i) * 0.3, Vector2(s, s), 0.0, at)
	match i:
		0:
			var bow := PackedVector2Array()
			for k in 17:
				bow.append(Vector2(-34, 0) + Vector2(12, 0).rotated(TAU * k / 16.0))
			_art.draw_polyline(tf * bow, col, 3.0)
			_art.draw_polyline(tf * PackedVector2Array([Vector2(-22, 0), Vector2(36, 0), Vector2(36, 10), Vector2(28, 10), Vector2(28, 5), Vector2(22, 5)]), col, 3.0)
		1:
			var arc := PackedVector2Array()
			for k in 13:
				arc.append(Vector2(0, -26) + Vector2(0, 52).rotated(lerpf(-0.6, 0.6, k / 12.0)))
			_art.draw_polyline(tf * arc, col, 4.0)
			_art.draw_line(tf * Vector2(0, -70), tf * Vector2(0, 26), col, 2.0)
		2:
			_art.draw_polyline(tf * PackedVector2Array([Vector2(0, -36), Vector2(32, 22), Vector2(-32, 22), Vector2(0, -36)]), col, 3.0)
			for k in 3:
				_art.draw_line(tf * Vector2(16, -2), tf * Vector2(60, -18 + k * 18), col, 2.0)
		3:
			_art.draw_polyline(tf * PackedVector2Array([Vector2(-20, -34), Vector2(20, -34), Vector2(0, 0), Vector2(20, 34), Vector2(-20, 34), Vector2(0, 0), Vector2(-20, -34)]), col, 3.0)
			_art.draw_line(tf * Vector2(-26, -38), tf * Vector2(26, -38), col, 4.0)
			_art.draw_line(tf * Vector2(-26, 38), tf * Vector2(26, 38), col, 4.0)
		4:
			_art.draw_polyline(tf * Game.ellipse(24, 34, 20) + PackedVector2Array([tf * Vector2(24, 0)]), col, 3.0)
			_art.draw_polyline(tf * PackedVector2Array([Vector2(-10, -16), Vector2(8, 10)]), col, 2.0)


## The prisoner from behind: hood, cloak, the rapier at their hip. Walking,
## they bob; `a` fades them into the light.
func _prisoner(at: Vector2, s: float, walking: bool, a: float) -> void:
	var c := Game.SAPPHIRE_CORE
	var bob := absf(sin(_t * 4.2)) * 6.0 * s if walking else sin(_t * 1.2) * 1.5
	var tf := Transform2D(0.0, Vector2(s, s), 0.0, at + Vector2(0, -bob))
	_art.draw_colored_polygon(Transform2D(0.0, at) * Game.ellipse(44 * s, 10 * s), Color(Game.DEEP_MOSS, 0.6 * a))
	var cloak := tf * PackedVector2Array([Vector2(-34, 0), Vector2(34, 0), Vector2(26, -120), Vector2(0, -140), Vector2(-26, -120)])
	_art.draw_colored_polygon(cloak, Color(c, 0.85 * a))
	_art.draw_polyline(cloak + PackedVector2Array([cloak[0]]), Color(Game.DEEP_MOSS, a), 3.0)
	_art.draw_circle(tf * Vector2(0, -160), 24.0 * s, Color(c, 0.9 * a))           # hood
	_art.draw_arc(tf * Vector2(0, -160), 24.0 * s, PI * 0.15, PI * 0.85, 10, Color(Game.DEEP_MOSS, a), 3.0)
	_art.draw_line(tf * Vector2(26, -60), tf * Vector2(56, 8), Color(Game.PALE_JADE, 0.8 * a), 3.0)   # the rapier
	_art.draw_line(tf * Vector2(20, -66), tf * Vector2(32, -54), Color(Game.PALE_JADE, 0.8 * a), 5.0)


# --- ui ----------------------------------------------------------------
func _draw_ui() -> void:
	var w := size.x
	var h := size.y
	# the caption, as it becomes whole
	var cap := _k(WHOLE + 1.0, WHOLE + 3.0) * (1.0 - _k(WHOLE + 8.0, WHOLE + 10.0))
	if cap > 0.0:
		UI.text(_ui, Vector2(_cx(), h * 0.80), "THE GREEN SAPPHIRE IS WHOLE", 34, Color(UI.JADE, cap), 600, 0.2, 0)

	# the credits, rolling up the right of the screen
	if _t > CREDITS_FROM and _t < CREDITS_TO + 4.0:
		var x := w * 0.78
		var f := (_t - CREDITS_FROM) / (CREDITS_TO - CREDITS_FROM)
		var y := lerpf(h + 40.0, -_credits_h - 40.0, f)
		for line in CREDITS:
			var sz := int(line[1])
			if line[0] != "" and y > -60.0 and y < h + 20.0:
				# fade in at the bottom, out at the top
				var edge := minf(clampf((h - y) / 140.0, 0.0, 1.0), clampf((y - 30.0) / 140.0, 0.0, 1.0))
				UI.text(_ui, Vector2(x, y), line[0], sz, Color(UI.JADE, float(line[3]) * edge), int(line[2]), 0.12, 0)
			y += float(sz) + 16.0
