extends "res://scripts/envs/env_base.gd"
## Cell II, the Pendulum's library: a back wall of tall bookshelves crammed
## with spines, a ladder, a plank floor with a long rug, reading desks with
## candles in the corners, and stacks of books, scrolls and a globe off the
## floor. Loose pages drift through the air and the candles flicker.

var _spines: Array = []      # {pts, a}
var _shelves: Array = []     # Rect2 shelf units
var _planks: Array = []      # {pts, a}
var _ground: Array = []
var _candles: Array = []     # Vector2 flame positions
var _pages: Array = []       # {p, v, ph, s}


func _init() -> void:
	seed_value = 31
	mote_count = 34
	mote_drift = Vector2(4, -7)


func _build(rng: RandomNumberGenerator) -> void:
	var foot := arena.position.y
	# shelf units across the back wall, each with five rows of spines
	var x := -10.0
	while x < vp.x:
		var w := rng.randf_range(140.0, 180.0)
		var unit := Rect2(x + 6.0, 34.0, w - 12.0, foot - 46.0)
		_shelves.append(unit)
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
				_spines.append({"pts": PackedVector2Array([Vector2(sx, by), Vector2(sx + bw, by),
					Vector2(sx + bw + lean, by - bh), Vector2(sx + lean, by - bh)]), "a": rng.randf_range(0.2, 0.42)})
				sx += bw + 1.5 + lean
		x += w

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

	# desks with candles in the cut corners, then clutter everywhere else
	for corner in [arena.position, Vector2(arena.end.x, arena.position.y), Vector2(arena.position.x, arena.end.y), arena.end]:
		var c: Vector2 = corner + (centre - corner).normalized() * 30.0
		_ground.append({"kind": "desk", "p": c, "y": c.y})
		_candles.append(c + Vector2(26, -58))
	for q in scatter(rng, foot - 6.0, 1100, 14.0, 36.0):
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.55:
			var books: Array = []
			var h := 0.0
			for k in rng.randi_range(2, 6):
				var bw := rng.randf_range(r * 1.2, r * 2.0)
				var bh := rng.randf_range(7.0, 11.0)
				books.append({"r": Rect2(p.x - bw * 0.5 + rng.randf_range(-5, 5), p.y - h - bh, bw, bh), "a": rng.randf_range(0.26, 0.42)})
				h += bh + 1.0
			_ground.append({"kind": "stack", "books": books, "y": p.y})
		elif roll < 0.75:
			_ground.append({"kind": "scroll", "p": p, "w": r * 1.6, "y": p.y})
		elif roll < 0.85:
			_ground.append({"kind": "globe", "p": p, "r": r * 0.8, "y": p.y})
		else:
			_ground.append({"kind": "candle", "p": p, "y": p.y})
			_candles.append(p + Vector2(0, -34))
	_ground.sort_custom(func(a, b): return a.y < b.y)

	for i in 14:
		_pages.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y), "v": rng.randf_range(10.0, 24.0),
			"ph": rng.randf() * TAU, "s": rng.randf_range(0.8, 1.3)})


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	var foot := arena.position.y
	draw_rect(Rect2(0, 0, vp.x, foot), Color(c, 0.1))
	for u in _shelves:
		draw_rect(u, Game.DEEP_MOSS)
		draw_rect(u, Color(c, 0.08))
	for s in _spines:
		draw_colored_polygon(s.pts, Color(c, s.a))
	for u in _shelves:
		var rh: float = u.size.y / 5.0
		for r in 6:
			draw_line(Vector2(u.position.x, u.position.y + r * rh), Vector2(u.end.x, u.position.y + r * rh), Color(c, 0.46), 5.0)
		draw_line(u.position, Vector2(u.position.x, u.end.y), Color(c, 0.46), 6.0)
		draw_line(Vector2(u.end.x, u.position.y), u.end, Color(c, 0.46), 6.0)
	draw_rect(Rect2(0, 18, vp.x, 18), Color(c, 0.42))     # cornice
	# a ladder leaning on the shelves
	var lx := vp.x * 0.27
	draw_line(Vector2(lx, 40), Vector2(lx - 50, foot), Color(c, 0.6), 5.0)
	draw_line(Vector2(lx + 40, 40), Vector2(lx - 10, foot), Color(c, 0.6), 5.0)
	for k in 9:
		var f := (k + 0.5) / 9.0
		draw_line(Vector2(lx - 50 * f, 40 + (foot - 40) * f), Vector2(lx + 40 - 50 * f, 40 + (foot - 40) * f), Color(c, 0.55), 4.0)
	draw_rect(Rect2(0, foot - 10.0, vp.x, 10.0), Color(c, 0.4))

	draw_rim(16.0, 0.38, 0.26)
	for p in _planks:
		draw_colored_polygon(p.pts, Color(c, p.a))
	# a long rug down the middle, with a border of diamonds
	var rug := Rect2(centre - Vector2(arena.size.x * 0.28, arena.size.y * 0.3), Vector2(arena.size.x * 0.56, arena.size.y * 0.6))
	draw_rect(rug, Color(c, 0.1))
	draw_rect(rug.grow(-14), Color(Game.DEEP_MOSS, 0.5))
	draw_rect(rug.grow(-20), Color(c, 0.08))
	var dx := rug.position.x + 16.0
	while dx < rug.end.x - 10.0:
		for yy in [rug.position.y + 7.0, rug.end.y - 7.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(dx, yy - 5), Vector2(dx + 6, yy), Vector2(dx, yy + 5), Vector2(dx - 6, yy)]), Color(c, 0.18))
		dx += 22.0

	for g in _ground:
		_draw_piece(g)


func _draw_piece(g: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	match g.kind:
		"desk":
			var p: Vector2 = g.p
			draw_rect(Rect2(p.x - 50, p.y - 44, 100, 12), Color(c, 0.46))
			draw_line(Vector2(p.x - 42, p.y - 32), Vector2(p.x - 42, p.y), Color(c, 0.4), 5.0)
			draw_line(Vector2(p.x + 42, p.y - 32), Vector2(p.x + 42, p.y), Color(c, 0.4), 5.0)
			draw_colored_polygon(PackedVector2Array([Vector2(p.x - 30, p.y - 46), Vector2(p.x - 2, p.y - 50), Vector2(p.x - 2, p.y - 62), Vector2(p.x - 30, p.y - 56)]), Color(c, 0.6))
			draw_colored_polygon(PackedVector2Array([Vector2(p.x + 2, p.y - 50), Vector2(p.x + 26, p.y - 46), Vector2(p.x + 26, p.y - 56), Vector2(p.x + 2, p.y - 62)]), Color(c, 0.5))
			draw_rect(Rect2(p.x + 22, p.y - 58, 8, 14), Color(c, 0.6))
		"stack":
			for b in g.books:
				draw_rect(b.r, Color(c, b.a))
				draw_line(b.r.position + Vector2(3, b.r.size.y * 0.5), b.r.position + Vector2(b.r.size.x - 3, b.r.size.y * 0.5), Game.DEEP_MOSS, 1.0)
		"scroll":
			var p: Vector2 = g.p
			var w: float = g.w
			draw_rect(Rect2(p.x - w * 0.5, p.y - 10, w, 10), Color(c, 0.36))
			draw_circle(p - Vector2(w * 0.5, 5), 6, Color(c, 0.5))
			draw_circle(p + Vector2(w * 0.5, -5), 6, Color(c, 0.5))
		"globe":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_line(p, p - Vector2(0, r * 0.8), Color(c, 0.45), 4.0)
			draw_circle(p - Vector2(0, r * 1.9), r, Color(c, 0.34))
			draw_arc(p - Vector2(0, r * 1.9), r + 4, -PI * 0.9, PI * 0.4, 16, Color(c, 0.55), 3.0)
			draw_line(p - Vector2(r, r * 1.9), p - Vector2(-r, r * 1.9), Game.DEEP_MOSS, 2.0)
		"candle":
			var p: Vector2 = g.p
			draw_rect(Rect2(p.x - 5, p.y - 28, 10, 28), Color(c, 0.5))


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	for f in _candles:
		var h := 12.0 + 3.0 * sin(t * 12.0 + f.x) + 2.0 * sin(t * 19.0 + f.y)
		l.draw_circle(f, 30.0, Color(c, 0.1))
		l.draw_colored_polygon(PackedVector2Array([f + Vector2(0, -h), f + Vector2(5, -2), f + Vector2(0, 3), f + Vector2(-5, -2)]), Color(c, 0.8))
	# loose pages drift down and sideways, tumbling
	for pg in _pages:
		var p := Vector2(fposmod(pg.p.x + t * float(pg.v) + sin(t + float(pg.ph)) * 30.0, vp.x),
			fposmod(pg.p.y + t * float(pg.v) * 0.6, vp.y))
		var tf := Transform2D(sin(t * 0.8 + float(pg.ph)) * 1.2, p)
		var s: float = pg.s
		l.draw_colored_polygon(tf * PackedVector2Array([Vector2(-8, -6) * s, Vector2(8, -6) * s, Vector2(8, 6) * s, Vector2(-8, 6) * s]), Color(c, 0.45))
	draw_motes(l, Color(c, 0.35), 2.0, 5.0)
