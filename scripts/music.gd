extends Node
## Music: one track at a time from res://media/music/, crossfaded on change.
## The loops (title, jail, boss, final) are cut by tools/make_music_loops.py
## to their exact musical length with their ring-out folded onto the start,
## so they repeat whole without a seam; the ending plays once.
##
## Asking for the track that's already playing does nothing, so moving
## between screens that share music (the jail and its pause menu) never
## restarts it. Keeps playing while the game is paused.

const DIR := "res://media/music/"
const LOOPS := ["title", "jail", "boss", "final"]
const DB := -4.0
const FADE := 1.2

var current := ""

var _players: Array[AudioStreamPlayer] = []
var _on := 0                     # which player holds the current track
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


## Crossfade to `name` (title, jail, boss, final, ending).
func play(name: String, fade := FADE) -> void:
	if name == current:
		return
	var s: AudioStreamWAV = load(DIR + name + ".wav")
	if s == null:
		return
	if name in LOOPS:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	current = name
	var old := _players[_on]
	_on = 1 - _on
	var p := _players[_on]
	p.stream = s
	p.volume_db = -60.0
	p.play()
	_fade(old, p, fade)


## Seconds into the current track (what the ending's animation runs on), or
## -1 when nothing is playing.
func position() -> float:
	var p := _players[_on]
	if current == "" or not p.playing:
		return -1.0
	return p.get_playback_position() + AudioServer.get_time_since_last_mix()


## Jump the current track to `at` seconds.
func seek(at: float) -> void:
	if current != "":
		_players[_on].seek(at)


## Fade the music out.
func stop(fade := FADE) -> void:
	current = ""
	_fade(_players[_on], null, fade)


func _fade(out: AudioStreamPlayer, into: AudioStreamPlayer, fade: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if out.playing:
		_tween.tween_property(out, "volume_db", -60.0, fade)
	if into:
		_tween.tween_property(into, "volume_db", DB, fade * 0.6)
	_tween.chain().tween_callback(func():
		if out != _players[_on] or into == null:
			out.stop())
