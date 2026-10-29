extends "res://scripts/envs/env_base.gd"
## Cell II, the Pendulum's library. Back to front:
##   a gallery rail running under the cornice; tall bookshelves crammed with
##   spines, broken by two pointed windows that let moonlight in, and in the
##   middle a great clock face the Pendulum hangs in front of, its hands
##   ticking; a ladder leaning on the shelves; lanterns hanging on chains;
##   a plank floor with a long patterned rug, moonlight lying across it;
##   reading desks with candles in the cut corners, a lectern with an open
##   book, stacks of books, scrolls, globes and candles everywhere off the floor;
##   a vignette. Pages drift and tumble, flames flicker, dust turns in the moonlight.

const P := preload("res://scripts/paint.gd")

var _spines: Array = []      # {pts, a}
var _shelves: Array = []     # Rect2 shelf units
var _windows: Array = []     # Rect2 window openings (arch above)
var _planks: Array = []      # {pts, a}
var _ground: Array = []
var _candles: Array = []     # Vector2 flame positions
var _lanterns: Array = []    # {p, len}
var _pages: Array = []       # {p, v, ph, s}
var _shafts: Array = []      # [a0, a1, b0, b1]
var _clock := Vector2.ZERO


func _init() -> void:
	seed_value = 31
	mote_count = 40
	mote_drift = Vector2(4, -7)


func _build(rng: RandomNumberGenerator) -> void:
	var foot := arena.position.y
	_clock = Vector2(vp.x * 0.5, 120.0)
	var win_x := [vp.x * 0.2, vp.x * 0.8]
	# shelf units across the back wall, each with five rows of spines, leaving
	# room for the clock in the middle and the two windows
	var x := -10.0
	while x < vp.x:
		var w := rng.randf_range(140.0, 180.0)
		var mid := x + w * 0.5
		var blocked := absf(mid - _clock.x) < 150.0
		for wx in win_x:
			if absf(mid - wx) < 90.0:
				blocked = true
		if not blocked:
			var unit := Rect2(x + 6.0, 50.0, w - 12.0, foot - 62.0)
			_shelves.append(unit)
			_fill_shelf(rng, unit)
		x += w
	for wx in win_x:
		var win := Rect2(wx - 46.0, 140.0, 92.0, foot - 186.0)
		_windows.append(win)
		# moonlight falls from the window and across the floor
		var lean := 140.0 if wx < vp.x * 0.5 else -140.0
		_shafts.append([win.position + Vector2(8, 40), Vector2(win.end.x - 8, win.position.y + 40),
			Vector2(win.position.x - 40 + lean * 2.0, foot + 300.0), Vector2(win.end.x + 40 + lean * 2.0, foot + 300.0)])

	for lx in [vp.x * 0.1, vp.x * 0.36, vp.x * 0.64, vp.x * 0.9]:
		_lanterns.append({"p": Vector2(lx, rng.randf_range(150.0, 190.0)), "ph": rng.randf() * TAU})

	# plank floor, clipped to the hall
	var py := arena.position.y
	while py < arena.end.y:
		var px := arena.position.x - rng.randf_range(0.0, 120.0)
		while px < arena.end.x:
			var pw := rng.randf_range(130.0, 260.0)
			for piece in Geometry2D.intersect_polygons(box(Vector2(px + pw * 0.5, py + 12.0), Vector2(pw - 3.0, 22.0)), poly):
				_planks.append({"pts": piece, "a": rng.randf_range(0.05, 0.12)})
			px += pw
		py += 25.0

	# desks with candles in the cut corners, a lectern, then clutter everywhere else
	for corner in [arena.position, Vector2(arena.end.x, arena.position.y), Vector2(arena.position.x, arena.end.y), arena.end]:
		var c: Vector2 = corner + (centre - corner).normalized() * 30.0
		_ground.append({"kind": "desk", "p": c, "y": c.y})
		_candles.append(c + Vector2(26, -58))
	for q in scatter(rng, foot - 6.0, 1200, 14.0, 38.0):
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.5:
			var books: Array = []
			var h := 0.0
			for k in rng.randi_range(2, 7):
				var bw := rng.randf_range(r * 1.2, r * 2.0)
				var bh := rng.randf_range(7.0, 11.0)
				books.append({"r": Rect2(p.x - bw * 0.5 + rng.randf_range(-5, 5), p.y - h - bh, bw, bh), "a": rng.randf_range(0.26, 0.44)})
				h += bh + 1.0
			_ground.append({"kind": "stack", "books": books, "y": p.y})
		elif roll < 0.66:
			_ground.append({"kind": "scroll", "p": p, "w": r * 1.6, "y": p.y})
		elif roll < 0.74:
			_ground.append({"kind": "globe", "p": p, "r": r * 0.8, "y": p.y})
		elif roll < 0.82:
			_ground.append({"kind": "lectern", "p": p, "y": p.y})
		elif roll < 0.9:
			_ground.append({"kind": "open", "p": p, "w": r * 1.4, "y": p.y})
		else:
			_ground.append({"kind": "candle", "p": p, "h": rng.randf_range(18.0, 34.0), "y": p.y})
			_candles.append(p + Vector2(0, -6) - Vector2(0, _ground[-1].h))
	_ground.sort_custom(func(a, b): return a.y < b.y)

	for i in 16:
		_pages.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y), "v": rng.randf_range(10.0, 24.0),
			"ph": rng.randf() * TAU, "s": rng.randf_range(0.8, 1.3)})


func _fill_shelf(rng: RandomNumberGenerator, unit: Rect2) -> void:
	var rows := 5
	var rh := unit.size.y / rows
	for r in rows:
		var by := unit.position.y + (r + 1) * rh - 6.0
		var sx := unit.position.x + 6.0
		while sx < unit.end.x - 10.0:
			var bw := rng.randf_range(6.0, 15.0)
			var bh := rh * rng.randf_range(0.6, 0.9)
			if rng.randf() < 0.08:
				sx += bw * 2.0      # a gap on the shelf
				continue
			var lean := rng.randf_range(4.0, 12.0) if rng.randf() < 0.1 else 0.0
			# higher shelves sit further from the candles: dimmer
			var a := rng.randf_range(0.2, 0.42) * lerpf(0.75, 1.0, float(r) / (rows - 1))
			_spines.append({"pts": PackedVector2Array([Vector2(sx, by), Vector2(sx + bw, by),
				Vector2(sx + bw + lean, by - bh), Vector2(sx + lean, by - bh)]), "a": a, "band": rng.randf() < 0.3})
			sx += bw + 1.5 + lean


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	var foot := arena.position.y
	P.vband(self, Rect2(0, 0, vp.x, foot), 0.04, 0.14)
	for u in _shelves:
		draw_rect(u, Game.DEEP_MOSS)
		draw_rect(u, Color(c, 0.08))
	for s in _spines:
		draw_colored_polygon(s.pts, Color(c, s.a))
		if s.band:
			var p0: Vector2 = s.pts[3].lerp(s.pts[0], 0.2)
			var p1: Vector2 = s.pts[2].lerp(s.pts[1], 0.2)
			draw_line(p0, p1, Game.DEEP_MOSS, 2.0)
	for u in _shelves:
		var rh: float = u.size.y / 5.0
		for r in 6:
			draw_line(Vector2(u.position.x, u.position.y + r * rh), Vector2(u.end.x, u.position.y + r * rh), Color(c, 0.46), 5.0)
		draw_line(u.position, Vector2(u.position.x, u.end.y), Color(c, 0.46), 6.0)
		draw_line(Vector2(u.end.x, u.position.y), u.end, Color(c, 0.46), 6.0)
		# a carved crest over each unit
		draw_arc(Vector2(u.get_center().x, u.position.y), 18.0, PI, TAU, 12, Color(c, 0.36), 3.0)
	for win in _windows:
		_window(win)
	_clock_face()

	# the gallery: cornice, balusters and a handrail along the top
	draw_rect(Rect2(0, 0, vp.x, 50), Game.DEEP_MOSS)
	P.vband(self, Rect2(0, 0, vp.x, 50), 0.08, 0.2)
	var bx := 6.0
	while bx < vp.x:
		draw_line(Vector2(bx, 22), Vector2(bx, 44), Color(c, 0.34), 4.0)
		bx += 16.0
	draw_line(Vector2(0, 20), Vector2(vp.x, 20), Color(c, 0.5), 5.0)
	draw_rect(Rect2(0, 44, vp.x, 8), Color(c, 0.44))

	# a ladder leaning on the shelves
	var lx := vp.x * 0.33
	draw_line(Vector2(lx, 52), Vector2(lx - 50, foot), Color(c, 0.6), 5.0)
	draw_line(Vector2(lx + 40, 52), Vector2(lx - 10, foot), Color(c, 0.6), 5.0)
	for k in 9:
		var f := (k + 0.5) / 9.0
		draw_line(Vector2(lx - 50 * f, 52 + (foot - 52) * f), Vector2(lx + 40 - 50 * f, 52 + (foot - 52) * f), Color(c, 0.55), 4.0)
	draw_rect(Rect2(0, foot - 10.0, vp.x, 10.0), Color(c, 0.42))

	# lantern chains (the lanterns themselves sway, on the live layer)
	for ln in _lanterns:
		P.glow(self, ln.p + Vector2(0, 30), 110.0, 0.12)

	draw_rim(16.0, 0.38, 0.26)
	for p in _planks:
		draw_colored_polygon(p.pts, Color(c, p.a))
	_rug()
	for s in _shafts:
		P.shaft(self, s[0], s[1], s[2], s[3], 0.16)
	for cnd in _candles:
		P.glow(self, cnd, 70.0, 0.14)

	for g in _ground:
		_draw_piece(g)
	P.vignette(self, vp, 160.0, 0.6)


## A tall pointed window: dark glass, mullions, tracery, a moonlit sill.
func _window(win: Rect2) -> void:
	var c := Game.SAPPHIRE_CORE
	var glass := _arch(win, 0.0)
	draw_colored_polygon(_arch(win, 10.0), Color(c, 0.3))
	draw_colored_polygon(glass, Game.DEEP_MOSS)
	# moonlit glass, brightest at the top
	P.gradient(self, glass, Vector2(0, win.position.y - win.size.x * 0.87), Vector2(0, win.end.y), 0.36, 0.1)
	# tracery: a round light in the arch, mullion and transoms below it
	var rose := Vector2(win.get_center().x, win.position.y - win.size.x * 0.3)
	draw_circle(rose, 15.0, Game.DEEP_MOSS)
	draw_circle(rose, 9.0, Color(c, 0.4))
	draw_arc(rose, 15.0, 0, TAU, 18, Color(c, 0.5), 3.0)
	draw_line(Vector2(rose.x, rose.y + 15.0), Vector2(rose.x, win.end.y), Game.DEEP_MOSS, 5.0)
	for k in range(1, 4):
		var y := win.position.y + win.size.y * k / 4.0
		draw_line(Vector2(win.position.x, y), Vector2(win.end.x, y), Game.DEEP_MOSS, 3.0)
	draw_polyline(glass, Color(c, 0.5), 3.0)
	draw_rect(Rect2(win.position.x - 14, win.end.y, win.size.x + 28, 10), Color(c, 0.5))
	# the moon, low in the right pane
	draw_circle(Vector2(win.get_center().x + win.size.x * 0.24, win.position.y + 30.0), 12.0, Color(c, 0.55))


## A pointed (equilateral) arch over `win`, grown outward by `grow`.
func _arch(win: Rect2, grow: float) -> PackedVector2Array:
	var r := win.grow(grow)
	var w := r.size.x
	var y0 := r.position.y
	var pts := PackedVector2Array([Vector2(r.position.x, r.end.y)])
	for k in 9:
		var a := PI + PI / 3.0 * k / 8.0       # left side, centred on the right springer
		pts.append(Vector2(r.end.x, y0) + Vector2(cos(a), sin(a)) * w)
	for k in range(1, 9):
		var a := -PI / 3.0 + PI / 3.0 * k / 8.0  # right side, centred on the left springer
		pts.append(Vector2(r.position.x, y0) + Vector2(cos(a), sin(a)) * w)
	pts.append(r.end)
	return pts


## The clock the Pendulum swings from: rings, hour marks, numeral bars and
## a carved surround. The hands are on the live layer.
func _clock_face() -> void:
	var c := Game.SAPPHIRE_CORE
	var r := 112.0
	P.glow(self, _clock, r * 1.8, 0.12)
	# carved surround: a square case with corner rosettes
	var case_r := Rect2(_clock - Vector2(r + 22, r + 6), Vector2((r + 22) * 2, r * 2 + 60))
	draw_rect(case_r, Game.DEEP_MOSS)
	draw_rect(case_r, Color(c, 0.2))
	draw_rect(case_r.grow(-6), Color(c, 0.12))
	for k in [case_r.position + Vector2(14, 14), Vector2(case_r.end.x - 14, case_r.position.y + 14)]:
		draw_circle(k, 8, Color(c, 0.42))
	draw_circle(_clock, r + 10, Game.DEEP_MOSS)
	draw_circle(_clock, r + 6, Color(c, 0.42))
	draw_circle(_clock, r - 2, Color(c, 0.2))
	draw_arc(_clock, r - 18, 0, TAU, 64, Color(c, 0.3), 2.0)
	for k in 60:
		var d := Vector2(0, -1).rotated(TAU * k / 60.0)
		var long := k % 5 == 0
		draw_line(_clock + d * (r - (16.0 if long else 8.0)), _clock + d * (r - 4.0), Color(c, 0.6 if long else 0.34), 3.0 if long else 1.5)
	# numeral bars: one bar per hour (I..XII as tally strokes)
	for k in 12:
		var d := Vector2(0, -1).rotated(TAU * k / 12.0)
		var p := _clock + d * (r - 34.0)
		var n := k if k > 0 else 12
		var strokes := mini(n, 4)
		for s in strokes:
			var off := d.orthogonal() * (s - (strokes - 1) * 0.5) * 4.0
			draw_line(p + off - d * 5.0, p + off + d * 5.0, Color(c, 0.44), 1.5)
	# the pendulum's window below the face
	draw_rect(Rect2(_clock + Vector2(-26, r + 16), Vector2(52, 30)), Color(Game.DEEP_MOSS))
	draw_rect(Rect2(_clock + Vector2(-26, r + 16), Vector2(52, 30)), Color(c, 0.1))


func _rug() -> void:
	var c := Game.SAPPHIRE_CORE
	var rug := Rect2(centre - Vector2(arena.size.x * 0.28, arena.size.y * 0.3), Vector2(arena.size.x * 0.56, arena.size.y * 0.6))
	draw_rect(rug, Color(c, 0.1))
	draw_rect(rug.grow(-14), Color(Game.DEEP_MOSS, 0.5))
	draw_rect(rug.grow(-20), Color(c, 0.07))
	var dx := rug.position.x + 16.0
	while dx < rug.end.x - 10.0:
		for yy in [rug.position.y + 7.0, rug.end.y - 7.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(dx, yy - 5), Vector2(dx + 6, yy), Vector2(dx, yy + 5), Vector2(dx - 6, yy)]), Color(c, 0.17))
		dx += 22.0
	# a medallion in the middle: nested lozenges and a ring
	var m := rug.get_center()
	for k in 3:
		var s := 120.0 - k * 34.0
		draw_polyline(PackedVector2Array([m + Vector2(0, -s * 0.6), m + Vector2(s, 0), m + Vector2(0, s * 0.6), m + Vector2(-s, 0), m + Vector2(0, -s * 0.6)]),
			Color(c, 0.13), 3.0)
	draw_arc(m, 26.0, 0, TAU, 32, Color(c, 0.13), 3.0)
	# fringe at the short ends
	var fy := rug.position.y
	while fy < rug.end.y:
		draw_line(Vector2(rug.position.x - 8, fy), Vector2(rug.position.x, fy), Color(c, 0.14), 2.0)
		draw_line(Vector2(rug.end.x, fy), Vector2(rug.end.x + 8, fy), Color(c, 0.14), 2.0)
		fy += 9.0


func _draw_piece(g: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	match g.kind:
		"desk":
			var p: Vector2 = g.p
			draw_colored_polygon(Transform2D(0.0, p + Vector2(0, 2)) * Game.ellipse(58, 10), Color(Game.DEEP_MOSS, 0.6))
			draw_rect(Rect2(p.x - 50, p.y - 44, 100, 12), Color(c, 0.48))
			draw_line(Vector2(p.x - 50, p.y - 44), Vector2(p.x + 50, p.y - 44), Color(c, 0.62), 2.0)
			draw_line(Vector2(p.x - 42, p.y - 32), Vector2(p.x - 42, p.y), Color(c, 0.4), 5.0)
			draw_line(Vector2(p.x + 42, p.y - 32), Vector2(p.x + 42, p.y), Color(c, 0.4), 5.0)
			draw_colored_polygon(PackedVector2Array([Vector2(p.x - 30, p.y - 46), Vector2(p.x - 2, p.y - 50), Vector2(p.x - 2, p.y - 62), Vector2(p.x - 30, p.y - 56)]), Color(c, 0.6))
			draw_colored_polygon(PackedVector2Array([Vector2(p.x + 2, p.y - 50), Vector2(p.x + 26, p.y - 46), Vector2(p.x + 26, p.y - 56), Vector2(p.x + 2, p.y - 62)]), Color(c, 0.5))
			for k in 3:
				draw_line(Vector2(p.x - 26, p.y - 52 - k * 2.5), Vector2(p.x - 6, p.y - 55 - k * 2.5), Game.DEEP_MOSS, 1.0)
			draw_rect(Rect2(p.x + 22, p.y - 58, 8, 14), Color(c, 0.62))
			# a quill in a pot
			draw_rect(Rect2(p.x - 44, p.y - 54, 9, 10), Color(c, 0.5))
			draw_line(Vector2(p.x - 40, p.y - 54), Vector2(p.x - 30, p.y - 78), Color(c, 0.5), 2.0)
		"stack":
			for b in g.books:
				draw_rect(b.r, Color(c, b.a))
				draw_line(b.r.position + Vector2(3, b.r.size.y * 0.5), b.r.position + Vector2(b.r.size.x - 3, b.r.size.y * 0.5), Game.DEEP_MOSS, 1.0)
				draw_line(Vector2(b.r.end.x - 4, b.r.position.y + 1), Vector2(b.r.end.x - 4, b.r.end.y - 1), Color(c, 0.6), 1.5)
		"scroll":
			var p: Vector2 = g.p
			var w: float = g.w
			draw_rect(Rect2(p.x - w * 0.5, p.y - 10, w, 10), Color(c, 0.38))
			draw_circle(p - Vector2(w * 0.5, 5), 6, Color(c, 0.52))
			draw_circle(p + Vector2(w * 0.5, -5), 6, Color(c, 0.52))
			draw_line(p + Vector2(-w * 0.3, -5), p + Vector2(w * 0.3, -5), Game.DEEP_MOSS, 1.0)
		"globe":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_line(p, p - Vector2(0, r * 0.8), Color(c, 0.45), 4.0)
			draw_line(p + Vector2(-r * 0.5, 0), p + Vector2(r * 0.5, 0), Color(c, 0.45), 4.0)
			draw_circle(p - Vector2(0, r * 1.9), r, Color(c, 0.34))
			draw_arc(p - Vector2(0, r * 1.9), r * 0.55, -PI * 0.5, PI * 0.5, 12, Color(Game.DEEP_MOSS, 0.8), 2.0)
			draw_arc(p - Vector2(0, r * 1.9), r + 4, -PI * 0.9, PI * 0.4, 16, Color(c, 0.56), 3.0)
			draw_line(p - Vector2(r, r * 1.9), p - Vector2(-r, r * 1.9), Game.DEEP_MOSS, 2.0)
		"lectern":
			var p: Vector2 = g.p
			draw_line(p, p - Vector2(0, 40), Color(c, 0.45), 6.0)
			draw_line(p + Vector2(-16, 0), p + Vector2(16, 0), Color(c, 0.45), 5.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-26, -40), p + Vector2(26, -40), p + Vector2(22, -52), p + Vector2(-22, -52)]), Color(c, 0.44))
			_open_book(p + Vector2(0, -54), 44.0)
		"open":
			_open_book(g.p, g.w)
		"candle":
			var p: Vector2 = g.p
			var h: float = g.h
			draw_colored_polygon(Transform2D(0.0, p) * Game.ellipse(10, 4), Color(c, 0.45))
			draw_rect(Rect2(p.x - 5, p.y - h, 10, h), Color(c, 0.5))
			draw_line(Vector2(p.x - 5, p.y - h + 3), Vector2(p.x - 5, p.y - h + 12), Color(c, 0.7), 2.0)   # a drip


func _open_book(p: Vector2, w: float) -> void:
	var c := Game.SAPPHIRE_CORE
	var h := w * 0.32
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(-w * 0.5, -3), p + Vector2(-w * 0.5, -h - 3), p + Vector2(0, -h)]), Color(c, 0.6))
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(w * 0.5, -3), p + Vector2(w * 0.5, -h - 3), p + Vector2(0, -h)]), Color(c, 0.5))
	for k in 3:
		var y := -h * 0.3 - k * h * 0.22
		draw_line(p + Vector2(-w * 0.42, y - 1), p + Vector2(-w * 0.08, y + 1), Game.DEEP_MOSS, 1.0)
		draw_line(p + Vector2(w * 0.08, y + 1), p + Vector2(w * 0.42, y - 1), Game.DEEP_MOSS, 1.0)


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	# the clock's hands creep round; the second hand ticks
	var hr := t * 0.02
	var mn := t * 0.24
	var sec := floorf(t) * TAU / 60.0
	l.draw_line(_clock, _clock + Vector2(0, -56).rotated(hr + 1.2), Color(c, 0.56), 6.0)
	l.draw_line(_clock, _clock + Vector2(0, -84).rotated(mn + 4.0), Color(c, 0.5), 4.0)
	l.draw_line(_clock - Vector2(0, -16).rotated(sec), _clock + Vector2(0, -92).rotated(sec), Color(c, 0.4), 1.5)
	l.draw_circle(_clock, 7.0, Color(c, 0.62))

	# lanterns sway on their chains
	for ln in _lanterns:
		var top: Vector2 = Vector2(ln.p.x, 52.0)
		var sway := sin(t * 0.9 + float(ln.ph)) * 0.05
		var bot: Vector2 = top + Vector2(0, ln.p.y - 52.0).rotated(sway)
		l.draw_line(top, bot, Color(c, 0.4), 2.0)
		var body := PackedVector2Array([bot + Vector2(-10, 4), bot + Vector2(10, 4), bot + Vector2(13, 30), bot + Vector2(-13, 30)])
		l.draw_colored_polygon(body, Color(c, 0.42))
		l.draw_polyline(body + PackedVector2Array([body[0]]), Color(c, 0.6), 2.0)
		l.draw_colored_polygon(PackedVector2Array([bot + Vector2(-14, 4), bot + Vector2(14, 4), bot + Vector2(0, -6)]), Color(c, 0.55))
		P.flame(l, bot + Vector2(0, 24), 12.0, t, float(ln.ph) * 5.0, 0.8)

	for i in _candles.size():
		P.flame(l, _candles[i], 12.0, t, float(i) * 2.9)
	# loose pages drift down and sideways, tumbling
	for pg in _pages:
		var p := Vector2(fposmod(pg.p.x + t * float(pg.v) + sin(t + float(pg.ph)) * 30.0, vp.x),
			fposmod(pg.p.y + t * float(pg.v) * 0.6, vp.y))
		var flip := sin(t * 1.6 + float(pg.ph))
		flip = signf(flip) * maxf(absf(flip), 0.2)    # never edge-on: a flat quad won't triangulate
		var tf := Transform2D(sin(t * 0.8 + float(pg.ph)) * 1.2, p)
		var s: float = pg.s
		var pts := PackedVector2Array([Vector2(-8 * flip, -6) * s, Vector2(8 * flip, -6) * s, Vector2(8 * flip, 6) * s, Vector2(-8 * flip, 6) * s])
		l.draw_colored_polygon(tf * pts, Color(c, 0.3 + 0.2 * absf(flip)))
	# dust: brighter in the moonlight
	for m in motes:
		var p: Vector2 = m.p + Vector2(sin(t * 0.6 + float(m.ph)) * 5.0, 0)
		var lit := false
		for s in _shafts:
			if Geometry2D.is_point_in_polygon(p, PackedVector2Array([s[0], s[1], s[3], s[2]])):
				lit = true
				break
		l.draw_circle(p, 2.4 if lit else 1.8, Color(c, 0.6 if lit else 0.26))
