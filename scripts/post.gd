extends Node
## Post effects on the ASCII pass. They live here, not in a scene, so a
## dissolve can run across a scene change; every frame the state is pushed to
## each ASCII pass on screen (group "ascii"). All of them work on which glyph a
## cell shows, never on colour: see the uniforms at the top of ascii.gdshader.
##
##   shock(at)      a ring of glyph density running out from a world point
##   scramble(at)   cells round a world point flicker through random glyphs
##   dissolve(to)   every cell thins down the ramp to nothing (1) or back (0)
##   low health     the screen edges breathe into the shadow green, read off
##                  the player each frame
##   phosphor       bright glyphs linger a few frames, always on

const SHOCK_TIME := 0.75
const HIT_TIME := 0.18
# How much of last frame's bright glyphs each frame keeps; 0 turns phosphor
# off. It reads the whole screen back once a frame: the one effect with a real
# cost, so it is the first to cut if a phone struggles.
const GLOW := 0.55

var fade := 0.0
var _shock_at := Vector2(0.5, 0.5)
var _shock_t := 1.0
var _shock_r := 0.7
var _hit_at := Vector2(0.5, 0.5)
var _hit_k := 0.0
var _hit_r := 0.13
var _pulse := 0.0
var _t := 0.0
var _trail: SubViewport          # holds last frame's finished screen for the phosphor
var _copy: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The screen can't read itself while drawing, so a small viewport copies
	# the finished frame; it draws first next frame, while the screen is free.
	_trail = SubViewport.new()
	_trail.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_copy = TextureRect.new()
	_copy.texture = get_viewport().get_texture()
	_copy.stretch_mode = TextureRect.STRETCH_SCALE
	_trail.add_child(_copy)
	add_child(_trail)


## `size` is the ring's final radius, in screen heights.
func shock(at: Vector2, size := 0.7) -> void:
	_shock_at = _uv(at)
	_shock_t = 0.0
	_shock_r = size


## `radius` in screen heights; `k` 0..1, how many of the cells flicker.
func scramble(at: Vector2, radius := 0.13, k := 1.0) -> void:
	_hit_at = _uv(at)
	_hit_r = radius
	_hit_k = maxf(_hit_k, k)


## Runs in real time, through hit-stops and pauses.
func dissolve(to: float, time: float) -> void:
	var tw := create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "fade", to, time)
	await tw.finished


func _uv(world: Vector2) -> Vector2:
	var vp := get_viewport()
	return (vp.get_canvas_transform() * world) / vp.get_visible_rect().size


func _process(delta: float) -> void:
	# shock and scramble run on game time, so a hit-stop holds them mid-flight
	_shock_t = minf(1.0, _shock_t + delta / SHOCK_TIME)
	_hit_k = maxf(0.0, _hit_k - delta / HIT_TIME)
	var real := delta / Engine.time_scale if Engine.time_scale > 0.0 else 0.0
	_t += real

	# low health: a slow breath at 2 hp, a quicker, deeper one at the last
	var want := 0.0
	var rate := 0.7
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl.hp > 0 and pl.hp <= 2:
		want = 1.0 if pl.hp == 1 else 0.45
		rate = 1.2 if pl.hp == 1 else 0.7
	_pulse = move_toward(_pulse, want, real * 2.0)

	var px := Vector2i(get_viewport().get_texture().get_size())
	if _trail.size != px:
		_trail.size = px
		_copy.size = Vector2(px)

	for n in get_tree().get_nodes_in_group("ascii"):
		var m: ShaderMaterial = n.material
		if not m.has_meta("post"):
			m.set_meta("post", true)
			m.set_shader_parameter("prev_tex", _trail.get_texture())
		m.set_shader_parameter("shock_at", _shock_at)
		m.set_shader_parameter("shock_t", _shock_t)
		m.set_shader_parameter("shock_r", _shock_r)
		m.set_shader_parameter("hit_at", _hit_at)
		m.set_shader_parameter("hit_k", _hit_k)
		m.set_shader_parameter("hit_r", _hit_r)
		m.set_shader_parameter("fade", fade)
		m.set_shader_parameter("pulse", _pulse * (0.55 + 0.45 * sin(_t * rate * TAU)))
		m.set_shader_parameter("glow_k", GLOW)
