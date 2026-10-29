extends "res://scripts/envs/env_base.gd"
## Gate V, the Mirror's dark space: the inside of a mind. Almost nothing is
## lit. A round floor made of faint rings and spokes floats in the void under a
## huge outlined eye whose pupil follows the player. Geometric fragments and
## mirror shards drift and turn around the floor, and stars twinkle.
## Darker than every other room on purpose: the fight should be the only
## bright thing on screen.
## Depth comes from faint nebulae and constellations; neurons branch through
## the dark with pulses running along them; ghosts of the four earlier
## rooms drift past (a key, a blade, a prism, an hourglass), the memories the
## Mirror fights with; thought-ripples spread out from the floor's edge.

const P := preload("res://scripts/paint.gd")

var _stars: Array = []        # {p, a, ph}
var _shapes: Array = []       # {c, r, n, rot, spin, orbit, ph, a}
var _shards: Array = []       # {p, len, ang, v, ph}
var _eye := Vector2.ZERO
var _nebulae: Array = []      # {p, r, a}
var _links: Array = []        # [Vector2, Vector2] constellation lines
var _neurons: Array = []      # PackedVector2Array branches, root first
var _ghosts: Array = []       # {kind, p, ph, s}


func _init() -> void:
	seed_value = 51
	mote_count = 24
	mote_drift = Vector2(0, -6)


func _build(rng: RandomNumberGenerator) -> void:
	_eye = Vector2(vp.x * 0.5, 120.0)
	for i in 110:
		_stars.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y), "a": rng.randf_range(0.2, 0.5), "ph": rng.randf() * TAU})
	# outlined shapes circling the floor at different distances
	for i in 26:
		_shapes.append({"orbit": rng.randf_range(arena.size.x * 0.56, arena.size.x * 0.85), "ang": rng.randf() * TAU,
			"speed": rng.randf_range(0.02, 0.06) * (1.0 if rng.randf() < 0.5 else -1.0),
			"r": rng.randf_range(10.0, 34.0), "n": [3, 4, 4, 6].pick_random(), "spin": rng.randf_range(-0.6, 0.6),
			"ph": rng.randf() * TAU, "a": rng.randf_range(0.3, 0.55)})
	for i in 7:
		_nebulae.append({"p": Vector2(rng.randf() * vp.x, rng.randf_range(0.0, vp.y)), "r": rng.randf_range(160.0, 320.0),
			"a": rng.randf_range(0.05, 0.09)})
	# constellations: chain a few nearby stars
	for i in 6:
		var s0: Vector2 = _stars[rng.randi() % _stars.size()].p
		var cur := s0
		for k in rng.randi_range(2, 4):
			var best := cur
			var bd := INF
			for s in _stars:
				var d: float = cur.distance_to(s.p)
				if d > 30.0 and d < bd and d < 160.0 and s.p != s0:
					bd = d
					best = s.p
			if best == cur:
				break
			_links.append([cur, best])
			cur = best
	# neurons: branching from the screen edges in towards the floor
	for i in 6:
		var root := Vector2(-10.0 if i % 2 == 0 else vp.x + 10.0, rng.randf_range(arena.position.y, vp.y))
		var dir := Vector2(1.0 if i % 2 == 0 else -1.0, rng.randf_range(-0.4, 0.4)).normalized()
		_grow_neuron(rng, root, dir, 4)
	for k in ["key", "blade", "prism", "glass"]:
		_ghosts.append({"kind": k, "p": Vector2(rng.randf() * vp.x, rng.randf_range(arena.position.y, vp.y)),
			"ph": rng.randf() * TAU, "s": rng.randf_range(0.8, 1.2)})
	for i in 10:
		_shards.append({"p": Vector2(rng.randf() * vp.x, rng.randf_range(arena.position.y, vp.y)), "len": rng.randf_range(30.0, 70.0),
			"ang": rng.randf() * TAU, "v": rng.randf_range(8.0, 18.0), "ph": rng.randf() * TAU})


func _grow_neuron(rng: RandomNumberGenerator, from: Vector2, dir: Vector2, depth: int) -> void:
	var line := PackedVector2Array([from])
	var p := from
	for k in rng.randi_range(4, 7):
		dir = dir.rotated(rng.randf_range(-0.5, 0.5))
		p += dir * rng.randf_range(18.0, 34.0)
		if on_floor(p, 20.0):
			break
		line.append(p)
		if depth > 0 and rng.randf() < 0.3:
			_grow_neuron(rng, p, dir.rotated(rng.randf_range(-1.0, 1.0)), depth - 1)
	if line.size() > 1:
		_neurons.append(line)


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
	for n in _nebulae:
		P.glow(self, n.p, n.r, n.a, 0.6)
	for l in _links:
		draw_line(l[0], l[1], Color(c, 0.12), 1.0)
	for n in _neurons:
		draw_polyline(n, Color(c, 0.14), 2.0)
		draw_circle(n[0], 3.0, Color(c, 0.2))
	for s in _stars:
		draw_circle(s.p, 1.6, Color(c, s.a))
	# the eye in the void: an almond outline and an iris ring (pupil is live)
	var almond := PackedVector2Array()
	for k in 33:
		var f := k / 32.0
		var x := lerpf(-260.0, 260.0, f)
		almond.append(_eye + Vector2(x, -sin(PI * f) * 70.0))
	for k in 33:
		var f := k / 32.0
		var x := lerpf(260.0, -260.0, f)
		almond.append(_eye + Vector2(x, sin(PI * f) * 70.0))
	P.glow(self, _eye, 320.0, 0.08, 0.4)
	draw_polyline(almond, Color(c, 0.3), 3.0)
	# lashes fanning off the upper lid
	for k in range(3, 30, 3):
		var f := k / 32.0
		var x := lerpf(-260.0, 260.0, f)
		var lid := _eye + Vector2(x, -sin(PI * f) * 70.0)
		var out := (lid - (_eye + Vector2(0, 60))).normalized()
		draw_line(lid, lid + out * (10.0 + 12.0 * sin(PI * f)), Color(c, 0.24), 2.0)
	# the iris: a ring with striations running in to the pupil
	draw_arc(_eye, 58.0, 0, TAU, 48, Color(c, 0.24), 3.0)
	for k in 36:
		var d := Vector2(1, 0).rotated(TAU * k / 36.0)
		draw_line(_eye + d * 30.0, _eye + d * (52.0 - (k % 3) * 5.0), Color(c, 0.12), 1.5)

	# the floor: rings and spokes, faint enough to read as a scatter of specks
	var h := arena.size * 0.5
	for k in range(1, 6):
		var ring := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			ring.append(centre + Vector2(cos(a), sin(a)) * h * (k / 5.0) * 0.98)
		draw_polyline(ring, Color(c, 0.16 if k < 5 else 0.5), 2.0 if k < 5 else 3.0)
	for i in 16:
		var a := TAU * i / 16.0
		draw_line(centre + Vector2(cos(a), sin(a)) * h * 0.2, centre + Vector2(cos(a), sin(a)) * h * 0.97, Color(c, 0.12), 2.0)
	P.vignette(self, vp, 220.0, 0.7)


func _draw_live(l: Node2D) -> void:
	var c := Game.SAPPHIRE_CORE
	# the pupil watches the player
	var pl := get_tree().get_first_node_in_group("player")
	var look := Vector2.ZERO
	if pl:
		look = (pl.global_position - _eye).normalized() * 26.0
	var pup := _eye + look * Vector2(1.0, 0.5)
	l.draw_colored_polygon(PackedVector2Array([pup + Vector2(0, -26), pup + Vector2(16, 0), pup + Vector2(0, 26), pup + Vector2(-16, 0)]), Color(c, 0.4))

	for s in _stars:
		var tw := sin(t * 1.3 + float(s.ph))
		if tw > 0.85:
			l.draw_circle(s.p, 2.5, Color(c, 0.6))

	# thought-ripples spreading out from the floor's edge
	var h := arena.size * 0.5
	for k in 2:
		var u := fposmod(t * 0.12 + k * 0.5, 1.0)
		var ring := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			ring.append(centre + Vector2(cos(a), sin(a)) * h * (1.0 + u * 0.5))
		l.draw_polyline(ring, Color(c, 0.22 * (1.0 - u)), 2.0)

	# pulses running out along the neurons
	for i in _neurons.size():
		var n: PackedVector2Array = _neurons[i]
		var u := fposmod(t * 0.4 + i * 0.37, 1.6)
		if u < 1.0:
			var f := u * (n.size() - 1)
			var k := int(f)
			var p := n[k].lerp(n[mini(k + 1, n.size() - 1)], f - k)
			l.draw_circle(p, 2.5, Color(c, 0.55))

	# ghosts of the earlier rooms, drifting and turning slowly
	for g in _ghosts:
		var p := Vector2(fposmod(float(g.p.x) + t * 12.0 * float(g.s), vp.x + 200.0) - 100.0, float(g.p.y) + sin(t * 0.5 + float(g.ph)) * 20.0)
		var a := 0.12 + 0.08 * sin(t * 0.7 + float(g.ph))
		_ghost(l, g.kind, Transform2D(sin(t * 0.3 + float(g.ph)) * 0.5, p), Color(c, a))

	for s in _shapes:
		var a := float(s.ang) + t * float(s.speed)
		var p := centre + Vector2(cos(a), sin(a)) * Vector2(float(s.orbit), float(s.orbit) * h.y / h.x)
		p.y += sin(t * 0.9 + float(s.ph)) * 10.0
		var pts := PackedVector2Array()
		var n: int = s.n
		for k in n + 1:
			pts.append(p + Vector2(float(s.r), 0).rotated(TAU * k / n + t * float(s.spin)))
		l.draw_polyline(pts, Color(c, s.a), 2.0)

	# mirror shards: thin slivers with one bright edge, drifting up and turning
	for s in _shards:
		var p := Vector2(float(s.p.x) + sin(t * 0.4 + float(s.ph)) * 20.0, fposmod(float(s.p.y) - t * float(s.v), vp.y))
		var d := Vector2(float(s.len), 0).rotated(float(s.ang) + t * 0.2)
		var n := d.orthogonal().normalized() * 5.0
		l.draw_colored_polygon(PackedVector2Array([p, p + d, p + d + n, p + n]), Color(c, 0.22))
		l.draw_line(p, p + d, Color(c, 0.55), 2.0)
	draw_motes(l, Color(c, 0.3), 1.8, 10.0)


## Outline memories of the four earlier rooms, faint and drifting.
func _ghost(l: Node2D, kind: String, tf: Transform2D, col: Color) -> void:
	match kind:
		"key":
			var bow := PackedVector2Array()
			for k in 17:
				bow.append(Vector2(-40, 0) + Vector2(14, 0).rotated(TAU * k / 16.0))
			l.draw_polyline(tf * bow, col, 2.0)
			l.draw_polyline(tf * PackedVector2Array([Vector2(-26, 0), Vector2(40, 0), Vector2(40, 12), Vector2(32, 12), Vector2(32, 6), Vector2(24, 6), Vector2(24, 0)]), col, 2.0)
		"blade":
			var arc := PackedVector2Array()
			for k in 13:
				arc.append(Vector2(0, -30) + Vector2(0, 60).rotated(lerpf(-0.6, 0.6, k / 12.0)))
			l.draw_polyline(tf * arc, col, 3.0)
			l.draw_line(tf * Vector2(0, -90), tf * Vector2(0, 30), col, 1.5)
		"prism":
			l.draw_polyline(tf * PackedVector2Array([Vector2(0, -40), Vector2(36, 24), Vector2(-36, 24), Vector2(0, -40)]), col, 2.0)
			l.draw_line(tf * Vector2(-80, 0), tf * Vector2(-18, 0), col, 1.5)
			for k in 3:
				l.draw_line(tf * Vector2(18, 0), tf * Vector2(80, -20 + k * 20), col, 1.5)
		"glass":
			l.draw_polyline(tf * PackedVector2Array([Vector2(-24, -40), Vector2(24, -40), Vector2(0, 0), Vector2(24, 40), Vector2(-24, 40), Vector2(0, 0), Vector2(-24, -40)]), col, 2.0)
			l.draw_line(tf * Vector2(-30, -44), tf * Vector2(30, -44), col, 3.0)
			l.draw_line(tf * Vector2(-30, 44), tf * Vector2(30, 44), col, 3.0)
