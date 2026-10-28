extends "res://scripts/envs/env_base.gd"
## Cell IV, the Hourglass's desert: a low sun over three bands of distant
## dunes with ruined columns on the horizon, a round floor of rippled sand,
## and the ground around it strewn with rocks, bleached bones, cacti and
## half-buried columns. Wind blows streaks of sand across the screen.

var _dunes: Array = []        # {pts, a}
var _ruins: Array = []        # {pts, a}
var _ripples: Array = []      # PackedVector2Array
var _floor_ripples: Array = []
var _ground: Array = []
var _sun := Vector2.ZERO
var _streaks: Array = []      # {p, v, len}


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

	for i in 26:
		_streaks.append({"p": Vector2(rng.randf() * vp.x, rng.randf_range(foot, vp.y)), "v": rng.randf_range(220.0, 420.0),
			"len": rng.randf_range(16.0, 40.0)})


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	var foot := arena.position.y
	draw_rect(Rect2(0, 0, vp.x, foot), Color(c, 0.06))
	for k in 4:
		draw_circle(_sun, 140.0 - k * 26.0, Color(c, 0.05 + k * 0.03))
	draw_circle(_sun, 52.0, Color(c, 0.36))
	for i in _dunes.size():
		if i == 1:
			for r in _ruins:
				draw_colored_polygon(r.pts, Color(c, r.a))
		draw_colored_polygon(_dunes[i].pts, Color(c, _dunes[i].a))
		draw_polyline(_dunes[i].pts.slice(1, _dunes[i].pts.size() - 1), Color(c, float(_dunes[i].a) + 0.12), 2.0)

	draw_rim(14.0, 0.3, 0.22)
	for r in _floor_ripples:
		draw_polyline(r, Color(c, 0.16), 2.0)
	for r in _ripples:
		draw_polyline(r, Color(c, 0.28), 2.0)
	for g in _ground:
		_draw_piece(g)


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
	for s in _streaks:
		var x := fposmod(float(s.p.x) + t * float(s.v), vp.x + 80.0) - 40.0
		var p := Vector2(x, float(s.p.y) + sin(t * 2.0 + float(s.p.x)) * 6.0)
		l.draw_line(p, p - Vector2(float(s.len), 0), Color(c, 0.4), 2.0)
	draw_motes(l, Color(c, 0.35), 2.0, 3.0)
