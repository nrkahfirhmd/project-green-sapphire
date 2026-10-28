extends "res://scripts/envs/env_base.gd"
## Gate V, the Mirror's dark space: the inside of a mind. Almost nothing is
## lit. A round floor made of faint rings and spokes floats in the void under a
## huge outlined eye whose pupil follows the player. Geometric fragments and
## mirror shards drift and turn around the floor, and stars twinkle.
## Darker than every other room on purpose: the fight should be the only
## bright thing on screen.

var _stars: Array = []        # {p, a, ph}
var _shapes: Array = []       # {c, r, n, rot, spin, orbit, ph, a}
var _shards: Array = []       # {p, len, ang, v, ph}
var _eye := Vector2.ZERO


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
	for i in 10:
		_shards.append({"p": Vector2(rng.randf() * vp.x, rng.randf_range(arena.position.y, vp.y)), "len": rng.randf_range(30.0, 70.0),
			"ang": rng.randf() * TAU, "v": rng.randf_range(8.0, 18.0), "ph": rng.randf() * TAU})


func _draw_static() -> void:
	var c := Game.SAPPHIRE_CORE
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
	draw_polyline(almond, Color(c, 0.3), 3.0)
	draw_arc(_eye, 58.0, 0, TAU, 48, Color(c, 0.24), 3.0)

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

	var h := arena.size * 0.5
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
