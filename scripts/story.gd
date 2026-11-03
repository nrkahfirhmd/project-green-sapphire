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
##
## The wardens, as feelings: the Turnkey is guardedness, the Pendulum
## regret, the Prism anger, the Hourglass anxiety. The Mirror is the self.

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

# --- 7-9. Each warden's first words (main.gd, once per cell) ---------------
const WARDENS := {
	1: [
		["THE TURNKEY", "calm", "Turn back. Everything in here stays locked."],
		["YOU", "calm", "I only want the sapphire."],
		["THE TURNKEY", "fear", "That's what they all say. Then they take the rest."],
		["THE TURNKEY", "anger", "Nothing gets in. Nothing gets out. Not again."],
		["", "resolve", "Then I'll pick the lock."],
	],
	2: [
		["THE PENDULUM", "sad", "Back... and forth. Back... and forth."],
		["THE PENDULUM", "sad", "Every page in here is something you should have done differently."],
		["YOU", "fear", "I don't remember any of them."],
		["THE PENDULUM", "whisper", "You will. I swing until you do."],
		["", "resolve", "Then I'll stop the swing."],
	],
	3: [
		["THE PRISM", "anger", "Finally. Something to break."],
		["YOU", "fear", "I didn't come here to fight you."],
		["THE PRISM", "anger", "Everyone fights me. I'm what you hit when nothing else will hold still."],
		["THE PRISM", "calm", "No tricks. No shield. Just you and me."],
		["", "resolve", "Head on, then."],
	],
	4: [
		["THE HOURGLASS", "fear", "You're late. You're already late. Can you hear it running out?"],
		["YOU", "fear", "Running out of what?"],
		["THE HOURGLASS", "fear", "Everything! Every grain is something that could go wrong!"],
		["THE HOURGLASS", "anger", "And when the top runs dry... time's up."],
		["", "resolve", "Breathe. One cut at a time."],
	],
	5: [
		["", "whisper", "The last door. He said it wore his face."],
		["THE MIRROR", "calm", "Hello again."],
		["YOU", "fear", "...That's my face."],
		["THE MIRROR", "sad", "It was his, too. He stood where you stand, and he lost."],
		["THE MIRROR", "anger", "Every warden was a piece of you. I am all of them at once."],
		["", "resolve", "Then I end this. And I wake up."],
	],
}
