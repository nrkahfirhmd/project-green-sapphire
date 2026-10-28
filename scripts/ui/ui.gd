extends RefCounted
## The UI kit from the design handoff (docs/design_handoff_green_sapphire_ui):
## IBM Plex Mono in two weights, letter-spaced; square frames with 8x8 corner
## ticks; diamonds as rotated squares; the heart shape. Every function draws
## onto the CanvasItem it is given, so HUDs, menus and buttons share one look.
##
##   const UI := preload("res://scripts/ui/ui.gd")
##
## All UI text is uppercase. Pale Jade appears in five places only (boss
## health, low-HP bands, the lost-heart flash, a dropped sapphire, the gate
## opening) -- never on buttons, headings or selection.

const MOSS := Color("3B4939")
const CORE := Color("69A062")
const JADE := Color("BBE2B6")

const STROKE := 2.0
const TICK := 8.0

const _FILES := {400: "res://fonts/IBMPlexMono-Regular.otf", 600: "res://fonts/IBMPlexMono-SemiBold.otf"}
static var _fonts := {}


## Plex Mono at `weight` (400 or 600) with letter-spacing in em at `size`.
## FontVariation spacing is in pixels, so each size gets its own variation.
static func font(size: int, weight := 600, em := 0.0) -> Font:
	var key := "%d/%d/%.2f" % [size, weight, em]
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = load(_FILES[weight])
		v.spacing_glyph = roundi(em * size)
		_fonts[key] = v
	return _fonts[key]


## Width as drawn. The variation's letter-spacing is already included, and
## measured this way spaced text centres to within a couple of units.
static func text_width(s: String, size: int, weight := 600, em := 0.0) -> float:
	return font(size, weight, em).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text whose top-left (align -1), top-centre (0) or top-right (1) is `at`.
static func text(ci: CanvasItem, at: Vector2, s: String, size: int, col: Color, weight := 600, em := 0.0, align := -1) -> void:
	var f := font(size, weight, em)
	var w := text_width(s, size, weight, em)
	var x := at.x - (w * 0.5 if align == 0 else (w if align == 1 else 0.0))
	ci.draw_string(f, Vector2(x, at.y + f.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_height(size: int, weight := 600) -> float:
	return font(size, weight).get_height(size)


## A panel: optional fill, a 2-unit outline and solid squares on the corners.
static func frame(ci: CanvasItem, r: Rect2, col := CORE, fill := Color(MOSS, 0.9), ticks := true) -> void:
	if fill.a > 0.0:
		ci.draw_rect(r, fill)
	ci.draw_rect(r, col, false, STROKE)
	if ticks:
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			ci.draw_rect(Rect2(c - Vector2(TICK, TICK) * 0.5, Vector2(TICK, TICK)), col)


## A square of side `side` turned 45 degrees about `c`.
static func diamond(ci: CanvasItem, c: Vector2, side: float, col: Color, filled := true, width := STROKE) -> void:
	var h := side * 0.7071
	var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col, width)


static var _heart := PackedVector2Array()

## The design's heart (an SVG path on a 28x26 box): a point at the bottom and
## two half-circle lobes. `at` is the box's top-left.
static func heart(ci: CanvasItem, at: Vector2, col: Color, filled := true, s := 1.0) -> void:
	if _heart.is_empty():
		_heart.append(Vector2(14, 24))
		_heart.append(Vector2(3.5, 13.5))
		for k in range(1, 13):
			_heart.append(Vector2(8.75, 9.25) + Vector2(6.75, 0).rotated(deg_to_rad(lerpf(141.0, 321.0, k / 12.0))))
		for k in range(1, 13):
			_heart.append(Vector2(19.25, 9.25) + Vector2(6.75, 0).rotated(deg_to_rad(lerpf(219.0, 399.0, k / 12.0))))
	var pts := PackedVector2Array()
	for p in _heart:
		pts.append(at + (p - Vector2(14, 13)) * s + Vector2(14, 13))
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), col, STROKE)


## A dashed rectangle outline, for disabled buttons.
static func dashed_rect(ci: CanvasItem, r: Rect2, col: Color, dash := 8.0) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		ci.draw_dashed_line(corners[i], corners[(i + 1) % 4], col, STROKE, dash)


## Safe-area rect in this canvas, from the Game autoload.
static func safe(ci: CanvasItem) -> Rect2:
	return Game.safe_area(ci.get_viewport_rect().size)


static func fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
