extends Node
## Haptics: every moment in the game that should be felt has a named pattern
## here. A pattern is a list of pulses [start ms, length ms, strength 0..1],
## played on the phone's Taptic Engine (Input.vibrate_handheld) and on any
## connected gamepad's rumble.
##
## The language, light to heavy:
##   ticks (6-12 ms, 0.2-0.4)   UI, selection, a swing that whiffs, "ready"
##   taps  (14-25 ms, 0.5-0.9)  a hit landing, a bounce, a slash
##   thuds (40-90 ms, 0.8-1.0)  a heavy hit, being hurt, a sapphire set down
##   rumbles (>120 ms)          deaths, the gate, a boss changing phase
## Rhythm carries meaning too: rising taps build (charge, pickup, phase), two
## quick ticks say "no" (blocked, on cooldown), a lub-dub is low health.
##
## Several things often happen in one frame (a heavy hit also shakes the
## camera), so a pulse is skipped while a stronger one is still playing.
## Off when Game.haptic_enabled is false.

const PATTERNS := {
	# interface
	"select": [[0, 6, 0.2]],
	"tap": [[0, 10, 0.35]],
	"toggle": [[0, 12, 0.5]],
	"denied": [[0, 10, 0.4], [70, 10, 0.4]],
	"door": [[0, 25, 0.6]],
	"intro": [[0, 50, 0.8]],
	# the player's rapier
	"swing_light": [[0, 8, 0.25]],
	"swing_heavy": [[0, 8, 0.2], [90, 8, 0.35], [180, 10, 0.5]],   # ticks rising through the windup
	"hit_light": [[0, 18, 0.6]],
	"hit_heavy": [[0, 45, 1.0], [60, 30, 0.5]],
	"blocked": [[0, 8, 0.5], [45, 8, 0.3]],                        # a clink off a shield
	# movement and abilities
	"dodge": [[0, 14, 0.35]],
	"aim": [[0, 6, 0.25]],
	"ricochet": [[0, 35, 0.75]],
	"bounce": [[0, 15, 0.55]],
	"pierce": [[0, 25, 0.85]],
	"blink": [[0, 8, 0.3], [60, 35, 0.9]],                         # gone, then arrived
	"ult_start": [[0, 60, 0.5], [80, 20, 0.7]],
	"ult_slash": [[0, 22, 0.9]],
	"ult_end": [[0, 90, 1.0], [110, 60, 0.4]],
	"ult_ready": [[0, 15, 0.5], [120, 15, 0.8]],
	"ready": [[0, 8, 0.25]],
	# the player hurt
	"hurt": [[0, 80, 1.0], [110, 50, 0.5]],
	"heartbeat": [[0, 25, 0.45], [180, 20, 0.3]],
	"death": [[0, 200, 1.0], [230, 160, 0.6], [420, 140, 0.3]],
	# the boss
	"telegraph": [[0, 12, 0.3]],
	"phase": [[0, 40, 0.5], [120, 40, 0.75], [240, 80, 1.0]],
	"boss_death": [[0, 120, 1.0], [160, 80, 0.7], [300, 80, 0.7], [460, 250, 0.9]],
	# sapphires and the jail
	"crystal_land": [[0, 30, 0.6], [180, 15, 0.3]],
	"pickup": [[0, 10, 0.3], [60, 10, 0.5], [120, 10, 0.7], [180, 40, 1.0]],
	"place": [[0, 50, 0.9], [90, 15, 0.4]],
	"gate": [[0, 400, 0.35], [450, 400, 0.45], [900, 300, 0.6], [1250, 120, 1.0]],
	"win": [[0, 30, 0.6], [120, 30, 0.8], [240, 90, 1.0]],
	"lose": [[0, 250, 0.5]],
}

## Checks swap this for a recorder: sink.call(length_ms, strength).
var sink := Callable()
var last := ""                   # the last pattern asked for, for checks

var _until := 0                  # when the pulse playing now ends, ms
var _amp := 0.0                  # and how strong it is


func play(name: String) -> void:
	last = name
	if not Game.haptic_enabled:
		return
	for p in PATTERNS[name]:
		if p[0] == 0:
			_pulse(p[1], p[2])
		else:
			# real time, and through hit-stop and the pause menu
			get_tree().create_timer(p[0] / 1000.0, true, false, true).timeout.connect(_pulse.bind(p[1], p[2]))


## A generic jolt for impacts with no pattern of their own (most boss attacks
## land through the camera shake), 0..1.
func impact(strength: float) -> void:
	if strength < 0.15 or not Game.haptic_enabled:
		return
	strength = minf(strength, 1.0)
	_pulse(roundi(15.0 + 45.0 * strength), 0.3 + 0.6 * strength)


func _pulse(ms: int, amp: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _until and amp <= _amp:
		return                       # something stronger is still playing
	_until = now + ms
	_amp = amp
	if sink.is_valid():
		sink.call(ms, amp)
		return
	Input.vibrate_handheld(ms, amp)
	for j in Input.get_connected_joypads():
		Input.start_joy_vibration(j, amp * 0.6, amp, ms / 1000.0)
