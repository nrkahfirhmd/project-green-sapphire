extends "res://scripts/envs/env_base.gd"
## Cell I, the Turnkey's treasure vault. Back to front:
##   the vault wall, ashlar falling into shadow towards the unseen ceiling, a
##   frieze of carved keys along its top, arched alcoves heaped with coin and
##   hung with banners, braziers burning on the pillars between them;
##   the great round vault door in the middle, bolted, with a keyhole at its
##   hub, flanked by two giant keys standing as statues;
##   two shafts of light falling from gratings high in the wall;
##   the chequered floor with a gilt inner octagon and a keyhole inlay;
##   treasure heaped everywhere off the floor: coin mounds, chests, goblets,
##   urns, crowns, swords and loose gems;
##   a vignette closing the edges in. Coin glints twinkle, braziers flicker, and
##   dust turns in the light.

const P := preload("res://scripts/paint.gd")

var _blocks: Array = []      # wall ashlar {r, a}
var _niches: Array = []      # Rect2 alcoves
var _pillars: Array = []     # Rect2
var _braziers: Array = []    # Vector2 bowl tops
var _banners: Array = []     # {x, top, len}
var _tiles: Array = []       # {pts, a}
var _ground: Array = []      # treasure pieces, back to front
var _glints: Array = []      # {p, ph, s}
var _shafts: Array = []      # [a0, a1, b0, b1]
var _door := Vector2.ZERO


func _init() -> void:
	seed_value = 21
	mote_count = 46


func _build(rng: RandomNumberGenerator) -> void:
	var foot := arena.position.y
	_door = Vector2(vp.x * 0.5, foot - 120.0)
	# vault wall: big ashlar courses, every block a little different
	var y := 0.0
	while y < foot:
		var x := -rng.randf_range(0.0, 60.0)
		while x < vp.x:
			var w := rng.randf_range(70.0, 130.0)
			_blocks.append({"r": Rect2(x + 2, y + 2, w - 4, 34), "a": rng.randf_range(0.15, 0.24)})
			x += w
		y += 38.0
	# alcoves along the wall, pillars between, the vault door in the middle
	var nx := 60.0
	while nx < vp.x - 60.0:
		if absf(nx + 55.0 - vp.x * 0.5) > 250.0:
			_niches.append(Rect2(nx, foot - 190.0, 110.0, 160.0))
		var pil := Rect2(nx - 34.0, 40.0, 24.0, foot - 40.0)
		_pillars.append(pil)
		if absf(pil.get_center().x - vp.x * 0.5) > 220.0 and rng.randf() < 0.75:
			_braziers.append(Vector2(pil.get_center().x, foot - 150.0))
		nx += rng.randf_range(190.0, 230.0)
	for n in _niches:
		_heap(rng, Vector2(n.get_center().x, n.end.y - 4.0), 40.0, true)
		if rng.randf() < 0.5:
			_banners.append({"x": n.get_center().x, "top": n.position.y - 70.0, "len": rng.randf_range(70.0, 100.0)})

	# light from two gratings high in the wall, slanting down across the floor
	for gx in [vp.x * 0.27, vp.x * 0.73]:
		var lean := 160.0 if gx < vp.x * 0.5 else -160.0
		_shafts.append([Vector2(gx - 30.0, 46.0), Vector2(gx + 30.0, 46.0),
			Vector2(gx - 120.0 + lean, foot + 260.0), Vector2(gx + 120.0 + lean, foot + 260.0)])

	# chequered floor, clipped to the octagon
	var s := 56.0
	var i := 0
	var ty := arena.position.y
	while ty < arena.end.y:
		var tx := arena.position.x
		var j := 0
		while tx < arena.end.x:
			var a := 0.12 if (i + j) % 2 == 0 else 0.05
			for piece in Geometry2D.intersect_polygons(box(Vector2(tx + s * 0.5, ty + s * 0.5), Vector2(s - 3, s - 3)), poly):
				_tiles.append({"pts": piece, "a": a})
			tx += s
			j += 1
		ty += s
		i += 1

	# treasure everywhere off the floor
	for q in scatter(rng, foot - 6.0, 1400, 14.0, 42.0):
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.36:
			_heap(rng, p, r, false)
		elif roll < 0.52:
			_ground.append({"kind": "chest", "p": p, "w": r * 1.7, "y": p.y, "open": rng.randf() < 0.35})
		elif roll < 0.64:
			_ground.append({"kind": "goblet", "p": p, "h": r * 1.4, "y": p.y})
		elif roll < 0.74:
			_ground.append({"kind": "urn", "p": p, "r": r * 0.75, "y": p.y})
		elif roll < 0.8:
			_ground.append({"kind": "crown", "p": p, "w": r * 1.1, "y": p.y})
		elif roll < 0.86:
			_ground.append({"kind": "sword", "p": p, "h": r * 2.4, "lean": rng.randf_range(-0.4, 0.4), "y": p.y})
		else:
			for k in rng.randi_range(3, 6):
				_ground.append({"kind": "gem", "p": p + Vector2(rng.randf_range(-r, r), rng.randf_range(-r * 0.4, r * 0.4)),
					"s": rng.randf_range(5.0, 10.0), "y": p.y})
	_ground.sort_custom(func(a, b): return a.y < b.y)


## A coin mound: a low dome with coins piled on it, and a few glints.
func _heap(rng: RandomNumberGenerator, base: Vector2, r: float, niche: bool) -> void:
	var coins := PackedVector2Array()
	for k in int(r * 1.1):
		var a := rng.randf_range(PI, TAU)
		var d := sqrt(rng.randf()) * r
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
	# the wall falls into shadow towards the ceiling
	P.vband(self, Rect2(0, 0, vp.x, foot * 0.55), 0.7, 0.0, Game.DEEP_MOSS)
	_frieze()

	# braziers throw warm pools of light up the wall
	for b in _braziers:
		P.glow(self, b, 120.0, 0.16)

	# vault door: a glow behind, toothed ring, bolts, wheel spokes, keyhole hub
	P.glow(self, _door, 200.0, 0.14)
	draw_circle(_door, 124, Game.DEEP_MOSS)
	draw_circle(_door, 118, Color(c, 0.38))
	for k in 36:
		var d := Vector2(1, 0).rotated(TAU * k / 36.0)
		draw_line(_door + d * 112, _door + d * 120, Game.DEEP_MOSS, 3.0)
	draw_circle(_door, 104, Color(c, 0.26))
	draw_arc(_door, 104, 0, TAU, 64, Color(c, 0.5), 3.0)
	for k in 12:
		var d := Vector2(1, 0).rotated(TAU * k / 12.0)
		draw_circle(_door + d * 92, 5.5, Color(c, 0.62))
		draw_circle(_door + d * 92, 2.0, Game.DEEP_MOSS)
	draw_circle(_door, 78, Color(c, 0.18))
	for k in 6:
		var d := Vector2(1, 0).rotated(TAU * k / 6.0 + 0.3)
		draw_line(_door + d * 30, _door + d * 74, Color(c, 0.52), 7.0)
		draw_circle(_door + d * 74, 7.0, Color(c, 0.6))
	draw_circle(_door, 34, Color(c, 0.56))
	draw_arc(_door, 34, 0, TAU, 32, Game.DEEP_MOSS, 2.0)
	# keyhole
	draw_circle(_door + Vector2(0, -7), 9, Game.DEEP_MOSS)
	draw_colored_polygon(PackedVector2Array([_door + Vector2(-5, -4), _door + Vector2(5, -4),
		_door + Vector2(8, 18), _door + Vector2(-8, 18)]), Game.DEEP_MOSS)
	# two giant keys stand guard either side of the door
	for side in [-1.0, 1.0]:
		_statue_key(_door + Vector2(side * 190.0, 110.0), side)

	for p in _pillars:
		draw_rect(p, Game.DEEP_MOSS)
		draw_rect(p, Color(c, 0.3))
		draw_rect(Rect2(p.position, Vector2(7, p.size.y)), Color(c, 0.44))
		draw_rect(Rect2(p.position - Vector2(6, 4), Vector2(p.size.x + 12, 12)), Color(c, 0.46))
		draw_rect(Rect2(Vector2(p.position.x - 6, p.end.y - 16), Vector2(p.size.x + 12, 16)), Color(c, 0.4))
		# a keyhole carved into each pillar
		var kh := Vector2(p.get_center().x, p.position.y + 60.0)
		draw_circle(kh, 4, Game.DEEP_MOSS)
		draw_colored_polygon(PackedVector2Array([kh + Vector2(-2, 0), kh + Vector2(2, 0), kh + Vector2(4, 11), kh + Vector2(-4, 11)]), Game.DEEP_MOSS)
	for n in _niches:
		draw_rect(n, Game.DEEP_MOSS)
		draw_circle(Vector2(n.get_center().x, n.position.y), n.size.x * 0.5, Game.DEEP_MOSS)
		P.gradient(self, PackedVector2Array([n.position, Vector2(n.end.x, n.position.y), n.end, Vector2(n.position.x, n.end.y)]),
			n.end, n.position, 0.16, 0.0)
		draw_arc(Vector2(n.get_center().x, n.position.y), n.size.x * 0.5 + 4, PI, TAU, 24, Color(c, 0.46), 6.0)
		draw_arc(Vector2(n.get_center().x, n.position.y), n.size.x * 0.5 + 12, PI, TAU, 24, Color(c, 0.22), 3.0)
		draw_line(n.position - Vector2(4, 0), Vector2(n.position.x - 4, n.end.y), Color(c, 0.46), 6.0)
		draw_line(Vector2(n.end.x + 4, n.position.y), Vector2(n.end.x + 4, n.end.y), Color(c, 0.46), 6.0)
		# keystone
		var ks := Vector2(n.get_center().x, n.position.y - n.size.x * 0.5 - 4.0)
		draw_colored_polygon(PackedVector2Array([ks + Vector2(-9, -10), ks + Vector2(9, -10), ks + Vector2(6, 8), ks + Vector2(-6, 8)]), Color(c, 0.5))
	for g in _ground:
		if g.kind == "heap" and g.y < 0.0:
			_draw_piece(g)
	for bn in _banners:
		_banner(bn)
	for b in _braziers:
		_brazier(b)
	draw_rect(Rect2(0, foot - 12.0, vp.x, 12.0), Color(c, 0.4))
	draw_line(Vector2(0, foot - 12.0), Vector2(vp.x, foot - 12.0), Color(c, 0.55), 2.0)

	draw_rim(20.0, 0.4, 0.28)
	for t_ in _tiles:
		draw_colored_polygon(t_.pts, Color(c, t_.a))
	# a gilt inlay: an inner octagon line, and a keyhole set into the centre
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(centre + (p - centre) * 0.55)
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(c, 0.24), 3.0)
	var inner2 := PackedVector2Array()
	for p in poly:
		inner2.append(centre + (p - centre) * 0.53)
	draw_polyline(inner2 + PackedVector2Array([inner2[0]]), Color(c, 0.12), 2.0)
	draw_arc(centre + Vector2(0, -16), 34, 0, TAU, 40, Color(c, 0.16), 3.0)
	draw_polyline(PackedVector2Array([centre + Vector2(-14, 8), centre + Vector2(-26, 62), centre + Vector2(26, 62), centre + Vector2(14, 8)]),
		Color(c, 0.16), 3.0)
	# the light from the gratings lands on the floor and the treasure
	for s in _shafts:
		P.shaft(self, s[0], s[1], s[2], s[3], 0.13)

	for g in _ground:
		if not (g.kind == "heap" and g.y < 0.0):
			_draw_piece(g)
	P.vignette(self, vp, 150.0, 0.55)


## A band of carved keys along the top of the wall, between two mouldings.
func _frieze() -> void:
	var c := Game.SAPPHIRE_CORE
	var y := 14.0
	draw_rect(Rect2(0, y - 10.0, vp.x, 36.0), Game.DEEP_MOSS)
	draw_rect(Rect2(0, y - 10.0, vp.x, 36.0), Color(c, 0.14))
	draw_line(Vector2(0, y - 10.0), Vector2(vp.x, y - 10.0), Color(c, 0.4), 3.0)
	draw_line(Vector2(0, y + 26.0), Vector2(vp.x, y + 26.0), Color(c, 0.4), 3.0)
	var x := 30.0
	var k := 0
	while x < vp.x:
		var flip := 1.0 if k % 2 == 0 else -1.0
		var bow := Vector2(x - 14.0 * flip, y + 8.0)
		draw_arc(bow, 6.0, 0, TAU, 12, Color(c, 0.34), 2.0)
		draw_line(bow + Vector2(6.0 * flip, 0), bow + Vector2(30.0 * flip, 0), Color(c, 0.34), 2.0)
		draw_line(bow + Vector2(24.0 * flip, 0), bow + Vector2(24.0 * flip, 6), Color(c, 0.34), 2.0)
		draw_line(bow + Vector2(29.0 * flip, 0), bow + Vector2(29.0 * flip, 5), Color(c, 0.34), 2.0)
		x += 56.0
		k += 1


## A giant key standing on its bit, bow up, as tall as the door.
func _statue_key(foot_p: Vector2, side: float) -> void:
	var c := Game.SAPPHIRE_CORE
	var top := foot_p + Vector2(0, -220.0)
	# plinth
	draw_rect(Rect2(foot_p + Vector2(-30, -16), Vector2(60, 16)), Color(c, 0.42))
	draw_rect(Rect2(foot_p + Vector2(-24, -26), Vector2(48, 10)), Color(c, 0.34))
	# shaft with a lit edge
	draw_rect(Rect2(top + Vector2(-7, 40), Vector2(14, 160)), Color(c, 0.36))
	draw_rect(Rect2(top + Vector2(-7 if side < 0 else 3, 40), Vector2(4, 160)), Color(c, 0.5))
	# bit, the teeth facing the door
	var bit := foot_p + Vector2(0, -70)
	for k in 3:
		draw_rect(Rect2(bit + Vector2(-side * 7.0 - (24.0 if side > 0 else 0.0), k * 14.0 - 6.0), Vector2(24.0 - k * 6.0, 9)), Color(c, 0.42))
	# bow: a ring with a quatrefoil cut-out
	draw_circle(top + Vector2(0, 20), 34, Color(c, 0.4))
	draw_arc(top + Vector2(0, 20), 34, 0, TAU, 32, Color(c, 0.55), 3.0)
	for d in [Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)]:
		draw_circle(top + Vector2(0, 20) + d, 8, Game.DEEP_MOSS)
	draw_line(top + Vector2(0, 54), top + Vector2(0, 62), Game.DEEP_MOSS, 3.0)


func _banner(bn: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	var x: float = bn.x
	var top: float = bn.top
	var l: float = bn.len
	draw_line(Vector2(x - 26, top), Vector2(x + 26, top), Color(c, 0.5), 4.0)
	var cloth := PackedVector2Array([Vector2(x - 20, top), Vector2(x + 20, top), Vector2(x + 20, top + l),
		Vector2(x, top + l - 14), Vector2(x - 20, top + l)])
	P.gradient(self, cloth, Vector2(x, top), Vector2(x, top + l), 0.4, 0.26)
	draw_line(Vector2(x - 20, top + 6), Vector2(x - 20, top + l), Color(c, 0.5), 2.0)
	# a key on the cloth
	draw_arc(Vector2(x, top + 22), 6, 0, TAU, 12, Game.DEEP_MOSS, 2.0)
	draw_line(Vector2(x, top + 28), Vector2(x, top + l - 30), Game.DEEP_MOSS, 2.0)
	draw_line(Vector2(x, top + l - 34), Vector2(x + 7, top + l - 34), Game.DEEP_MOSS, 2.0)


func _brazier(b: Vector2) -> void:
	var c := Game.SAPPHIRE_CORE
	draw_line(b + Vector2(0, 4), b + Vector2(0, 40), Color(c, 0.5), 4.0)
	draw_line(b + Vector2(-12, 40), b + Vector2(12, 40), Color(c, 0.5), 4.0)
	draw_colored_polygon(PackedVector2Array([b + Vector2(-18, -4), b + Vector2(18, -4), b + Vector2(10, 8), b + Vector2(-10, 8)]), Color(c, 0.6))
	draw_line(b + Vector2(-18, -4), b + Vector2(18, -4), Color(c, 0.75), 2.0)


func _draw_piece(g: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	match g.kind:
		"heap":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_colored_polygon(Transform2D(0.0, p + Vector2(0, 2)) * Game.ellipse(r * 1.1, r * 0.22), Color(Game.DEEP_MOSS, 0.6))
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(p + Vector2(cos(a) * r, sin(a) * r * 0.62))
			P.gradient(self, dome, p - Vector2(0, r * 0.62), p, 0.42, 0.24)
			for cp in g.coins:
				draw_colored_polygon(Transform2D(0.0, cp) * Game.ellipse(4.5, 2.2, 8), Color(c, 0.6))
				draw_line(cp - Vector2(4, 0), cp + Vector2(4, 0), Game.DEEP_MOSS, 1.0)
		"chest":
			var p: Vector2 = g.p
			var w: float = g.w
			draw_colored_polygon(Transform2D(0.0, p + Vector2(0, 2)) * Game.ellipse(w * 0.62, w * 0.12), Color(Game.DEEP_MOSS, 0.6))
			var body := Rect2(p.x - w * 0.5, p.y - w * 0.55, w, w * 0.55)
			P.gradient(self, PackedVector2Array([body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]),
				body.position, body.end, 0.42, 0.26)
			var lid_h := w * 0.28
			if g.open:
				# lid thrown back, coins brimming over the lip
				draw_colored_polygon(PackedVector2Array([body.position, Vector2(body.end.x, body.position.y),
					Vector2(body.end.x - 6, body.position.y - lid_h * 1.6), Vector2(body.position.x + 6, body.position.y - lid_h * 1.6)]), Color(c, 0.3))
				for k in 7:
					var cp := Vector2(lerpf(body.position.x + 6, body.end.x - 6, k / 6.0), body.position.y - 3.0 - 4.0 * sin(PI * k / 6.0))
					draw_colored_polygon(Transform2D(0.0, cp) * Game.ellipse(4.5, 2.2, 8), Color(c, 0.66))
			else:
				draw_colored_polygon(PackedVector2Array([body.position, Vector2(body.end.x, body.position.y),
					Vector2(body.end.x - 4, body.position.y - lid_h), Vector2(body.position.x + 4, body.position.y - lid_h)]), Color(c, 0.5))
			draw_line(Vector2(body.position.x + w * 0.2, body.position.y - (0.0 if g.open else lid_h)), Vector2(body.position.x + w * 0.2, body.end.y), Game.DEEP_MOSS, 3.0)
			draw_line(Vector2(body.end.x - w * 0.2, body.position.y - (0.0 if g.open else lid_h)), Vector2(body.end.x - w * 0.2, body.end.y), Game.DEEP_MOSS, 3.0)
			draw_rect(Rect2(p.x - 5, body.position.y - 4, 10, 12), Color(c, 0.72))
			draw_circle(Vector2(p.x, body.position.y + 2), 1.8, Game.DEEP_MOSS)
		"goblet":
			var p: Vector2 = g.p
			var h: float = g.h
			draw_colored_polygon(Transform2D(0.0, p) * Game.ellipse(h * 0.35, h * 0.1), Color(c, 0.42))
			draw_line(p, p - Vector2(0, h * 0.55), Color(c, 0.46), 4.0)
			draw_circle(p - Vector2(0, h * 0.4), 3.5, Color(c, 0.5))
			draw_colored_polygon(PackedVector2Array([p - Vector2(h * 0.4, h), p - Vector2(-h * 0.4, h), p - Vector2(0, h * 0.5)]), Color(c, 0.5))
			draw_line(p - Vector2(h * 0.4, h), p - Vector2(-h * 0.4, h), Color(c, 0.72), 3.0)
		"urn":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_colored_polygon(Transform2D(0.0, p + Vector2(0, 1)) * Game.ellipse(r * 1.1, r * 0.25), Color(Game.DEEP_MOSS, 0.6))
			draw_circle(p - Vector2(0, r), r, Color(c, 0.32))
			draw_arc(p - Vector2(0, r), r - 3, PI * 0.7, PI * 1.25, 10, Color(c, 0.55), 3.0)
			draw_rect(Rect2(p.x - r * 0.4, p.y - r * 2.5, r * 0.8, r * 0.7), Color(c, 0.4))
			draw_line(p - Vector2(r * 0.5, r * 2.5), p - Vector2(-r * 0.5, r * 2.5), Color(c, 0.55), 3.0)
			draw_line(p - Vector2(r * 0.8, r * 1.1), p - Vector2(-r * 0.8, r * 1.1), Game.DEEP_MOSS, 2.0)
		"crown":
			var p: Vector2 = g.p
			var w: float = g.w
			draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(w * 0.5, 0), p + Vector2(w * 0.5, -w * 0.55),
				p + Vector2(w * 0.25, -w * 0.3), p + Vector2(0, -w * 0.62), p + Vector2(-w * 0.25, -w * 0.3), p + Vector2(-w * 0.5, -w * 0.55)]), Color(c, 0.55))
			draw_line(p + Vector2(-w * 0.5, -3), p + Vector2(w * 0.5, -3), Game.DEEP_MOSS, 2.0)
			for x in [-0.5, 0.0, 0.5]:
				draw_circle(p + Vector2(w * x, -w * (0.62 if x == 0.0 else 0.55)), 3.0, Color(c, 0.75))
		"sword":
			var p: Vector2 = g.p
			var h: float = g.h
			var d := Vector2(sin(g.lean), -cos(g.lean))
			draw_line(p, p + d * h, Color(c, 0.5), 4.0)
			draw_line(p + d * h * 0.72 + d.orthogonal() * 12.0, p + d * h * 0.72 - d.orthogonal() * 12.0, Color(c, 0.6), 4.0)
			draw_circle(p + d * (h + 4.0), 4.0, Color(c, 0.6))
		"gem":
			var p: Vector2 = g.p
			var s: float = g.s
			draw_colored_polygon(PackedVector2Array([p - Vector2(0, s * 1.4), p + Vector2(s * 0.7, -s * 0.5), p, p - Vector2(s * 0.7, s * 0.5)]), Color(c, 0.64))
			draw_colored_polygon(PackedVector2Array([p - Vector2(0, s * 1.4), p, p - Vector2(s * 0.7, s * 0.5)]), Color(c, 0.4))


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	for i in _braziers.size():
		var b: Vector2 = _braziers[i]
		P.flame(l, b + Vector2(0, -6), 20.0, t, float(i) * 3.7)
		P.flame(l, b + Vector2(-8, -4), 11.0, t, float(i) * 3.7 + 1.3, 0.6)
		P.flame(l, b + Vector2(8, -4), 12.0, t, float(i) * 3.7 + 2.1, 0.6)
		# embers rising off the bowl
		for k in 3:
			var u := fposmod(t * 0.6 + k * 0.33 + i * 0.17, 1.0)
			var e := b + Vector2(sin(t * 2.0 + k * 2.0 + i) * 10.0, -20.0 - u * 90.0)
			l.draw_circle(e, 2.0, Color(c, 0.7 * (1.0 - u)))
	for g in _glints:
		var a := maxf(0.0, sin(t * 1.7 * float(g.s) + float(g.ph)))
		if a < 0.2:
			continue
		var p: Vector2 = g.p
		var r := 3.0 + 6.0 * a
		l.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(c, 0.85 * a), 2.0)
		l.draw_line(p - Vector2(0, r), p + Vector2(0, r), Color(c, 0.85 * a), 2.0)
	# dust: brighter where it drifts through a shaft of light
	for m in motes:
		var p: Vector2 = m.p + Vector2(sin(t * 0.6 + float(m.ph)) * 6.0, 0)
		var lit := false
		for s in _shafts:
			if Geometry2D.is_point_in_polygon(p, PackedVector2Array([s[0], s[1], s[3], s[2]])):
				lit = true
				break
		l.draw_circle(p, 2.4 if lit else 1.8, Color(c, 0.6 if lit else 0.28))
