extends Node2D
## The jail: the hub between fights. Cells I and II are cut into the back wall,
## III and IV into the front wall, and the great gate V into the right wall.
## Walk into an open cell to fight the boss held there; beat it and it drops a
## sapphire. Carry the sapphire back to the altar in the middle of the hall.
## With four sapphires set, the gate lifts on the final boss.
##
## Every cell leads to the same fight scene for now; Game.current_boss tells the
## fight (and, on the way back, this scene) which cell it came from.
##
## Drawn like the arena: palette shapes under the ASCII shader. The jail itself
## is drawn once and never redrawn; only torches, the eyes in the cells, the
## altar's sapphires, the gate and the dust are redrawn each frame, on _live.

const FIGHT := "res://scenes/main.tscn"
const SEED := 3
const WALL_TOP := 230.0          # back wall height; cells I-II are cut into it
const SIDE := 80.0               # left wall thickness
const RIGHT := 150.0             # right wall thickness; gate V is cut into it
const FRONT := 110.0             # front wall depth; cells III-IV are cut into it
const CELL_W := 150.0
const CELL_D := 120.0
const ALTAR_R := 92.0            # the altar is solid out to here
const REACH := 150.0             # this close counts as standing at the altar
const ENTER_DEPTH := 20.0        # how far into a cell before the fight starts
const MOTES := 40
const NUMERALS := ["", "I", "II", "III", "IV", "V"]

var hall: Rect2                  # the walkable floor
var altar: Vector2
var doors := {}                  # id -> {"cell": Rect2, "mouth": Vector2}

var _bricks: Array = []          # {r: Rect2, a: float}, walls and floor alike
var _straw: Array = []           # PackedVector2Array tufts along the walls
var _chains: Array = []          # PackedVector2Array hanging from the back wall
var _sconces: Array = []         # torch positions on the back wall
var _drains: Array = []          # Rect2 floor grates
var _pilasters: Array = []       # Rect2 columns on the back wall
var _slabs: Array = []           # {pts, a}: ring round the altar and walkways to each door
var _rubble: Array = []          # {pts, a}: rock piles in the hall corners
var _altar_poly := PackedVector2Array()
var _altar_rim := PackedVector2Array()
var _motes: Array = []           # {p, v, ph}

var _live: Node2D
var _t := 0.0
var _gate_open := 0.0            # 0 shut .. 1 bars fully raised
var _flash := 0.0                # Pale Jade flash the moment the gate unlocks
var _leaving := false
var _hint: Label
var _gate_label: Label

@onready var player: CharacterBody2D = $Player


func _ready() -> void:
	var vp := get_viewport_rect().size
	hall = Rect2(SIDE, WALL_TOP, vp.x - SIDE - RIGHT, vp.y - WALL_TOP - FRONT)
	altar = hall.get_center()
	for id in [1, 2]:
		var x: float = hall.position.x + hall.size.x * [0.15, 0.62][id - 1]
		doors[id] = {"cell": Rect2(x - CELL_W * 0.5, WALL_TOP - CELL_D, CELL_W, CELL_D),
			"mouth": Vector2(x, WALL_TOP + 70.0)}
	for id in [3, 4]:
		var x: float = hall.position.x + hall.size.x * [0.2, 0.66][id - 3]
		doors[id] = {"cell": Rect2(x - CELL_W * 0.5, hall.end.y, CELL_W, FRONT - 14.0),
			"mouth": Vector2(x, hall.end.y - 70.0)}
	# higher than the hall's middle, to keep it clear of the touch buttons
	var gy := hall.position.y + hall.size.y * 0.36
	doors[5] = {"cell": Rect2(hall.end.x, gy - 95.0, RIGHT - 34.0, 190.0),
		"mouth": Vector2(hall.end.x - 80.0, gy)}

	# back from a fight: stand in front of the cell it came from
	var from := Game.current_boss
	player.global_position = doors[from].mouth if doors.has(from) else Vector2(altar.x, hall.end.y - 90.0)
	Game.current_boss = 0
	_gate_open = 1.0 if _gate_unlocked() else 0.0

	_build(vp)
	_make_labels(vp)
	_live = Node2D.new()
	_live.draw.connect(_draw_live)
	add_child(_live)


# --- rules -----------------------------------------------------------
func _gate_unlocked() -> bool:
	return Game.crystals_placed() == 4


## A cell can be entered while its boss still holds its sapphire. The gate
## also has to be unlocked and finished lifting.
func _door_open(id: int) -> bool:
	if Game.crystals.has(id):
		return false
	return id != 5 or (_gate_unlocked() and _gate_open > 0.9)


## Nearest walkable point: the hall plus any open cell, minus the altar.
func clamp_to_arena(p: Vector2) -> Vector2:
	var best := p.clamp(hall.position, hall.end)
	for id in doors:
		if _door_open(id):
			var r: Rect2 = doors[id].cell
			var q := p.clamp(r.position, r.end)
			if q.distance_squared_to(p) < best.distance_squared_to(p):
				best = q
	var off := best - altar
	if off.length() < ALTAR_R and off != Vector2.ZERO:
		best = altar + off.normalized() * ALTAR_R
	return best


func spawn_burst(pos: Vector2, color: Color, n := 10, speed := 220.0) -> void:
	Game.burst(self, pos, color, n, speed)


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if _gate_unlocked():
		_gate_open = move_toward(_gate_open, 1.0, delta * 0.7)
	if not _leaving:
		_set_sapphires()
		_check_doors()
	_hint.text = _hint_text()
	_gate_label.modulate.a = 1.0 if _gate_unlocked() else 0.4
	var vp := get_viewport_rect().size
	for m in _motes:
		var p: Vector2 = m.p - Vector2(0, m.v * delta)
		m.p = Vector2(p.x, vp.y + 10.0) if p.y < -10.0 else p
	_live.queue_redraw()


## Standing at the altar sets every sapphire the player is carrying.
func _set_sapphires() -> void:
	if player.global_position.distance_to(altar) > REACH:
		return
	for id in Game.crystals.keys():
		if Game.crystals[id] != "carried":
			continue
		Game.crystals[id] = "placed"
		spawn_burst(_socket(id), Game.PALE_JADE, 18, 260.0)
		if id != 5 and _gate_unlocked():
			_flash = 0.7


func _check_doors() -> void:
	for id in doors:
		if _door_open(id) and doors[id].cell.grow(-ENTER_DEPTH).has_point(player.global_position):
			_leaving = true
			Game.current_boss = id
			get_tree().change_scene_to_file.call_deferred(FIGHT)
			return


func _hint_text() -> String:
	if Game.crystals.get(5, "") == "placed":
		return "THE GREEN SAPPHIRE IS WHOLE"
	if Game.crystals.values().has("carried"):
		return "BRING THE SAPPHIRE TO THE ALTAR"
	if _gate_unlocked():
		return "THE GREAT GATE IS OPEN"
	return "TAKE A SAPPHIRE FROM EVERY CELL     %d / 4" % Game.crystals_placed()


## Where sapphire `id` sits on the altar: I-IV round the rim, V in the middle.
func _socket(id: int) -> Vector2:
	if id == 5:
		return altar + Vector2(0, -4)
	return altar + Vector2(58, 0).rotated(-PI * 0.75 + (id - 1) * PI * 0.5) * Vector2(1, 0.62)


# --- layout (once) ---------------------------------------------------
func _build(vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# walls: brick courses; floor: big flagstones, faint enough to read as specks
	_course(rng, Rect2(0, 0, vp.x, WALL_TOP - 10), 30.0, Vector2(50, 110), 0.2, 0.32)
	_course(rng, Rect2(0, WALL_TOP, SIDE - 12, hall.size.y), 26.0, Vector2(24, 44), 0.22, 0.32)
	_course(rng, Rect2(hall.end.x + 12, WALL_TOP, RIGHT - 12, hall.size.y), 26.0, Vector2(30, 60), 0.22, 0.32)
	_course(rng, Rect2(0, hall.end.y + 12, vp.x, FRONT), 26.0, Vector2(50, 110), 0.24, 0.34)
	_course(rng, hall, 58.0, Vector2(70, 120), 0.04, 0.13)

	# pilasters on the back wall wherever a cell isn't
	var px := 30.0
	while px < vp.x:
		if not _near_cell(Vector2(px, WALL_TOP - 60.0), 40.0):
			_pilasters.append(Rect2(px - 16.0, 30.0, 32.0, WALL_TOP - 40.0))
		px += rng.randf_range(160.0, 230.0)

	# a ring of slabs round the altar, and a worn walkway from it to every door
	for i in 18:
		var a0 := TAU * i / 18.0 + 0.02
		var a1 := TAU * (i + 1) / 18.0 - 0.02
		var ring := PackedVector2Array()
		for a in [a0, a1]:
			ring.append(altar + Vector2(cos(a), sin(a) * 0.7) * (ALTAR_R * 1.32))
		for a in [a1, a0]:
			ring.append(altar + Vector2(cos(a), sin(a) * 0.7) * (ALTAR_R * 1.9))
		_slabs.append({"pts": ring, "a": rng.randf_range(0.12, 0.18)})
	for id in doors:
		var from := altar
		var to: Vector2 = doors[id].mouth
		var dir := (to - from).normalized()
		var nrm := Vector2(-dir.y, dir.x) * 30.0
		var d := ALTAR_R * 1.9
		while d < from.distance_to(to) + 40.0:
			var a := from + dir * d
			var b := from + dir * (d + 36.0)
			_slabs.append({"pts": PackedVector2Array([a - nrm, a + nrm, b + nrm, b - nrm]), "a": rng.randf_range(0.12, 0.17)})
			d += 40.0

	# rubble piled in the hall's corners
	for corner in [hall.position, Vector2(hall.end.x, hall.position.y), Vector2(hall.position.x, hall.end.y), hall.end]:
		var inward: Vector2 = (altar - corner).normalized()
		for i in rng.randi_range(5, 8):
			var cp: Vector2 = corner + inward * rng.randf_range(10.0, 70.0) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-14, 14))
			if _near_cell(cp, 20.0):
				continue
			var rr := rng.randf_range(8.0, 20.0)
			var pts := PackedVector2Array()
			for k in 6:
				pts.append(cp + Vector2(rr * rng.randf_range(0.75, 1.1), 0).rotated(TAU * k / 6.0) * Vector2(1, 0.7))
			_rubble.append({"pts": pts, "a": rng.randf_range(0.26, 0.36)})

	# chains and torches on the back wall, between the cells
	for x in [0.04, 0.32, 0.45, 0.8, 0.96]:
		_sconces.append(Vector2(hall.position.x + hall.size.x * x, WALL_TOP - 110.0))
	for i in 12:
		var x := rng.randf_range(0.0, vp.x)
		if _near_cell(Vector2(x, WALL_TOP - 60.0), 30.0):
			continue
		var line := PackedVector2Array()
		var drop := rng.randf_range(60.0, 150.0)
		var y := 0.0
		while y < drop:
			line.append(Vector2(x + (4.0 if int(y / 8.0) % 2 == 0 else -4.0), y))
			y += 8.0
		_chains.append(line)

	# straw tufts along the foot of every wall, and two floor drains
	for i in 34:
		var p: Vector2
		match rng.randi() % 3:
			0: p = Vector2(rng.randf_range(hall.position.x, hall.end.x), hall.position.y + rng.randf_range(4.0, 22.0))
			1: p = Vector2(hall.position.x + rng.randf_range(4.0, 26.0), rng.randf_range(hall.position.y, hall.end.y))
			_: p = Vector2(hall.end.x - rng.randf_range(4.0, 26.0), rng.randf_range(hall.position.y, hall.end.y))
		if _near_cell(p, 26.0):
			continue
		for j in rng.randi_range(3, 6):
			var a := rng.randf_range(-PI, 0.0)
			_straw.append(PackedVector2Array([p, p + Vector2(rng.randf_range(8.0, 18.0), 0).rotated(a)]))
	_drains = [Rect2(altar + Vector2(-360, 110), Vector2(56, 30)), Rect2(altar + Vector2(300, -150), Vector2(56, 30))]

	# the altar: an uneven stone dais with a bevelled rim
	for i in 16:
		var a := TAU * i / 16.0
		var r := ALTAR_R * rng.randf_range(0.92, 1.06)
		var p := Vector2(cos(a), sin(a) * 0.7) * r
		_altar_poly.append(altar + p)
		_altar_rim.append(altar + p * 1.18 + Vector2(0, 8))

	for i in MOTES:
		_motes.append({"p": Vector2(rng.randf() * vp.x, rng.randf() * vp.y),
			"v": rng.randf_range(6.0, 16.0), "ph": rng.randf() * TAU})


## Brick courses filling `r`: rows of height `h`, brick widths in `w`.
func _course(rng: RandomNumberGenerator, r: Rect2, h: float, w: Vector2, a_lo: float, a_hi: float) -> void:
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x - rng.randf_range(0.0, w.x)
		while x < r.end.x:
			var bw := rng.randf_range(w.x, w.y)
			var b := Rect2(x + 2.0, y + 2.0, bw - 4.0, h - 4.0).intersection(r)
			if b.has_area():
				_bricks.append({"r": b, "a": rng.randf_range(a_lo, a_hi)})
			x += bw
		y += h


func _near_cell(p: Vector2, margin: float) -> bool:
	for id in doors:
		if doors[id].cell.grow(margin).has_point(p):
			return true
	return false


## Cell numerals and the hint line, as real text on the UI layer: through the
## ASCII shader they would turn to noise.
func _make_labels(vp: Vector2) -> void:
	_hint = _label(26)
	_hint.position = Vector2(0, 18)
	_hint.size = Vector2(vp.x, 40)
	for id in doors:
		var r: Rect2 = doors[id].cell
		var l := _label(30)
		l.text = NUMERALS[id]
		l.size = Vector2(120, 40)
		var y := r.position.y - 44.0 if id < 3 else r.get_center().y - 20.0
		if id == 5:
			y = r.position.y - 84.0     # above the lamps
		l.position = Vector2(r.get_center().x - 60.0, y)
		if Game.crystals.has(id):
			l.modulate.a = 0.35
		if id == 5:
			_gate_label = l


func _label(px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Game.SAPPHIRE_CORE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$UI.add_child(l)
	return l


# --- draw ------------------------------------------------------------
## The static jail, drawn once.
func _draw() -> void:
	var c := Game.SAPPHIRE_CORE
	var vp := get_viewport_rect().size
	for b in _bricks:
		draw_rect(b.r, Color(c, b.a))
	for pl in _pilasters:
		draw_rect(pl, Game.DEEP_MOSS)
		draw_rect(pl, Color(c, 0.3))
		draw_rect(Rect2(pl.position, Vector2(8, pl.size.y)), Color(c, 0.42))
		draw_rect(Rect2(pl.position - Vector2(6, 0), Vector2(pl.size.x + 12, 12)), Color(c, 0.46))
	for sl in _slabs:
		draw_colored_polygon(sl.pts, Color(c, sl.a))
	for rb in _rubble:
		draw_colored_polygon(rb.pts, Color(c, rb.a))
		draw_polyline(rb.pts + PackedVector2Array([rb.pts[0]]), Game.DEEP_MOSS, 2.0)

	# lit caps where each wall meets the floor
	draw_rect(Rect2(0, WALL_TOP - 10.0, vp.x, 10.0), Color(c, 0.36))
	draw_rect(Rect2(SIDE - 12.0, WALL_TOP, 12.0, hall.size.y), Color(c, 0.34))
	draw_rect(Rect2(hall.end.x, WALL_TOP, 12.0, hall.size.y), Color(c, 0.34))
	draw_rect(Rect2(0, hall.end.y, vp.x, 12.0), Color(c, 0.4))

	for ch in _chains:
		draw_polyline(ch, Color(c, 0.42), 3.0)
		draw_arc(ch[ch.size() - 1] + Vector2(0, 8), 8.0, 0, TAU, 14, Color(c, 0.5), 3.0)   # shackle
	for s in _sconces:
		draw_rect(Rect2(s + Vector2(-10, 0), Vector2(20, 8)), Color(c, 0.5))
		draw_line(s + Vector2(0, 8), s + Vector2(0, 30), Color(c, 0.5), 4.0)
	for st in _straw:
		draw_polyline(st, Color(c, 0.3), 2.0)
	for d in _drains:
		draw_rect(d, Color(c, 0.3))
		for i in 5:
			var x: float = d.position.x + 6.0 + i * 11.0
			draw_line(Vector2(x, d.position.y + 3), Vector2(x, d.end.y - 3), Game.DEEP_MOSS, 4.0)

	for id in doors:
		_draw_cell(id)

	# altar: bevelled rim, top face, dark sockets for the five sapphires
	var n := _altar_poly.size()
	for i in n:
		var j := (i + 1) % n
		draw_colored_polygon(PackedVector2Array([_altar_poly[i], _altar_poly[j], _altar_rim[j], _altar_rim[i]]),
			Color(c, 0.4 if i % 2 == 0 else 0.28))
	draw_colored_polygon(_altar_poly, Game.DEEP_MOSS)
	draw_colored_polygon(_altar_poly, Color(c, 0.22))
	draw_polyline(_altar_poly + PackedVector2Array([_altar_poly[0]]), Color(c, 0.5), 2.0)
	for id in [1, 2, 3, 4, 5]:
		var s := _socket(id)
		var e := Game.ellipse(12.0 if id != 5 else 18.0, 6.0 if id != 5 else 9.0)
		for k in e.size():
			e[k] += s
		draw_colored_polygon(e, Game.DEEP_MOSS)


## A cell: dark interior, a stone jamb, and bars. Open cells keep a gap in the
## bars where the cell door has swung out; cleared cells are barred shut.
## The gate's bars move, so they are drawn on _live instead.
func _draw_cell(id: int) -> void:
	var c := Game.SAPPHIRE_CORE
	var r: Rect2 = doors[id].cell
	draw_rect(r.grow(10), Color(c, 0.34))
	draw_rect(r, Game.DEEP_MOSS)
	draw_rect(r, Color(c, 0.07))
	if id == 5:
		return
	var open := _door_open(id)
	var gap := Vector2(r.get_center().x - r.size.x * 0.2, r.get_center().x + r.size.x * 0.2)
	var x := r.position.x + 9.0
	while x < r.end.x:
		if not (open and x > gap.x and x < gap.y):
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(c, 0.6), 5.0)
		x += 18.0
	draw_line(Vector2(r.position.x, r.position.y + 10), Vector2(r.end.x, r.position.y + 10), Color(c, 0.6), 5.0)
	if not open:
		draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(c, 0.6), 5.0)


## Everything that moves.
func _draw_live() -> void:
	var c := Game.SAPPHIRE_CORE

	# a boss eye watches from every cell that still holds its sapphire
	for id in doors:
		if Game.crystals.has(id):
			continue
		var r: Rect2 = doors[id].cell
		var e := 16.0 if id == 5 else 10.0
		var p := r.get_center()
		var col := Game.DEEP_MOSS.lerp(c, 0.5 + 0.5 * sin(_t * 1.3 + id * 1.7))
		_live.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -e), p + Vector2(e, 0),
			p + Vector2(0, e), p + Vector2(-e, 0)]), col)

	# the gate: bars rise as it unlocks; four lamps below count the sapphires set
	var g: Rect2 = doors[5].cell
	var bottom := g.end.y - _gate_open * g.size.y
	var x := g.position.x + 10.0
	while x < g.end.x:
		if bottom > g.position.y:
			_live.draw_line(Vector2(x, g.position.y), Vector2(x, bottom), Color(c, 0.65), 6.0)
		x += 16.0
	if bottom > g.position.y:
		_live.draw_line(Vector2(g.position.x, bottom), Vector2(g.end.x, bottom), Color(c, 0.65), 6.0)
	for i in 4:
		var lp := Vector2(g.get_center().x - 39.0 + i * 26.0, g.position.y - 24.0)
		if i < Game.crystals_placed():
			_live.draw_circle(lp, 8.0, Color(c, 0.9))
		else:
			_live.draw_arc(lp, 8.0, 0, TAU, 16, Color(c, 0.5), 2.0)

	# torches
	for s in _sconces:
		var h := 16.0 + 4.0 * sin(_t * 11.0 + s.x) + 3.0 * sin(_t * 17.3 + s.x * 0.5)
		_live.draw_circle(s + Vector2(0, -6), 38.0, Color(c, 0.1))
		_live.draw_colored_polygon(PackedVector2Array([s + Vector2(0, -h), s + Vector2(6, -3),
			s + Vector2(0, 2), s + Vector2(-6, -3)]), Color(c, 0.8))

	# sapphires on the altar
	for id in [1, 2, 3, 4, 5]:
		if Game.crystals.get(id, "") != "placed":
			continue
		var s := _socket(id)
		var h := 72.0 if id == 5 else 46.0
		var w := 16.0 if id == 5 else 12.0
		var a := 0.8 + 0.2 * sin(_t * 2.0 + id)
		_live.draw_colored_polygon(PackedVector2Array([s + Vector2(0, -h), s + Vector2(-w, -h * 0.45), s]), Color(c, a))
		_live.draw_colored_polygon(PackedVector2Array([s + Vector2(0, -h), s + Vector2(w, -h * 0.45), s]), Color(c, a * 0.55))

	for m in _motes:
		var p: Vector2 = m.p + Vector2(sin(_t * 0.6 + float(m.ph)) * 8.0, 0)
		_live.draw_circle(p, 2.5, Color(c, 0.45))

	# the moment the gate unlocks: Pale Jade, "look now"
	if _flash > 0.0:
		_live.draw_rect(get_viewport_rect(), Color(Game.PALE_JADE, _flash * 0.35))
