extends RefCounted
## Paint: light and air for the scenery, shared by every room and the jail.
##
## Under the ASCII pass a smooth alpha ramp comes out as a ramp of glyph
## density, so gradients are how the scenery gets depth and light: a shaft of
## light is a fan of specks thickening towards its source, a glow is a halo of
## specks round a flame, a vignette thins the glyphs towards the screen edge.
## Everything here is Sapphire Core over Deep Moss, or Deep Moss on top to
## darken; Pale Jade stays reserved for telegraphs.

const C := Color("69A062")     # Game.SAPPHIRE_CORE
const M := Color("3B4939")     # Game.DEEP_MOSS


## A polygon fading from alpha `a0` at `from` to `a1` at `to` (any two points
## along the fade). Vertex colours do the blend, so it is one draw call.
static func gradient(ci: CanvasItem, pts: PackedVector2Array, from: Vector2, to: Vector2,
		a0: float, a1: float, col := C) -> void:
	var d := to - from
	var len2 := maxf(d.length_squared(), 0.001)
	var cols := PackedColorArray()
	for p in pts:
		var f := clampf((p - from).dot(d) / len2, 0.0, 1.0)
		cols.append(Color(col, lerpf(a0, a1, f)))
	ci.draw_polygon(pts, cols)


## A band of light from a source edge (a0..a1) down to a wider foot (b0..b1),
## bright at the source and gone at the foot.
static func shaft(ci: CanvasItem, a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2, a: float) -> void:
	var top := (a0 + a1) * 0.5
	var foot := (b0 + b1) * 0.5
	gradient(ci, PackedVector2Array([a0, a1, b1, b0]), top, foot, a, 0.0)
	# a brighter core down the middle of the band
	var k := 0.3
	gradient(ci, PackedVector2Array([a0.lerp(a1, 0.5 - k * 0.5), a0.lerp(a1, 0.5 + k * 0.5),
		b0.lerp(b1, 0.5 + k * 0.5), b0.lerp(b1, 0.5 - k * 0.5)]), top, foot, a * 0.6, 0.0)


## A soft round halo: alpha `a` at the centre falling to nothing at `r`.
## `squash` flattens it into a pool of light on the floor.
static func glow(ci: CanvasItem, p: Vector2, r: float, a: float, squash := 1.0, col := C) -> void:
	var pts := PackedVector2Array([p])
	var cols := PackedColorArray([Color(col, a)])
	for i in 25:
		var ang := TAU * i / 24.0
		pts.append(p + Vector2(cos(ang), sin(ang) * squash) * r)
		cols.append(Color(col, 0.0))
	var idx := PackedInt32Array()
	for i in 24:
		idx.append_array([0, i + 1, i + 2])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


## Darkens the screen edges with Deep Moss so the eye falls to the middle.
static func vignette(ci: CanvasItem, vp: Vector2, w: float, a: float) -> void:
	var o := Vector2.ZERO
	var r := vp
	var sides := [
		[Vector2(o.x, o.y), Vector2(r.x, o.y), Vector2(r.x - w, w), Vector2(w, w)],
		[Vector2(r.x, o.y), Vector2(r.x, r.y), Vector2(r.x - w, r.y - w), Vector2(r.x - w, w)],
		[Vector2(r.x, r.y), Vector2(o.x, r.y), Vector2(w, r.y - w), Vector2(r.x - w, r.y - w)],
		[Vector2(o.x, r.y), Vector2(o.x, o.y), Vector2(w, w), Vector2(w, r.y - w)],
	]
	for s in sides:
		ci.draw_polygon(PackedVector2Array(s), PackedColorArray([Color(M, a), Color(M, a), Color(M, 0.0), Color(M, 0.0)]))


## A candle or torch flame that licks and flickers; `seed` keeps neighbours
## out of step.
static func flame(ci: CanvasItem, p: Vector2, h: float, t: float, seed: float, a := 0.85) -> void:
	var lick := h * (1.0 + 0.22 * sin(t * 11.0 + seed) + 0.14 * sin(t * 17.3 + seed * 1.7))
	var sway := sin(t * 7.0 + seed * 2.3) * h * 0.18
	var w := h * 0.36
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(sway, -lick), p + Vector2(w, -h * 0.18),
		p + Vector2(w * 0.6, h * 0.12), p + Vector2(-w * 0.6, h * 0.12), p + Vector2(-w, -h * 0.18)]), Color(C, a))
	# the hot core, a darker notch so the flame reads as a flame and not a blob
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(sway * 0.5, -lick * 0.45), p + Vector2(w * 0.35, 0),
		p + Vector2(-w * 0.35, 0)]), Color(M, 0.55))


## Horizontal bands from `top` to `bottom`, alpha a0 to a1: a sky or a wall
## falling into shadow.
static func vband(ci: CanvasItem, r: Rect2, a0: float, a1: float, col := C) -> void:
	gradient(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		r.position, Vector2(r.position.x, r.end.y), a0, a1, col)


## A cobweb tucked into a corner (`dir` points out of the corner).
static func web(ci: CanvasItem, corner: Vector2, r: float, dir: Vector2, a := 0.3) -> void:
	var base := dir.angle()
	var spokes: Array = []
	for i in 5:
		spokes.append(Vector2.RIGHT.rotated(base - PI * 0.25 + PI * 0.5 * i / 4.0))
	for s in spokes:
		ci.draw_line(corner, corner + s * r, Color(C, a), 1.5)
	for k in range(1, 4):
		var ring := PackedVector2Array()
		for s in spokes:
			ring.append(corner + s * r * k / 3.6)
		ci.draw_polyline(ring, Color(C, a * 0.85), 1.5)
