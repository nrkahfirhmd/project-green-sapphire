extends Node2D
## The cave around the arena. Back to front: a far row of columns, the ceiling
## and its stalactites, the near prism-column wall with crystal veins and
## hanging vines, the gem-cut floor with its bevelled rim, flagstones, cracks
## and chips, then rocks, spires and crystal clusters packed into every bit of
## ground between the rim and the screen edge, and dust drifting up through it.
##
## Sapphire Core and Deep Moss only. Pale Jade is reserved for telegraphs, so
## nothing in the scenery can ever read as "look now". Under the ASCII shader
## alpha becomes glyph density: below 0.2 a tone comes out as scattered specks
## (floor tiles, the far wall), 0.2-0.5 as light '- = +' texture, and only the
## crystals go denser. The boss and telegraphs stay the densest things on screen.
## Laid out from a fixed seed, so the cave is the same every run.
##
## Performance: the cave is ~1000 polygons, so this node draws it once and
## never redraws. Only the dust and vines are redrawn each frame (on _live),
## and the crystals glimmer by pulsing the modulate of a few pre-drawn layers
## rather than being redrawn. Redrawing everything every frame cost ~5x the
## whole rest of the game.

const SEED := 7
const MOTES := 70
const RIM := 18.0          # bevel width around the floor
const GLIMMER_GROUPS := 3  # crystal layers pulsing out of phase

var _far: Array = []       # far-wall columns: {x, w, h}
var _stal: Array = []      # stalactites: {x, w, len, lean, a}
var _cols: Array = []      # near-wall prism columns: {x, w, h, a, strata}
var _veins: Array = []     # PackedVector2Array crystal veins on the wall
var _vines: Array = []     # {x, top, len, ph}
var _rim := PackedVector2Array()   # floor outline pushed outward by RIM
var _tiles: Array = []     # floor flagstones: {pts, a}
var _cracks: Array = []    # PackedVector2Array polylines on the floor
var _pebbles: Array = []   # {c, s}
var _ground: Array = []    # scenery off the floor, sorted back to front: {kind, y, ...}
var _motes: Array = []     # {p, v, ph}
var _t := 0.0
var _live: Node2D          # redrawn every frame: dust and vines only
var _glimmer: Array = []   # one pre-drawn crystal layer per phase group
var _arena: Rect2
var _poly: PackedVector2Array


func _ready() -> void:
	# Main builds the arena in its own _ready, which runs after its children's
	await get_parent().ready
	var vp := get_viewport_rect().size
	_arena = get_parent().arena_rect
	_poly = get_parent().arena_poly
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_far_wall(rng, vp)
	_build_ceiling(rng, vp)
	_build_wall(rng, vp)
	_build_floor(rng)
	_build_ground(rng, vp)
	for i in MOTES:
		_motes.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y),
			"v": rng.randf_range(6.0, 16.0), "ph": rng.randf() * TAU})

	for i in GLIMMER_GROUPS:
		var layer := Node2D.new()
		layer.draw.connect(_draw_shards.bind(layer, i))
		add_child(layer)
		_glimmer.append(layer)
	_live = Node2D.new()
	_live.draw.connect(_draw_live)
	add_child(_live)
	queue_redraw()   # the one and only full draw


## A second, fainter row of columns behind the near wall. Faint enough to come
## out as specks, which fills the gap above the wall without adding noise.
func _build_far_wall(rng: RandomNumberGenerator, vp: Vector2) -> void:
	var x := -10.0
	while x < vp.x + 10.0:
		var w := rng.randf_range(28.0, 58.0)
		_far.append({"x": x, "w": w, "h": rng.randf_range(150.0, _arena.position.y - 40.0)})
		x += w


## Stalactites hanging from the top edge. The top-left corner stays clear for
## the run timer.
func _build_ceiling(rng: RandomNumberGenerator, vp: Vector2) -> void:
	var x := 200.0
	while x < vp.x + 20.0:
		var w := rng.randf_range(18.0, 56.0)
		_stal.append({"x": x, "w": w, "len": rng.randf_range(24.0, 110.0),
			"lean": rng.randf_range(-6.0, 6.0), "a": rng.randf_range(0.22, 0.3)})
		x += w * rng.randf_range(0.6, 1.1)


## Basalt-style columns standing along the back of the cave: taller towards the
## sides so the middle stays open behind the boss.
func _build_wall(rng: RandomNumberGenerator, vp: Vector2) -> void:
	var foot := _arena.position.y
	var x := -20.0
	while x < vp.x + 20.0:
		var w := rng.randf_range(44.0, 92.0)
		var edge := absf((x + w * 0.5) / vp.x - 0.5) * 2.0   # 0 centre .. 1 sides
		var strata := []
		for i in rng.randi_range(1, 3):
			strata.append(rng.randf_range(0.2, 0.9))
		# capped so the tallest stays clear of the HUD's top row
		var h := minf(lerpf(90.0, 175.0, edge) + rng.randf_range(-20.0, 20.0), foot - 75.0)
		_cols.append({"x": x, "w": w, "h": h, "a": rng.randf_range(0.2, 0.24), "strata": strata})
		# vines hang from about a third of the column tops
		if rng.randf() < 0.35:
			_vines.append({"x": x + rng.randf_range(8.0, w - 8.0), "top": foot - h + w * 0.15,
				"len": rng.randf_range(40.0, h * 0.8), "ph": rng.randf() * TAU})
		x += w
	# crystal veins zigzagging down the wall face
	for i in 12:
		var p := Vector2(rng.randf() * vp.x, foot - rng.randf_range(40.0, 120.0))
		var line := PackedVector2Array([p])
		for j in rng.randi_range(3, 6):
			p += Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(8.0, 18.0))
			line.append(p)
		_veins.append(line)


## Bevel rim, flagstones, cracks and embedded crystal chips. The tiles are all
## below the shader's 0.2 line, so they read as patches of specks, never as
## solid shapes: the floor is where every telegraph is drawn and it has to stay
## readable.
func _build_floor(rng: RandomNumberGenerator) -> void:
	var c := Vector2.ZERO
	for p in _poly:
		c += p
	c /= _poly.size()
	for p in _poly:
		_rim.append(p + (p - c).normalized() * RIM)

	var y := _arena.position.y
	while y < _arena.end.y:
		var h := rng.randf_range(40.0, 54.0)
		var x := _arena.position.x - rng.randf_range(0.0, 60.0)
		while x < _arena.end.x:
			var w := rng.randf_range(56.0, 104.0)
			var tile := PackedVector2Array()
			for k in [Vector2(x + 3, y + 3), Vector2(x + w - 3, y + 3), Vector2(x + w - 3, y + h - 3), Vector2(x + 3, y + h - 3)]:
				tile.append(k + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)))
			var a := rng.randf_range(0.03, 0.13)
			for piece in Geometry2D.intersect_polygons(tile, _poly):
				_tiles.append({"pts": piece, "a": a})
			x += w
		y += h

	var main := get_parent()
	for i in 10:
		var p := _random_on_floor(rng)
		var ang := rng.randf() * TAU
		var line := PackedVector2Array([p])
		for j in rng.randi_range(5, 9):
			ang += rng.randf_range(-0.6, 0.6)
			p = main.clamp_to_arena(p + Vector2(rng.randf_range(16.0, 34.0), 0).rotated(ang))
			line.append(p)
		_cracks.append(line)
	for i in 30:
		_pebbles.append({"c": _random_on_floor(rng), "s": rng.randf_range(3.0, 6.0)})


func _random_on_floor(rng: RandomNumberGenerator) -> Vector2:
	while true:
		var p := Vector2(rng.randf_range(_arena.position.x, _arena.end.x), rng.randf_range(_arena.position.y, _arena.end.y))
		if Geometry2D.is_point_in_polygon(p, _poly):
			return p
	return _arena.get_center()


## Everything off the floor: rocks, spires and crystal clusters packed into the
## ground between the rim and the screen edge, below the foot of the wall. None
## of it lands on the floor, so nothing that looks solid sits where the player
## can walk. Sorted by y so nearer pieces overlap farther ones.
func _build_ground(rng: RandomNumberGenerator, vp: Vector2) -> void:
	var main := get_parent()
	var foot := _arena.position.y
	var placed: Array = []    # [centre, radius]
	for k in 1400:
		var p := Vector2(rng.randf_range(-20.0, vp.x + 20.0), rng.randf_range(foot - 8.0, vp.y + 24.0))
		var r := rng.randf_range(12.0, 36.0)
		# stay off the floor and its rim
		if p.distance_to(main.clamp_to_arena(p)) < r + RIM + 4.0:
			continue
		var free := true
		for q in placed:
			if p.distance_to(q[0]) < (r + float(q[1])) * 0.78:
				free = false
				break
		if free:
			placed.append([p, r])

	for q in placed:
		var p: Vector2 = q[0]
		var r: float = q[1]
		var roll := rng.randf()
		if roll < 0.24:
			# crystal cluster: 3-5 thin two-faced shards
			for i in rng.randi_range(3, 5):
				var b := p + Vector2(rng.randf_range(-r, r), rng.randf_range(-3.0, 3.0))
				_ground.append({"kind": "shard", "y": b.y, "b": b, "h": r * rng.randf_range(1.6, 3.6),
					"w": rng.randf_range(5.0, 11.0), "lean": rng.randf_range(-0.35, 0.35), "grp": rng.randi() % GLIMMER_GROUPS})
		elif roll < 0.4:
			# spire: a tall stalagmite with a lit face
			_ground.append({"kind": "spire", "y": p.y, "b": p, "h": r * rng.randf_range(1.8, 3.2),
				"w": r * 0.6, "a": rng.randf_range(0.24, 0.3)})
		else:
			_ground.append(_rock(rng, p, r))
	_ground.sort_custom(func(a, b): return a.y < b.y)


func _rock(rng: RandomNumberGenerator, c: Vector2, r: float) -> Dictionary:
	var pts := PackedVector2Array()
	var cap := PackedVector2Array()
	var n := rng.randi_range(6, 8)
	for i in n:
		var p := Vector2(r * rng.randf_range(0.75, 1.1), 0).rotated(TAU * i / n)
		pts.append(c + Vector2(p.x, p.y * 0.7))
		# lit top face: the same outline, smaller and shifted up
		cap.append(c + Vector2(p.x * 0.6, p.y * 0.4 - r * 0.28))
	return {"kind": "rock", "y": c.y, "pts": pts, "cap": cap, "a": rng.randf_range(0.2, 0.3)}


func _process(delta: float) -> void:
	if _live == null:
		return
	_t += delta
	for i in _glimmer.size():
		_glimmer[i].modulate.a = 0.82 + 0.18 * sin(_t * 0.9 + i * TAU / GLIMMER_GROUPS)
	var vp := get_viewport_rect().size
	for m in _motes:
		var p: Vector2 = m.p - Vector2(0, m.v * delta)
		m.p = Vector2(p.x, vp.y + 10.0) if p.y < -10.0 else p
	_live.queue_redraw()


func _draw() -> void:
	if _poly.is_empty():
		return
	var base := Game.SAPPHIRE_CORE
	var foot := _arena.position.y
	var top_w := get_viewport_rect().size.x

	# far wall and ceiling, faint enough to land as specks
	for f in _far:
		draw_rect(Rect2(f.x, foot - float(f.h), f.w, f.h), Color(base, 0.14))
		draw_line(Vector2(f.x, foot - float(f.h)), Vector2(f.x, foot), Game.DEEP_MOSS, 2.0)
	draw_rect(Rect2(0, 0, top_w, 26), Color(base, 0.16))
	for s in _stal:
		var x: float = s.x
		var w: float = s.w
		var tip := Vector2(x + float(s.lean), float(s.len))
		draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5, 0), Vector2(x, 0), tip]), Color(base, float(s.a) + 0.08))
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w * 0.5, 0), tip]), Color(base, s.a))

	# near wall: front face, a lit strip on the left edge, a hex cap on top, and
	# Deep Moss seams between columns so each one reads as its own prism
	for col in _cols:
		var x: float = col.x
		var w: float = col.w
		var top: float = foot - float(col.h)
		var a: float = col.a
		draw_rect(Rect2(x, top, w, foot - top), Color(base, a))
		draw_rect(Rect2(x, top, w * 0.18, foot - top), Color(base, a + 0.06))
		for s in col.strata:
			var sy: float = lerpf(top, foot, s)
			draw_line(Vector2(x + 4, sy), Vector2(x + w * 0.6, sy + 3), Game.DEEP_MOSS, 2.0)
		draw_line(Vector2(x, top), Vector2(x, foot), Game.DEEP_MOSS, 3.0)
		var cap := Game.ellipse(w * 0.5, w * 0.2, 6)
		for i in cap.size():
			cap[i] += Vector2(x + w * 0.5, top)
		draw_colored_polygon(cap, Color(base, a + 0.22))
	for v in _veins:
		draw_polyline(v, Color(base, 0.45), 2.0)

	# the floor: a bevelled gem facet per edge, shaded alternately so the rim
	# reads as cut stone, then the seams darkened and the flagstones laid on top
	var n := _poly.size()
	for i in n:
		var j := (i + 1) % n
		draw_colored_polygon(PackedVector2Array([_poly[i], _poly[j], _rim[j], _rim[i]]),
			Color(base, 0.36 if i % 2 == 0 else 0.24))
		draw_line(_poly[i], _rim[i], Game.DEEP_MOSS, 2.0)
	draw_polyline(_rim + PackedVector2Array([_rim[0]]), Game.DEEP_MOSS, 2.0)
	draw_colored_polygon(_poly, Color(Game.DEEP_MOSS, 0.6))
	for t in _tiles:
		draw_colored_polygon(t.pts, Color(base, t.a))
	for c in _cracks:
		draw_polyline(c, Color(base, 0.28), 2.0)
	for p in _pebbles:
		var c: Vector2 = p.c
		var s: float = p.s
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0),
			c + Vector2(0, s * 0.6), c + Vector2(-s, 0)]), Color(base, 0.32))

	# ground scenery, back to front (crystals are on the glimmer layers)
	for g in _ground:
		match g.kind:
			"rock":
				draw_colored_polygon(g.pts, Color(base, g.a))
				draw_colored_polygon(g.cap, Color(base, g.a + 0.15))
				draw_polyline(g.pts + PackedVector2Array([g.pts[0]]), Game.DEEP_MOSS, 2.0)
			"spire":
				var b: Vector2 = g.b
				var w: float = g.w
				var tip := b + Vector2(0, -float(g.h))
				draw_colored_polygon(PackedVector2Array([b - Vector2(w, 0), b, tip]), Color(base, float(g.a) + 0.1))
				draw_colored_polygon(PackedVector2Array([b, b + Vector2(w, 0), tip]), Color(base, g.a))
				draw_line(b - Vector2(w, 0), b + Vector2(w, 0), Game.DEEP_MOSS, 2.0)


## Crystals in one glimmer group, drawn once onto that group's layer. They
## glimmer through the layer's modulate: brightness only, never Pale Jade.
func _draw_shards(layer: Node2D, grp: int) -> void:
	var base := Game.SAPPHIRE_CORE
	for g in _ground:
		if g.kind != "shard" or g.grp != grp:
			continue
		var b: Vector2 = g.b
		var h: float = g.h
		var w: float = g.w
		var tip := b + Vector2(g.lean * h, -h)
		layer.draw_colored_polygon(PackedVector2Array([b - Vector2(w, 0), b, tip]), Color(base, 0.88))
		layer.draw_colored_polygon(PackedVector2Array([b, b + Vector2(w, 0), tip]), Color(base, 0.48))
		layer.draw_line(b - Vector2(w, 0), tip, Game.DEEP_MOSS, 2.0)


## The only per-frame drawing: swaying vines and rising dust.
func _draw_live() -> void:
	var base := Game.SAPPHIRE_CORE
	# vines sway a little and carry a leaf every so often
	for v in _vines:
		var pts := PackedVector2Array()
		var vl: float = v.len
		var i := 0.0
		while i <= vl:
			var sway := sin(i * 0.08 + _t * 0.7 + float(v.ph)) * 4.0 * (i / vl)
			var p := Vector2(float(v.x) + sway, float(v.top) + i)
			pts.append(p)
			if int(i) % 16 == 8:
				_live.draw_colored_polygon(PackedVector2Array([p, p + Vector2(5, -3), p + Vector2(8, 1), p + Vector2(4, 3)]),
					Color(base, 0.42))
			i += 4.0
		_live.draw_polyline(pts, Color(base, 0.36), 2.0)

	# dust rising through the cave, swaying a little
	for m in _motes:
		var p: Vector2 = m.p + Vector2(sin(_t * 0.6 + float(m.ph)) * 8.0, 0)
		_live.draw_circle(p, 2.5, Color(base, 0.45))
