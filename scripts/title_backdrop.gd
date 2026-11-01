extends Control
## The title screen's backdrop: the jail at night, seen straight on. Cells I-IV
## flank the menu, two to a side, each with its boss's silhouette behind the
## bars and an eye blinking in the dark; gate V stands behind the buttons.
## Moonlight falls from a barred window high in the wall onto the lone
## prisoner, who stands with their back to us, facing the gate.
##
## Drawn in the palette like every room, so the ASCII pass laid over it turns
## it into the same glyph world as the game. The menu sits on top, untouched.

const P := preload("res://scripts/paint.gd")
const SEED := 11
const FLOOR := 0.72              # floor line, as a fraction of the height
const CELL_X := [0.085, 0.225, 0.775, 0.915]
const CELL := Vector2(190, 250)
const MOTES := 36

var _bricks: Array = []          # {r: Rect2, a: float}
var _motes: Array = []           # {p: Vector2 (0..1 across the beam), v, ph}
var _built := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in MOTES:
		_motes.append({"p": Vector2(rng.randf(), rng.randf()), "v": rng.randf_range(0.01, 0.03), "ph": rng.randf() * TAU})


func _process(delta: float) -> void:
	_t += delta
	for m in _motes:
		m.p.y = fmod(m.p.y + m.v * delta, 1.0)
	queue_redraw()


## Brick courses on the back wall, rebuilt when the screen changes shape.
func _build(s: Vector2) -> void:
	_built = s
	_bricks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var fy := s.y * FLOOR
	var y := 0.0
	var row := 0
	while y < fy:
		var x := -45.0 * (row % 2)
		while x < s.x:
			var w := rng.randf_range(70.0, 110.0)
			_bricks.append({"r": Rect2(x + 3, y + 3, w - 6, 30), "a": rng.randf_range(0.16, 0.32) * (0.45 + 0.55 * y / fy)})
			x += w
		y += 36.0
		row += 1


func _draw() -> void:
	var s := size
	if s != _built:
		_build(s)
	var c := Game.SAPPHIRE_CORE
	var fy := s.y * FLOOR
	var mid := s.x * 0.5

	draw_rect(Rect2(Vector2.ZERO, s), Game.DEEP_MOSS)
	# back wall, sinking into the dark towards the unseen ceiling
	for b in _bricks:
		draw_rect(b.r, Color(c, b.a))
	P.vband(self, Rect2(0, 0, s.x, fy * 0.45), 0.6, 0.0, Game.DEEP_MOSS)
	draw_rect(Rect2(0, fy - 14, s.x, 14), Color(c, 0.22))      # skirting
	draw_line(Vector2(0, fy), Vector2(s.x, fy), Color(c, 0.5), 3.0)

	# floor: flagstones running away to the gate
	P.vband(self, Rect2(0, fy, s.x, s.y - fy), 0.2, 0.08)
	var vanish := Vector2(mid, fy - 700.0)
	for i in range(-9, 10):
		var foot := Vector2(mid + i * 210.0, s.y)
		var top := vanish.lerp(foot, (fy - vanish.y) / (s.y - vanish.y))
		draw_line(top, foot, Color(c, 0.22), 3.0)
	var y := fy
	var step := 22.0
	while y < s.y:
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(c, 0.2), 3.0)
		y += step
		step *= 1.35

	# gate V behind the buttons: a deep arch, its portcullis down
	var gate := Rect2(mid - 230, fy - 300, 460, 300)
	draw_rect(gate.grow(14), Color(c, 0.3))
	draw_rect(gate, Game.DEEP_MOSS)
	draw_rect(gate, Color(Game.SHADOW, 0.45))
	var gx := gate.position.x + 14.0
	while gx < gate.end.x:
		draw_line(Vector2(gx, gate.position.y), Vector2(gx, gate.end.y), Color(c, 0.4), 6.0)
		gx += 30.0
	for gy in [gate.position.y + 40, gate.get_center().y + 30]:
		draw_line(Vector2(gate.position.x, gy), Vector2(gate.end.x, gy), Color(c, 0.4), 6.0)

	# the window, and the moonlight through it onto the prisoner
	var win := Rect2(mid - 60, 26, 120, 92)
	draw_rect(win.grow(10), Color(c, 0.3))
	draw_rect(win, Color(c, 0.4 + 0.04 * sin(_t * 0.7)))
	for k in 3:
		var bx := win.position.x + win.size.x * (k + 1) / 4.0
		draw_line(Vector2(bx, win.position.y), Vector2(bx, win.end.y), Game.DEEP_MOSS, 6.0)
	var who := Vector2(mid, s.y - 46.0)
	P.shaft(self, win.position + Vector2(0, win.size.y), win.end, who + Vector2(-190, 30), who + Vector2(190, 30), 0.34)
	for m in _motes:
		var a: Vector2 = win.get_center().lerp(who, m.p.y)
		var half := lerpf(win.size.x * 0.5, 190.0, m.p.y)
		var p := Vector2(a.x + (m.p.x - 0.5) * 2.0 * half, a.y) + Vector2(sin(_t * 0.8 + m.ph) * 8.0, 0)
		draw_circle(p, 2.5, Color(c, 0.5 * sin(PI * m.p.y) * (0.6 + 0.4 * sin(_t * 2.0 + m.ph))))

	# a well of shade behind the title so its letters stand clear
	P.glow(self, Vector2(mid, s.y * 0.3), 640.0, 0.55, 0.42, Game.SHADOW)

	# cells I-IV, two to each side, each watched from inside
	for i in 4:
		var cx: float = s.x * CELL_X[i]
		_cell(i + 1, Rect2(cx - CELL.x * 0.5, fy - CELL.y, CELL.x, CELL.y))
	# a torch between each pair, pooling light on the wall and floor
	for tx in [0.155, 0.845]:
		var tp := Vector2(s.x * tx, fy - 190.0)
		P.glow(self, tp, 190.0, 0.38)
		P.glow(self, Vector2(tp.x, fy + 40.0), 180.0, 0.26, 0.3)
		draw_rect(Rect2(tp + Vector2(-6, 4), Vector2(12, 34)), Color(c, 0.6))
		P.flame(self, tp, 26.0, _t, tx * 40.0)

	# the prisoner, back to us, sword low, in the moon's pool
	P.glow(self, who + Vector2(0, 6), 200.0, 0.3, 0.3)
	Game.shadow(self, who + Vector2(0, 4), 44.0)
	var r := 2.0
	var sway := sin(_t * 1.6) * 1.5
	draw_line(who + Vector2(9 * r, -18 * r), who + Vector2(30 * r, 6), Game.PALE_JADE, 4.0)
	draw_line(who + Vector2(-5 * r, -14 * r), who + Vector2(-5 * r, 0), c, 5.0 * r)
	draw_line(who + Vector2(5 * r, -14 * r), who + Vector2(5 * r, 0), c, 5.0 * r)
	draw_line(who + Vector2(0, -32 * r + sway), who + Vector2(0, -16 * r), c, 16.0 * r)
	draw_circle(who + Vector2(0, -32 * r + sway), 8.0 * r, c)
	draw_circle(who + Vector2(0, -16 * r), 8.0 * r, c)
	draw_circle(who + Vector2(0, -41 * r + sway), 6.5 * r, c)

	P.web(self, Vector2.ZERO, 90.0, Vector2(1, 1))
	P.web(self, Vector2(s.x, 0), 90.0, Vector2(-1, 1))
	P.vignette(self, s, 160.0, 0.6)


func _cell(id: int, r: Rect2) -> void:
	var c := Game.SAPPHIRE_CORE
	draw_rect(r.grow(10), Color(c, 0.34))
	draw_rect(r, Game.DEEP_MOSS)
	draw_rect(r, Color(Game.SHADOW, 0.35))
	P.emblem(self, id, Vector2(r.get_center().x, r.end.y - 60.0), Color(c, 0.7))
	# its eye, slowly brightening and blinking, out of step with its neighbours
	var e := Vector2(r.get_center().x, r.position.y + 58.0)
	var lit := 0.5 + 0.5 * sin(_t * 0.9 + id * 1.9)
	var blink := 1.0 if fmod(_t + id * 1.37, 4.3) > 0.18 else 0.15
	draw_colored_polygon(P._diamond(e, 9.0 + 3.0 * lit, (11.0 + 3.0 * lit) * blink), Game.DEEP_MOSS.lerp(c, 0.4 + 0.6 * lit))
	var x := r.position.x + 9.0
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(c, 0.6), 5.0)
		x += 18.0
	draw_line(Vector2(r.position.x, r.position.y + 10), Vector2(r.end.x, r.position.y + 10), Color(c, 0.6), 5.0)
	draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(c, 0.6), 5.0)
