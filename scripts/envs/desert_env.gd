extends "res://scripts/envs/env_base.gd"
## Cell IV, the Hourglass's desert: a low sun over three bands of distant
## dunes with ruined columns on the horizon, a round floor of rippled sand,
## and the ground around it strewn with rocks, bleached bones, cacti and
## half-buried columns. Wind blows streaks of sand across the screen.
## The sky brightens towards the horizon, the sun throws long rays, pyramids
## and an obelisk stand on the far dunes, and a giant broken hourglass lies
## half sunk in the near ones. Each dune has a lit crest and a shaded lee.
## Vultures wheel overhead, sand smokes off the crests, and a vignette closes
## the edges in.

const P := preload("res://scripts/paint.gd")

var _dunes: Array = []        # {pts, a}
var _ruins: Array = []        # {pts, a}
var _ripples: Array = []      # PackedVector2Array
var _floor_ripples: Array = []
var _ground: Array = []
var _sun := Vector2.ZERO
var _streaks: Array = []      # {p, v, len}
var _crests: Array = []       # [PackedVector2Array crest line, a] per dune band
var _birds: Array = []        # {c, r, ph, s}
var _wisps: Array = []        # {p, ph}: sand blowing off the crests
var _wreck := Vector2.ZERO    # the giant hourglass half sunk in the dunes


func _init() -> void:
	seed_value = 41
	mote_count = 26
	mote_drift = Vector2(40, -3)


func _build(rng: RandomNumberGenerator) -> void:
	var foot := arena.position.y
	_sun = Vector2(vp.x * 0.74, 96.0)
	# three bands of dunes, back to front, down to the floor's top edge
	for layer in 3:
		var base := 110.0 + layer * 50.0
		var amp := 16.0 + layer * 8.0
		var freq := rng.randf_range(0.006, 0.01)
		var ph := rng.randf() * TAU
		var pts := PackedVector2Array([Vector2(0, foot)])
		var x := 0.0
		while x <= vp.x + 20.0:
			pts.append(Vector2(x, base + sin(x * freq + ph) * amp + sin(x * freq * 2.7 + ph) * amp * 0.4))
			x += 20.0
		pts.append(Vector2(vp.x, foot))
		_dunes.append({"pts": pts, "a": 0.12 + layer * 0.07})
		_crests.append([pts.slice(1, pts.size() - 1), 0.12 + layer * 0.07])
		for k in 3:
			_wisps.append({"p": pts[rng.randi_range(2, pts.size() - 3)], "ph": rng.randf() * TAU})
		if layer == 0:
			for k in 4:
				var rx := rng.randf_range(80.0, vp.x - 80.0)
				var ry := base + sin(rx * freq + ph) * amp
				var w := rng.randf_range(16.0, 26.0)
				var h := rng.randf_range(40.0, 80.0)
				_ruins.append({"pts": PackedVector2Array([Vector2(rx, ry + 6), Vector2(rx + w, ry + 6), Vector2(rx + w, ry - h),
					Vector2(rx + w * 0.6, ry - h - 10), Vector2(rx, ry - h + 6)]), "a": 0.22})

	# sand ripples: long wavy lines, split into the floor's and the rest
	var y := foot + 10.0
	while y < vp.y + 10.0:
		var line := PackedVector2Array()
		var ph := rng.randf() * TAU
		var x := -10.0
		while x <= vp.x + 10.0:
			line.append(Vector2(x, y + sin(x * 0.02 + ph) * 6.0))
			x += 14.0
		var cur := PackedVector2Array()
		var inside := on_floor(line[0])
		for p in line:
			if on_floor(p) != inside:
				if cur.size() > 1:
					(_floor_ripples if inside else _ripples).append(cur)
				cur = PackedVector2Array()
				inside = not inside
			cur.append(p)
		if cur.size() > 1:
			(_floor_ripples if inside else _ripples).append(cur)
		y += rng.randf_range(22.0, 34.0)

	for q in scatter(rng, foot - 4.0, 1000, 12.0, 34.0, 30.0):
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.45:
			var rk := rock(rng, p, r, 0.24, 0.34)
			rk["y"] = p.y
			_ground.append(rk)
		elif roll < 0.62:
			_ground.append({"kind": "skull", "p": p, "r": r * 0.55, "y": p.y})
		elif roll < 0.78:
			_ground.append({"kind": "cactus", "p": p, "h": r * 2.6, "arm": rng.randf() < 0.6, "y": p.y})
		elif roll < 0.9:
			_ground.append({"kind": "column", "p": p, "w": r * 0.9, "h": r * rng.randf_range(1.2, 2.6), "y": p.y})
		else:
			_ground.append({"kind": "ribs", "p": p, "r": r, "y": p.y})
	_ground.sort_custom(func(a, b): return a.y < b.y)

	_wreck = Vector2(vp.x * 0.17, foot - 84.0)
	for i in 4:
		_birds.append({"c": Vector2(rng.randf_range(vp.x * 0.3, vp.x * 0.9), rng.randf_range(40.0, 120.0)),
			"r": rng.randf_range(30.0, 70.0), "ph": rng.randf() * TAU, "s": rng.randf_range(0.25, 0.45)})
	for i in 26:
		_streaks.append({"p": Vector2(rng.randf() * vp.x, rng.randf_range(foot, vp.y)), "v": rng.randf_range(220.0, 420.0),
			"len": rng.randf_range(16.0, 40.0)})


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	var foot := arena.position.y
	# sky: dark overhead, bright at the horizon
	P.vband(self, Rect2(0, 0, vp.x, foot), 0.02, 0.2)
	# sun: long rays, a halo, the disc
	for k in 16:
		var ang := TAU * k / 16.0 + 0.1
		var d := Vector2(cos(ang), sin(ang))
		var len := 260.0 if k % 2 == 0 else 170.0
		P.gradient(self, PackedVector2Array([_sun + d.orthogonal() * 10.0, _sun - d.orthogonal() * 10.0, _sun + d * len]),
			_sun, _sun + d * len, 0.16, 0.0)
	P.glow(self, _sun, 200.0, 0.22)
	draw_circle(_sun, 52.0, Color(c, 0.4))
	draw_arc(_sun, 52.0, 0, TAU, 40, Color(c, 0.55), 2.0)
	for i in _dunes.size():
		if i == 0:
			_pyramids()
		if i == 1:
			for r in _ruins:
				draw_colored_polygon(r.pts, Color(c, r.a))
		if i == 2:
			_hourglass_wreck()
		var a := float(_dunes[i].a)
		draw_colored_polygon(_dunes[i].pts, Color(c, a))
		# the lee of each dune falls into shadow below its crest
		var crest: PackedVector2Array = _crests[i][0]
		for k in crest.size() - 1:
			if crest[k + 1].y > crest[k].y:     # downhill to the right: the shaded face
				P.gradient(self, PackedVector2Array([crest[k], crest[k + 1], crest[k + 1] + Vector2(0, 40), crest[k] + Vector2(0, 40)]),
					Vector2(0, crest[k].y), Vector2(0, crest[k].y + 40.0), 0.3, 0.0, Game.DEEP_MOSS)
		draw_polyline(crest, Color(c, a + 0.16), 2.0)

	draw_rim(14.0, 0.3, 0.22)
	for r in _floor_ripples:
		draw_polyline(r, Color(c, 0.16), 2.0)
	for r in _ripples:
		draw_polyline(r, Color(c, 0.28), 2.0)
	for g in _ground:
		_draw_piece(g)
	P.vignette(self, vp, 150.0, 0.5)


## Pyramids and an obelisk on the farthest dunes, lit on the sun's side.
func _pyramids() -> void:
	var c := Game.SAPPHIRE_CORE
	for py in [[vp.x * 0.42, 70.0, 96.0], [vp.x * 0.5, 50.0, 112.0], [vp.x * 0.57, 40.0, 104.0]]:
		var x: float = py[0]
		var h: float = py[1]
		var base_y: float = py[2] + 20.0
		var apex := Vector2(x, base_y - h)
		draw_colored_polygon(PackedVector2Array([Vector2(x - h * 1.3, base_y), Vector2(x, base_y), apex]), Color(c, 0.13))
		draw_colored_polygon(PackedVector2Array([Vector2(x, base_y), Vector2(x + h * 1.3, base_y), apex]), Color(c, 0.2))
	var ob := Vector2(vp.x * 0.66, 128.0)
	draw_colored_polygon(PackedVector2Array([ob + Vector2(-7, 0), ob + Vector2(7, 0), ob + Vector2(5, -80), ob + Vector2(0, -92), ob + Vector2(-5, -80)]), Color(c, 0.2))


## A giant hourglass, toppled and half sunk in the near dune: one bulb
## cracked open, sand spilling from it, its frame posts sticking out.
func _hourglass_wreck() -> void:
	var c := Game.SAPPHIRE_CORE
	var w := _wreck
	var tf := Transform2D(-0.3, Vector2(0.72, 0.72), 0.0, w)
	# the frame: two end plates and the posts between them
	var plate_a := tf * PackedVector2Array([Vector2(-150, -70), Vector2(-136, -70), Vector2(-136, 70), Vector2(-150, 70)])
	var plate_b := tf * PackedVector2Array([Vector2(136, -70), Vector2(150, -70), Vector2(150, 70), Vector2(136, 70)])
	draw_colored_polygon(plate_a, Color(c, 0.4))
	draw_colored_polygon(plate_b, Color(c, 0.34))
	for y in [-60.0, 60.0]:
		draw_line(tf * Vector2(-136, y), tf * Vector2(136, y), Color(c, 0.38), 6.0)
	# the glass: two bulbs pinched at the neck
	var glass := PackedVector2Array()
	for k in 25:
		var x := lerpf(-130.0, 130.0, k / 24.0)
		glass.append(Vector2(x, -(10.0 + 44.0 * pow(absf(x) / 130.0, 0.7))))
	for k in 25:
		var x := lerpf(130.0, -130.0, k / 24.0)
		glass.append(Vector2(x, 10.0 + 44.0 * pow(absf(x) / 130.0, 0.7)))
	glass = tf * glass
	draw_colored_polygon(glass, Color(c, 0.16))
	draw_polyline(glass + PackedVector2Array([glass[0]]), Color(c, 0.46), 2.0)
	# sand inside the lower bulb, and a crack with sand pouring out
	draw_colored_polygon(tf * PackedVector2Array([Vector2(20, 30), Vector2(128, 30), Vector2(128, 52), Vector2(40, 40)]), Color(c, 0.38))
	draw_polyline(tf * PackedVector2Array([Vector2(90, -40), Vector2(98, -24), Vector2(88, -12), Vector2(100, 0)]), Game.DEEP_MOSS, 2.0)
	var spill := tf * Vector2(118, 50)
	draw_colored_polygon(PackedVector2Array([spill, spill + Vector2(70, 34), spill + Vector2(-30, 34)]), Color(c, 0.3))


func _draw_piece(g: Dictionary) -> void:
	var c := Game.SAPPHIRE_CORE
	match g.kind:
		"rock":
			draw_rock(g)
		"skull":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_circle(p - Vector2(0, r), r, Color(c, 0.55))
			draw_rect(Rect2(p.x - r * 0.55, p.y - r * 0.3, r * 1.1, r * 0.6), Color(c, 0.55))
			draw_circle(p + Vector2(-r * 0.38, -r * 1.05), r * 0.26, Game.DEEP_MOSS)
			draw_circle(p + Vector2(r * 0.38, -r * 1.05), r * 0.26, Game.DEEP_MOSS)
			for k in 3:
				draw_line(p + Vector2(-r * 0.3 + k * r * 0.3, -r * 0.25), p + Vector2(-r * 0.3 + k * r * 0.3, r * 0.25), Game.DEEP_MOSS, 2.0)
		"cactus":
			var p: Vector2 = g.p
			var h: float = g.h
			draw_line(p, p - Vector2(0, h), Color(c, 0.42), 12.0)
			draw_circle(p - Vector2(0, h), 6, Color(c, 0.42))
			if g.arm:
				draw_line(p - Vector2(0, h * 0.5), p - Vector2(-h * 0.3, h * 0.5), Color(c, 0.42), 9.0)
				draw_line(p - Vector2(-h * 0.3, h * 0.5), p - Vector2(-h * 0.3, h * 0.85), Color(c, 0.42), 9.0)
		"column":
			var p: Vector2 = g.p
			var w: float = g.w
			var h: float = g.h
			draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(w, 0), p + Vector2(w, -h),
				p + Vector2(w * 0.2, -h - 10), p + Vector2(-w, -h + 4)]), Color(c, 0.34))
			draw_rect(Rect2(p.x - w, p.y - h, w * 0.4, h), Color(c, 0.44))
			draw_colored_polygon(Transform2D(0.0, p) * Game.ellipse(w * 1.6, 6), Color(c, 0.28))
		"ribs":
			var p: Vector2 = g.p
			var r: float = g.r
			draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(c, 0.5), 3.0)
			for k in 4:
				var x := -r * 0.7 + k * r * 0.46
				draw_arc(p + Vector2(x, 0), r * 0.4, PI, TAU, 10, Color(c, 0.5), 3.0)


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	l.draw_arc(_sun, 66.0 + sin(t * 1.4) * 5.0, 0, TAU, 40, Color(c, 0.22), 3.0)
	# vultures wheel over the dunes
	for b in _birds:
		var a := t * float(b.s) + float(b.ph)
		var p: Vector2 = b.c + Vector2(cos(a), sin(a) * 0.4) * float(b.r)
		var flap := sin(t * 3.0 + float(b.ph)) * 3.0
		l.draw_polyline(PackedVector2Array([p + Vector2(-12, -2 + flap), p + Vector2(-5, 0), p, p + Vector2(5, 0), p + Vector2(12, -2 + flap)]),
			Color(c, 0.45), 2.0)
	# sand smoking off the dune crests
	for w in _wisps:
		var u := fposmod(t * 0.35 + float(w.ph), 1.0)
		var p: Vector2 = w.p + Vector2(u * 90.0, -u * 14.0)
		l.draw_line(p, p + Vector2(18.0 + u * 20.0, -2.0), Color(c, 0.35 * (1.0 - u)), 2.0)
	for s in _streaks:
		var x := fposmod(float(s.p.x) + t * float(s.v), vp.x + 80.0) - 40.0
		var p := Vector2(x, float(s.p.y) + sin(t * 2.0 + float(s.p.x)) * 6.0)
		l.draw_line(p, p - Vector2(float(s.len), 0), Color(c, 0.4), 2.0)
	draw_motes(l, Color(c, 0.35), 2.0, 3.0)
