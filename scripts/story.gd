extends RefCounted
## Every line of dialogue in the game, in story order. A line is
## [who, mood, text]:
##   who   "" is the player's own thought (no name tag); "YOU" is the player
##         speaking aloud; "???" / "FALLEN KNIGHT" is the knight.
##   mood  calm, sad, fear, anger, resolve, whisper (scripts/ui/dialogue.gd
##         says what each one does to the box, the voice and the haptics).
##
## The lore under it, never said outright: it is all the player's own mind,
## each warden one of their feelings, and the fallen knight is the player
## from the other dream, the one where they died and failed.


# --- 1. A dark room --------------------------------------------------
const WAKE := [
	["", "whisper", "..."],
	["", "fear", "Cold. Stone under my hands."],
	["", "fear", "Where... am I?"],
]

# --- 2. The fallen knight tells you where you are ----------------------
const MEET := [
	["???", "sad", "Another one wakes."],
	["YOU", "fear", "Who's there?"],
	["???", "calm", "Easy. Your eyes will learn the dark. Mine did, once."],
	["???", "sad", "Call me what I am. A knight who fell."],
	["FALLEN KNIGHT", "calm", "This is the jail of five cells. Four wardens keep four of them."],
	["FALLEN KNIGHT", "calm", "The fifth door... you'll see the fifth door."],
	["YOU", "fear", "A jail? I didn't do anything!"],
	["FALLEN KNIGHT", "sad", "No one here did. That's never why you're kept."],
	["FALLEN KNIGHT", "resolve", "There's a sword at your side. If you mean to leave, learn to hold it."],
]

# --- 3. He teaches you, then fights you (tutorial) -----------------------
## One beat before each control; scripts/prologue.gd shows the prompt after.
const TUTORIAL := {
	"move": [["FALLEN KNIGHT", "calm", "Walk. Get a feel for the floor."]],
	"attack_light": [["FALLEN KNIGHT", "calm", "Quick cuts first. Strike at nothing, three times."]],
	"attack_heavy": [["FALLEN KNIGHT", "calm", "Now put your weight behind it. Slow, but it carries."]],
	"dodge": [["FALLEN KNIGHT", "calm", "When something comes for you, don't stand there. Roll."]],
	"blink": [["FALLEN KNIGHT", "calm", "You can cut through the space between, too. Blink."]],
	"ricochet": [["FALLEN KNIGHT", "calm", "Draw back... aim... let go. Let the walls throw you."]],
}

const FIGHT := [
	["FALLEN KNIGHT", "sad", "You learn fast. I did too."],
	["FALLEN KNIGHT", "anger", "Now show me. I won't go easy. They won't."],
	["YOU", "fear", "Wait—"],
]

## Mid-fight, the first time the ultimate is charged.
const ULTIMATE := [
	["FALLEN KNIGHT", "resolve", "Feel that? Every blow you've landed, gathered. Let it out."],
]

# --- 4. You win; he tells you the way out --------------------------------
const DEFEATED := [
	["FALLEN KNIGHT", "sad", "...Enough. You're stronger than I was."],
	["YOU", "calm", "Than you were?"],
	["FALLEN KNIGHT", "sad", "I tried to leave, too. I got as far as the last door."],
	["FALLEN KNIGHT", "whisper", "What waited behind it wore my face."],
	["FALLEN KNIGHT", "resolve", "Listen. Each warden holds a sapphire. Take all four and set them on the altar."],
	["FALLEN KNIGHT", "resolve", "The great gate will open. Then escape. Do what I couldn't."],
	["YOU", "fear", "Wait, who are you?"],
	["FALLEN KNIGHT", "whisper", "Wake up."],
]

# --- 5-6. You wake a second time, in the jail ------------------------------
const JAIL_WAKE := [
	["", "whisper", "..."],
	["", "fear", "Bars. Stone. A jail, just like he said."],
	["", "sad", "So it wasn't a dream. Or it was, and this is one too."],
	["", "resolve", "Four cells. Four sapphires. One gate."],
	["", "resolve", "I know what I have to do."],
]

