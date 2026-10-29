extends Node
## Sfx: every sound effect, by name, from res://media/sfx/<name>.wav. The
## files are synthesised by tools/make_sfx.py; most names match a haptic
## pattern in haptics.gd and hit on the same beats.
##
## A name with no file plays nothing, so a moment can be wired before its
## sound exists (the foley ones: sand, books, the gate). Each play is nudged a
## few percent in pitch so a repeated hit never sounds copy-pasted.
##
## Layers: <name>.<layer>.wav plays together with <name>, so a recorded layer
## (glass under boss_death, a body fall under death) sits on a synthesised
## sound without touching either. Sources and licences: media/sfx/CREDITS.md.
##
## Ambience: one looping amb_<place>.wav at a time, crossfaded on change.
## Loops (amb_*, *_loop) are cut by tools/make_foley.py with their seam
## already crossfaded, and set to loop here; loop() holds any other one on.

const DIR := "res://media/sfx/"
const VOICES := 16
const AMB_DB := -14.0
const AMB_FADE := 1.2

var last := ""                   # the last sound asked for, for checks

var _streams := {}               # name -> [stream, layer streams...]
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _amb: AudioStreamPlayer
var _amb_name := ""
var _loops := {}                 # name -> AudioStreamPlayer held on by loop()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # the pause menu has sounds too
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".wav"):
			var s: AudioStreamWAV = load(DIR + f)
			var key := f.get_slice(".", 0)
			if key.begins_with("amb_") or key.ends_with("_loop"):
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = int(s.get_length() * s.mix_rate)
			if not _streams.has(key):
				_streams[key] = []
			# the bare name first, its layers after
			if f.get_slice_count(".") == 2:
				_streams[key].push_front(s)
			else:
				_streams[key].append(s)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_amb = AudioStreamPlayer.new()
	add_child(_amb)


func play(name: String, db := 0.0, vary := 0.04) -> void:
	last = name
	var pitch := randf_range(1.0 - vary, 1.0 + vary)
	for s in _streams.get(name, []):
		var p := _voice()
		p.stream = s
		p.volume_db = db
		p.pitch_scale = pitch
		p.play()


## A generic thump for impacts with no sound of their own (most boss attacks
## land through the camera shake), 0..1, quieter as it gets lighter.
func impact(strength: float) -> void:
	if strength < 0.3:
		return
	play("impact", linear_to_db(minf(strength, 1.0)))


## Fades to amb_<place>, or to silence when there is no such file.
func ambience(place: String) -> void:
	var name := "amb_" + place
	if name == _amb_name:
		return
	_amb_name = name
	var s: Array = _streams.get(name, [])
	if not _amb.playing and s.is_empty():
		return
	var tw := create_tween()
	if _amb.playing:
		tw.tween_property(_amb, "volume_db", -60.0, AMB_FADE)
		tw.tween_callback(_amb.stop)
	if s.is_empty():
		return
	tw.tween_callback(func():
		_amb.stream = s[0]
		_amb.volume_db = -60.0
		_amb.play())
	tw.tween_property(_amb, "volume_db", AMB_DB, AMB_FADE)


## Holds a looping sound on (the dropped sapphire's hum) until turned off.
func loop(name: String, on := true, db := 0.0) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if not on:
		if p:
			_loops.erase(name)
			var tw := p.create_tween()
			tw.tween_property(p, "volume_db", -60.0, 0.4)
			tw.tween_callback(p.queue_free)
		return
	var s: Array = _streams.get(name, [])
	if p or s.is_empty():
		return
	p = AudioStreamPlayer.new()
	p.stream = s[0]
	p.volume_db = db
	add_child(p)
	p.play()
	_loops[name] = p


## A free voice, else the one that started longest ago.
func _voice() -> AudioStreamPlayer:
	for i in VOICES:
		var p := _voices[(_next + i) % VOICES]
		if not p.playing:
			_next = (_next + i + 1) % VOICES
			return p
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	return p
