extends Node2D
## Shared plumbing for the fight scenery. Like the cave (arena_env.gd), the
## scenery is drawn once and never redrawn; only what moves is redrawn each
## frame, on a small child layer. Redrawing everything every frame cost ~5x the
## rest of the game.
##
## Each scenery script overrides _build (lay out from the seeded rng),
## _draw_static (drawn once) and _draw_live (every frame, onto `live`).
## Colours: Sapphire Core and Deep Moss only -- Pale Jade is for telegraphs.

var vp: Vector2
var arena: Rect2
var poly: PackedVector2Array     # the walkable floor
var centre: Vector2
var live: Node2D
var t := 0.0
var motes: Array = []            # {p, s, ph}
var mote_drift := Vector2(0, -11)
var mote_count := 40
var seed_value := 1


func _ready() -> void:
	# Main builds the arena in its own _ready, which runs after its children's
	await get_parent().ready
	vp = get_viewport_rect().size
	arena = get_parent().arena_rect
	poly = get_parent().arena_poly
	centre = arena.get_center()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_build(rng)
	for i in mote_count:
		motes.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y),
			"s": rng.randf_range(0.6, 1.4), "ph": rng.randf() * TAU})
	live = Node2D.new()
	live.draw.connect(func() -> void: _draw_live(live))
	add_child(live)
	queue_redraw()


func _process(delta: float) -> void:
	if live == null:
		return
	t += delta
	for m in motes:
		var p: Vector2 = m.p + mote_drift * float(m.s) * delta
		m.p = Vector2(fposmod(p.x, vp.x), fposmod(p.y + 10.0, vp.y + 20.0) - 10.0)
	live.queue_redraw()


func _draw() -> void:
	if poly.is_empty():
		return
	_draw_static()


func _build(_rng: RandomNumberGenerator) -> void:
	pass


func _draw_static() -> void:
	pass


func _draw_live(_c: Node2D) -> void:
	pass


# --- helpers -----------------------------------------------------------
func draw_motes(c: Node2D, col: Color, r := 2.5, sway := 8.0) -> void:
	for m in motes:
		c.draw_circle(m.p + Vector2(sin(t * 0.6 + float(m.ph)) * sway, 0), r, col)


func on_floor(p: Vector2, margin := 0.0) -> bool:
	if Geometry2D.is_point_in_polygon(p, poly):
		return true
	return margin > 0.0 and p.distance_to(get_parent().clamp_to_arena(p)) < margin


## A bevelled rim around the floor: one facet per edge, shaded alternately.
func draw_rim(width: float, a_hi: float, a_lo: float) -> void:
	var rim := PackedVector2Array()
	for p in poly:
		rim.append(p + (p - centre).normalized() * width)
	var n := poly.size()
	for i in n:
		var j := (i + 1) % n
		draw_colored_polygon(PackedVector2Array([poly[i], poly[j], rim[j], rim[i]]),
			Color(Game.SAPPHIRE_CORE, a_hi if i % 2 == 0 else a_lo))
	draw_polyline(rim + PackedVector2Array([rim[0]]), Game.DEEP_MOSS, 2.0)


## Draw `shape` clipped to the floor.
func draw_on_floor(shape: PackedVector2Array, col: Color) -> void:
	for piece in Geometry2D.intersect_polygons(shape, poly):
		draw_colored_polygon(piece, col)


## Scatter non-overlapping spots over the screen, off the floor and its rim,
## below `top`. Returns [centre, radius] pairs sorted back to front.
func scatter(rng: RandomNumberGenerator, top: float, tries: int, r_lo: float, r_hi: float, margin := 26.0) -> Array:
	var placed: Array = []
	for k in tries:
		var p := Vector2(rng.randf_range(-20.0, vp.x + 20.0), rng.randf_range(top, vp.y + 24.0))
		var r := rng.randf_range(r_lo, r_hi)
		if on_floor(p, r + margin):
			continue
		var free := true
		for q in placed:
			if p.distance_to(q[0]) < (r + float(q[1])) * 0.8:
				free = false
				break
		if free:
			placed.append([p, r])
	placed.sort_custom(func(a, b): return a[0].y < b[0].y)
	return placed


func rock(rng: RandomNumberGenerator, c: Vector2, r: float, a_lo := 0.2, a_hi := 0.3) -> Dictionary:
	var pts := PackedVector2Array()
	var cap := PackedVector2Array()
	var n := rng.randi_range(6, 8)
	for i in n:
		var p := Vector2(r * rng.randf_range(0.75, 1.1), 0).rotated(TAU * i / n)
		pts.append(c + Vector2(p.x, p.y * 0.7))
		cap.append(c + Vector2(p.x * 0.6, p.y * 0.4 - r * 0.28))
	return {"kind": "rock", "pts": pts, "cap": cap, "a": rng.randf_range(a_lo, a_hi)}


func draw_rock(r: Dictionary) -> void:
	draw_colored_polygon(r.pts, Color(Game.SAPPHIRE_CORE, r.a))
	draw_colored_polygon(r.cap, Color(Game.SAPPHIRE_CORE, float(r.a) + 0.15))
	draw_polyline(r.pts + PackedVector2Array([r.pts[0]]), Game.DEEP_MOSS, 2.0)


func box(c: Vector2, size: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([c - h, c + Vector2(h.x, -h.y), c + h, c + Vector2(-h.x, h.y)])
