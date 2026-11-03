extends Control
## Dialogue: a framed box at the foot of the screen that types out lines one
## letter at a time. A line is [who, mood, text] (see scripts/story.gd); an
## empty `who` is the player's own thought, drawn without a name tag.
##
## The mood carries the feeling through everything the box can do at once:
##   type speed and the pauses after punctuation (an ellipsis drags),
##   the voice blip's pitch and how often it sounds,
##   a haptic tick under the blips and a felt beat as the line opens,
##   the letters' motion (anger shakes, fear trembles, sorrow sinks and
##   sways, a whisper drifts in faint) and the box's (anger jolts it, resolve
##   draws the frame heavier and flares it once).
## Pale Jade is never used: a dialogue box must not read as a telegraph.
##
## Tap anywhere, or press light attack / dodge / accept: the first press
## finishes the line, the next one moves on. `finished` fires after the last.
##
##   dlg.play(Story.MEET)
##   await dlg.finished

signal finished
signal line_started(who: String, mood: String)

const UI := preload("res://scripts/ui/ui.gd")

const BOX_W := 1180.0
const BOX_H := 196.0
const BOTTOM := 40.0             # above the safe area's foot
const PAD := Vector2(48, 44)
const PX := 30                   # body text size
const LINE_GAP := 10.0
const GRACE := 0.18              # a press this soon after a line opens is ignored
const POP := 0.09                # each letter rises into place over this long

## Each speaker's voice: the blip it types with and how high it sits.
const VOICES := {
	"": {"sfx": "talk_you", "pitch": 1.0, "db": -6.0},
	"YOU": {"sfx": "talk_you", "pitch": 1.0, "db": 0.0},
	"???": {"sfx": "talk_knight", "pitch": 1.0, "db": 0.0},
	"FALLEN KNIGHT": {"sfx": "talk_knight", "pitch": 1.0, "db": 0.0},
}

## cps: letters a second. every: a blip every n letters. pitch: on top of the
## voice's. shake / tremble / wave / sink: letter motion in units. alpha: text
## strength. jolt: box knock as the line opens. frame: outline width.
## onset: the haptic + sound that open the line ("" for none).
const MOODS := {
	"calm": {"cps": 40.0, "every": 2, "pitch": 1.0, "shake": 0.0, "tremble": 0.0, "wave": 0.0, "sink": 0.0, "alpha": 1.0, "jolt": 0.0, "frame": 2.0, "onset": ""},
	"sad": {"cps": 22.0, "every": 3, "pitch": 0.85, "shake": 0.0, "tremble": 0.0, "wave": 1.6, "sink": 4.0, "alpha": 0.8, "jolt": 0.0, "frame": 2.0, "onset": "mood_sad"},
	"fear": {"cps": 50.0, "every": 1, "pitch": 1.14, "shake": 0.0, "tremble": 1.6, "wave": 0.0, "sink": 0.0, "alpha": 1.0, "jolt": 0.25, "frame": 2.0, "onset": "mood_fear"},
	"anger": {"cps": 58.0, "every": 1, "pitch": 0.9, "shake": 2.6, "tremble": 0.0, "wave": 0.0, "sink": 0.0, "alpha": 1.0, "jolt": 1.0, "frame": 3.0, "onset": "mood_anger"},
	"resolve": {"cps": 32.0, "every": 2, "pitch": 0.97, "shake": 0.0, "tremble": 0.0, "wave": 0.0, "sink": 0.0, "alpha": 1.0, "jolt": 0.0, "frame": 4.0, "onset": "mood_resolve"},
	"whisper": {"cps": 24.0, "every": 4, "pitch": 1.2, "shake": 0.0, "tremble": 0.0, "wave": 0.6, "sink": 0.0, "alpha": 0.55, "jolt": 0.0, "frame": 2.0, "onset": ""},
}
## Extra wait after a letter, seconds.
const PAUSES := {",": 0.14, ";": 0.18, ".": 0.32, "!": 0.32, "?": 0.32, "—": 0.24}

var playing := false

var _lines: Array = []
var _i := -1
var _glyphs: Array = []          # {ch, at: Vector2, born: float} for the line on screen
var _shown := 0                  # letters revealed so far
var _due := 0.0                  # when the next letter is due, on _clock
var _clock := 0.0                # real seconds since the line opened
var _blips := 0
var _mood: Dictionary = MOODS["calm"]
var _mood_name := "calm"
var _voice: Dictionary = VOICES[""]
var _who := ""
var _jolt := 0.0                 # 1 -> 0 knock on the box
var _flare := 0.0                # 1 -> 0 frame flare (resolve)
var _show := 0.0                 # 0 hidden .. 1 up, the box's rise and fade
var _last_ms := 0
var _tw: Tween                   # the box's rise or fall; a new one replaces it


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func play(lines: Array) -> void:
	_lines = lines
	_i = -1
	playing = true
	show()
	_last_ms = Time.get_ticks_msec()
	# a conversation straight after another: the last one's fall must not
	# finish and hide this one
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "_show", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_next()


## A press: finish the line typing out, else go on to the next one.
func advance() -> void:
	if not playing or _clock < GRACE:
		return
	if _shown < _glyphs.size():
		for g in range(_shown, _glyphs.size()):
			_glyphs[g].born = _clock
		_shown = _glyphs.size()
		Haptics.play("select")
		return
	Haptics.play("select")
	Sfx.play("select")
	_next()


func _next() -> void:
	_i += 1
	if _i >= _lines.size():
		_close()
		return
	var line: Array = _lines[_i]
	_who = line[0]
	_mood_name = line[1]
	_mood = MOODS[_mood_name]
	_voice = VOICES.get(_who, VOICES["???"])
	_layout(line[2])
	_shown = 0
	_due = 0.05
	_clock = 0.0
	_blips = 0
	_jolt = _mood.jolt
	_flare = 1.0 if _mood.frame > 2.0 else 0.0
	if _mood.onset != "":
		Haptics.play(_mood.onset)
		Sfx.play(_mood.onset, 0.0, 0.0)
	line_started.emit(_who, line[1])


func _close() -> void:
	playing = false
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "_show", 0.0, 0.15).set_ease(Tween.EASE_IN)
	_tw.tween_callback(hide)
	finished.emit()


## Word-wraps `text` into the box and gives every letter its place.
func _layout(text: String) -> void:
	_glyphs.clear()
	var f := UI.font(PX, 400)
	var adv := f.get_char_size("M".unicode_at(0), PX).x      # Plex Mono: every letter the same width
	var width := BOX_W - PAD.x * 2.0
	var line_h := UI.text_height(PX, 400) + LINE_GAP
	var x := 0.0
	var y := 0.0
	for word in text.split(" "):
		var w := word.length() * adv
		if x > 0.0 and x + w > width:
			x = 0.0
			y += line_h
		for ch in word:
			_glyphs.append({"ch": ch, "at": Vector2(x, y), "born": INF})
			x += adv
		_glyphs.append({"ch": " ", "at": Vector2(x, y), "born": INF})
		x += adv
	_glyphs.pop_back()


func _input(event: InputEvent) -> void:
	if not playing:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or event.is_action_pressed("attack_light") or event.is_action_pressed("dodge") or event.is_action_pressed("ui_accept")
	if pressed:
		get_viewport().set_input_as_handled()
		advance()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# real time, so hit-stop and slow-mo don't slow the typing; capped so
	# coming back from the pause sheet doesn't spill a whole line at once
	var dt := minf((now - _last_ms) / 1000.0, 0.1)
	_last_ms = now
	if not visible:
		return
	_jolt = maxf(0.0, _jolt - dt / 0.35)
	_flare = maxf(0.0, _flare - dt / 0.6)
	if playing:
		_clock += dt
		while _shown < _glyphs.size() and _clock >= _due:
			_reveal()
	queue_redraw()


func _reveal() -> void:
	var g: Dictionary = _glyphs[_shown]
	g.born = _clock
	_shown += 1
	_due += 1.0 / _mood.cps + float(PAUSES.get(g.ch, 0.0))
	if g.ch == " ":
		return
	_blips += 1
	if (_blips - 1) % int(_mood.every) == 0:
		Sfx.play(_voice.sfx, _voice.db + (-10.0 if _mood_name == "whisper" else 0.0), 0.05, _voice.pitch * _mood.pitch)
		Haptics.play("talk_hard" if _mood.shake > 0.0 else "talk")


func _draw() -> void:
	if _show <= 0.0:
		return
	var safe := UI.safe(self)
	var e := _show
	var w := minf(BOX_W, safe.size.x - 32.0)
	var at := Vector2(safe.get_center().x - w * 0.5, safe.end.y - BOTTOM - BOX_H + 24.0 * (1.0 - e))
	# the knock: a quick decaying shove sideways, and fear's steady shiver
	var j := _jolt * _jolt
	at += Vector2(sin(_clock * 70.0) * 14.0 * j, cos(_clock * 55.0) * 5.0 * j)
	if _mood.tremble > 0.0:
		at += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _mood.tremble * 0.6
	var r := Rect2(at, Vector2(w, BOX_H))
	var a := e
	draw_rect(r, Color(UI.MOSS, 0.92 * a))
	var frame_w: float = _mood.frame + 3.0 * _flare
	draw_rect(r, Color(UI.CORE, a), false, frame_w)
	var tick := UI.TICK + 6.0 * _flare
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		draw_rect(Rect2(c - Vector2(tick, tick) * 0.5, Vector2(tick, tick)), Color(UI.CORE, a))

	# name tag on the top edge, filled Core with Moss letters, like the carry chip
	if _who != "":
		var tw := UI.text_width(_who, 20, 600, 0.15)
		var tag := Rect2(r.position + Vector2(PAD.x - 16.0, -22.0), Vector2(tw + 32.0, 44.0))
		draw_rect(tag, Color(UI.CORE, a))
		UI.text(self, tag.position + Vector2(16.0, (44.0 - UI.text_height(20)) * 0.5), _who, 20, Color(UI.MOSS, a), 600, 0.15)

	# the letters: each rises into place as it appears, then moves with the mood
	var f := UI.font(PX, 400)
	var origin := r.position + PAD + Vector2(0, f.get_ascent(PX) - 8.0)
	var thought := _who == ""
	for i in _shown:
		var g: Dictionary = _glyphs[i]
		if g.ch == " ":
			continue
		var age: float = _clock - float(g.born)
		var k := clampf(age / POP, 0.0, 1.0)
		var off := Vector2(0, 8.0 * (1.0 - k))
		if _mood.shake > 0.0:
			off += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _mood.shake
		if _mood.tremble > 0.0:
			off.x += sin(_clock * 48.0 + i * 1.7) * _mood.tremble
		if _mood.wave > 0.0:
			off.y += sin(_clock * 2.4 - i * 0.35) * _mood.wave
		if _mood.sink > 0.0:
			off.y += _mood.sink * clampf(age / 1.5, 0.0, 1.0)     # the words settle lower as they hang there
		var col := Color(UI.CORE, a * k * _mood.alpha * (0.78 if thought else 1.0))
		draw_char(f, origin + g.at + off, g.ch, PX, col)

	# done typing: a diamond bobbing in the corner says "tap to go on"
	if playing and _shown >= _glyphs.size():
		var bob := sin(_clock * 5.0) * 4.0
		UI.diamond(self, r.end - Vector2(40.0, 34.0 - bob), 16.0, Color(UI.CORE, a))
