extends "res://scripts/envs/env_base.gd"
## Cell I, the Turnkey's treasure room: a vault wall of arched alcoves full of
## coin and goblets, a great round vault door in the middle, a chequered floor
## with a bevelled octagon rim, and treasure heaped everywhere off the floor:
## coin mounds, chests, goblets, urns and loose gems. Coin glints twinkle.

var _blocks: Array = []      # wall ashlar {r, a}
var _niches: Array = []      # Rect2 alcoves
var _pillars: Array = []     # Rect2
var _tiles: Array = []       # {pts, a}
var _ground: Array = []      # treasure pieces, back to front
var _glints: Array = []      # {p, ph, s}


func _init() -> void:
	seed_value = 21
	mote_count = 30


func _build(rng: RandomNumberGenerator) -> void:
	var foot := arena.position.y
	# vault wall: big ashlar courses
	var y := 0.0
	while y < foot:
		var x := -rng.randf_range(0.0, 60.0)
		while x < vp.x:
			var w := rng.randf_range(70.0, 130.0)
			_blocks.append({"r": Rect2(x + 2, y + 2, w - 4, 34), "a": rng.randf_range(0.16, 0.24)})
			x += w
		y += 38.0
	# alcoves along the wall, pillars between, the vault door in the middle
	var nx := 60.0
	while nx < vp.x - 60.0:
		if absf(nx + 55.0 - vp.x * 0.5) > 170.0:
			_niches.append(Rect2(nx, foot - 190.0, 110.0, 160.0))
		_pillars.append(Rect2(nx - 34.0, 40.0, 24.0, foot - 40.0))
		nx += rng.randf_range(190.0, 230.0)
	for n in _niches:
		_heap(rng, Vector2(n.get_center().x, n.end.y - 4.0), 40.0, true)

	# chequered floor, clipped to the octagon
	var s := 56.0
	var i := 0
	var ty := arena.position.y
	while ty < arena.end.y:
		var tx := arena.position.x
		var j := 0
		while tx < arena.end.x:
			var a := 0.13 if (i + j) % 2 == 0 else 0.05
			for piece in Geometry2D.intersect_polygons(box(Vector2(tx + s * 0.5, ty + s * 0.5), Vector2(s - 3, s - 3)), poly):
				_tiles.append({"pts": piece, "a": a})
			tx += s
			j += 1
		ty += s
		i += 1

	# treasure everywhere off the floor
	for q in scatter(rng, foot - 6.0, 1300, 14.0, 40.0):
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.4:
			_heap(rng, p, r, false)
		elif roll < 0.58:
			_ground.append({"kind": "chest", "p": p, "w": r * 1.7, "y": p.y})
		elif roll < 0.72:
			_ground.append({"kind": "goblet", "p": p, "h": r * 1.4, "y": p.y})
		elif roll < 0.84:
			_ground.append({"kind": "urn", "p": p, "r": r * 0.75, "y": p.y})
		else:
			for k in rng.randi_range(3, 6):
				_ground.append({"kind": "gem", "p": p + Vector2(rng.randf_range(-r, r), rng.randf_range(-r * 0.4, r * 0.4)),
					"s": rng.randf_range(5.0, 10.0), "y": p.y})
	_ground.sort_custom(func(a, b): return a.y < b.y)


## A coin mound: a low dome with coins piled on it, and a few glints.
func _heap(rng: RandomNumberGenerator, base: Vector2, r: float, niche: bool) -> void:
	var coins := PackedVector2Array()
	for k in int(r * 0.9):
		var a := rng.randf_range(PI, TAU)
		var d := rng.randf() * r
		coins.append(base + Vector2(cos(a) * d, sin(a) * d * 0.6))
	_ground.append({"kind": "heap", "p": base, "r": r, "coins": coins, "y": base.y if not niche else -1.0})
	for k in rng.randi_range(1, 3):
		_glints.append({"p": coins[rng.randi() % coins.size()] + Vector2(0, -4), "ph": rng.randf() * TAU,
			"s": rng.randf_range(0.7, 1.3)})


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	var foot := arena.position.y
	for b in _blocks:
		draw_rect(b.r, Color(c, b.a))

	# vault door: rings, spokes and a hub, set into the wall
	var vd := Vector2(vp.x * 0.5, foot - 120.0)
	draw_circle(vd, 118, Game.DEEP_MOSS)
	draw_circle(vd, 112, Color(c, 0.36))
	draw_circle(vd, 92, Color(c, 0.22))
	for k in 12:
		var d := Vector2(1, 0).rotated(TAU * k / 12.0)
		draw_circle(vd + d * 102, 5, Color(c, 0.6))
	for k in 6:
		var d := Vector2(1, 0).rotated(TAU * k / 6.0 + 0.3)
		draw_line(vd + d * 22, vd + d * 86, Color(c, 0.5), 6.0)
	draw_circle(vd, 26, Color(c, 0.55))
	draw_circle(vd, 12, Game.DEEP_MOSS)

	for p in _pillars:
		draw_rect(p, Game.DEEP_MOSS)
		draw_rect(p, Color(c, 0.3))
		draw_rect(Rect2(p.position, Vector2(7, p.size.y)), Color(c, 0.42))
		draw_rect(Rect2(p.position - Vector2(6, 4), Vector2(p.size.x + 12, 12)), Color(c, 0.45))
	for n in _niches:
		draw_rect(n, Game.DEEP_MOSS)
		draw_circle(Vector2(n.get_center().x, n.position.y), n.size.x * 0.5, Game.DEEP_MOSS)
		draw_rect(n, Color(c, 0.06))
		draw_arc(Vector2(n.get_center().x, n.position.y), n.size.x * 0.5 + 4, PI, TAU, 24, Color(c, 0.45), 6.0)
		draw_line(n.position - Vector2(4, 0), Vector2(n.position.x - 4, n.end.y), Color(c, 0.45), 6.0)
		draw_line(Vector2(n.end.x + 4, n.position.y), Vector2(n.end.x + 4, n.end.y), Color(c, 0.45), 6.0)
	for g in _ground:
		if g.kind == "heap" and g.y < 0.0:
			_draw_piece(g)
	draw_rect(Rect2(0, foot - 12.0, vp.x, 12.0), Color(c, 0.38))

	draw_rim(20.0, 0.4, 0.28)
	for t_ in _tiles:
		draw_colored_polygon(t_.pts, Color(c, t_.a))
	# a gilt inlay: an inner octagon line
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(centre + (p - centre) * 0.55)
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(c, 0.3), 3.0)

	for g in _ground:
		if not (g.kind == "heap" and g.y < 0.0):
			_draw_piece(g)


func _draw_piece(g: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	match g.kind:
		"heap":
			var p: Vector2 = g.p
			var r: float = g.r
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(p + Vector2(cos(a) * r, sin(a) * r * 0.62))
			draw_colored_polygon(dome, Color(c, 0.3))
			for cp in g.coins:
				draw_colored_polygon(Transform2D(0.0, cp) * Game.ellipse(4.5, 2.2, 8), Color(c, 0.58))
				draw_line(cp - Vector2(4, 0), cp + Vector2(4, 0), Game.DEEP_MOSS, 1.0)
		"chest":
			var p: Vector2 = g.p
			var w: float = g.w
			var body := Rect2(p.x - w * 0.5, p.y - w * 0.55, w, w * 0.55)
			draw_rect(body, Color(c, 0.34))
			draw_colored_polygon(PackedVector2Array([body.position, Vector2(body.end.x, body.position.y),
				Vector2(body.end.x - 4, body.position.y - w * 0.28), Vector2(body.position.x + 4, body.position.y - w * 0.28)]), Color(c, 0.46))
			draw_line(Vector2(body.position.x + w * 0.2, body.position.y - w * 0.28), Vector2(body.position.x + w * 0.2, body.end.y), Game.DEEP_MOSS, 3.0)
			draw_line(Vector2(body.end.x - w * 0.2, body.position.y - w * 0.28), Vector2(body.end.x - w * 0.2, body.end.y), Game.DEEP_MOSS, 3.0)
			draw_rect(Rect2(p.x - 5, body.position.y - 4, 10, 12), Color(c, 0.7))
		"goblet":
			var p: Vector2 = g.p
			var h: float = g.h
			draw_colored_polygon(Transform2D(0.0, p) * Game.ellipse(h * 0.35, h * 0.1), Color(c, 0.4))
			draw_line(p, p - Vector2(0, h * 0.55), Color(c, 0.45), 4.0)
			draw_colored_polygon(PackedVector2Array([p - Vector2(h * 0.4, h), p - Vector2(-h * 0.4, h), p - Vector2(0, h * 0.5)]), Color(c, 0.5))
			draw_line(p - Vector2(h * 0.4, h), p - Vector2(-h * 0.4, h), Color(c, 0.7), 3.0)
		"urn":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_circle(p - Vector2(0, r), r, Color(c, 0.32))
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 2.5, r * 0.8, r * 0.7), Color(c, 0.4))
			draw_line(p - Vector2(r * 0.8, r * 1.1), p - Vector2(-r * 0.8, r * 1.1), Game.DEEP_MOSS, 2.0)
		"gem":
			var p: Vector2 = g.p
			var s: float = g.s
			draw_colored_polygon(PackedVector2Array([p - Vector2(0, s * 1.4), p + Vector2(s * 0.7, -s * 0.5), p, p - Vector2(s * 0.7, s * 0.5)]), Color(c, 0.62))


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	for g in _glints:
		var a := maxf(0.0, sin(t * 1.7 * float(g.s) + float(g.ph)))
		if a < 0.2:
			continue
		var p: Vector2 = g.p
		var r := 3.0 + 6.0 * a
		l.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(c, 0.85 * a), 2.0)
		l.draw_line(p - Vector2(0, r), p + Vector2(0, r), Color(c, 0.85 * a), 2.0)
	draw_motes(l, Color(c, 0.4), 2.0, 6.0)
