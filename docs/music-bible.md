# Green Sapphire — Music Bible

The score for the jail, the five keepers, and the stone they hold.
The MIDI sketches are made by `tools/make_music.py`: music in `media/music/midi/`, stings in `media/sfx/midi/` (see §4).

---

## 1. The idea

The screen has three greens and nothing else. The music provides the colour the screen
holds back. Every room is drawn in the same glyphs, so the score is what tells you where you are:
- a vault that swings
- a library that waltzes
- a cave that refracts
- a desert that counts down
- a mind that answers you with your own melody

**One stone, one motif.** The Green Sapphire is a five-note idea, and it is everywhere.
- It plays as a piano lullaby in the jail.
- It plays inside each keeper's theme, disguised in that room's dialect.
- The Mirror plays it upside down.
- When the stone is whole, it plays right side up in a major key for the first time.

Players should be able to hum it after one fight and recognise it in the last.

### What we take from the masters

| Franchise | What we borrow | Where it lives |
|---|---|---|
| **Kingdom Hearts** (Shimomura) | A solo piano holds the soul of the game; a lullaby that later becomes a battle cry | Title, jail, ending |
| **Persona** (Meguro) | Genre-forward fights: acid jazz, slap bass, brass stabs, a groove you play *to* | The Turnkey |
| **Trails** (Falcom Sound Team jdk) | Violin over a rock rhythm section; motifs that come back years later; key changes that lift at the climax | The Pendulum, the Mirror |
| **Tales of** (Sakuraba) | Progressive orchestral rock, odd meters, organ and choir, relentless forward motion | The Prism, the Mirror |
| **Trails / Tales desert themes** | Phrygian dominant, hand drums, plucked lutes, a pulse that tightens | The Hourglass |

### Pillars

1. **The fight is a dance.** Boss themes are tempo-locked and phrase-regular (8- and 16-bar
   blocks), so a player's rhythm settles into the music's. Telegraph windups land within one beat of a
   downbeat wherever the tempo allows (see §6.4).
2. **Phases are chapters.** Every phase of a fight has its own music section and changes on the next
   bar line, never mid-phrase. The player always *hears* the fight escalate.
3. **The motif carries the story.** No cue is "just a loop". Each one says something about the
   Green Sapphire.
4. **Leave room for the swordsman.** Telegraph sounds, hits and the heartbeat sit in 1–4 kHz. Arrangements
   keep that band light during attacks: no shrill leads over windups, and pads stay below 1 kHz or above 6 kHz.
5. **Small and seamless.** Every loop is sample-accurate, the whole score fits a mobile budget,
   and nothing pops at a loop point.

---

## 2. Leitmotifs

Written in E minor, the home key of the stone. The sound effects already agree: the pickup and win
jingles are in E major.

### 2.1 The Green Sapphire (S)

```
  E4  B4  D5 | E5 . F#5 G5 | F#5 . D5 . | B4 - - -
  1   5   b7 | 8    9   b3' | 9    b7    | 5
```
- **Why it works:** a rising fifth opens the stone up, the flat seventh and octave make it ancient, and the
  climb to G5 then the fall back to B4 is a sigh. The last note sits on the fifth, so the phrase is unresolved
  until the ending.
- **Answer (S′):** `G5 F#5 E5 D5 | E5 - - -`. This resolves it, and the score holds it back until the final cue.
- **Inversion (S⁻¹), the Mirror's voice:** `E5 A4 F#4 | E4 . D4 C#4 | D4 . F#4 . | A4 - - -`.
  It is the exact chromatic mirror of S, so its C♯ lends it a Dorian, A-major glow S never has.
- **Major form (S+), the ending:** the same contour in E major (D♯, G♯), first heard when the stone is whole.

### 2.2 The keepers' cells

Each keeper has a two-to-four-note cell. Each one is quoted in the keeper's own theme and again in the Mirror's.

| Keeper | Cell | Idea |
|---|---|---|
| The Turnkey | `G A♭ A … D` (three chromatic clicks up, then a drop) | a key turning in tumblers |
| The Pendulum | `D A D A` in a 3/4 lilt (tick, tock) | the swing |
| The Prism | `B F♯ C♯ G♯` (stacked fifths) | white light split into colour |
| The Hourglass | `A G♯ G F♯ F E` (descending chromatic lament) | sand running out |
| The Mirror | S⁻¹ | the player's own song, reversed |

---

## 3. Technical requirements

### 3.1 Delivery
- **Format:** OGG Vorbis, quality 6, 44.1 kHz stereo. Stings may be mono.
- **Loudness** (integrated, measured over one loop):
  - boss themes -14 LUFS
  - jail -17 LUFS
  - title -16 LUFS
  - stings -14 LUFS
  - true peak ≤ -1 dBTP on all of them
- **Loops:**
  - sample-accurate, with the loop start written as `loop_offset` in the Godot import
  - the last bar's reverb tail is rendered and folded into the loop start, so the seam is inaudible
- **Phase sections:**
  - one OGG per section, all the same length in bars, starting and ending on a bar line
  - each section loops on its own until the next phase arrives
- **Size budget:** whole score ≤ 28 MB on device. The ending can be the largest cue.
- **Naming:** `music_<cue>[_<section>].ogg`, for example `music_turnkey_p2.ogg`.

### 3.2 Adaptive behaviour (Godot 4)
- **Horizontal phases:**
  - `AudioStreamInteractive`, one clip per phase
  - transitions on the next bar (`TRANSITION_FROM_TIME_NEXT_BAR`), with a 1-bar crossfade, or an authored fill where one is listed
- **Vertical layers (the jail):**
  - `AudioStreamSynchronized`, with five stems started together
  - layer *n* fades in over 2 s once *n* sapphires are on the altar
- **Stings:**
  - the boss intro, victory, defeat and gate stings play on their own player
  - while a sting plays, the loop under it ducks 8 dB and then is cut

### 3.3 Buses and the mix with what already exists
- **Buses:** `Master` → `Music` (-3 dB), `Ambience` (-14 dB, as `Sfx.ambience` sets now), `SFX`.
  Settings gets one slider for Music and one for SFX.
- **Ambience:**
  - boss music replaces room ambience during a fight: ambience fades to -24 dB, but never to silence, so the room still breathes between notes
  - in the jail, `amb_jail` stays at full level under the jail theme
  - the theme is sparse enough that dripping water and torches stay audible
- **Ducking:** a sidechain compressor on `Music`, keyed from `SFX` (ratio 2:1, -3 dB maximum, 80 ms release), so hits punch through
  without the music pumping.

---

## 4. Cue sheet

`★` means it loops. Lengths are for one pass of the loop.

**One palette for the whole score.** The title and jail set it, and every boss theme keeps to it:
- piano, harp
- strings (section, solo violin, cello, low strings, tremolo, pizzicato)
- flute, clarinet
- choir, horns
- timpani and orchestral percussion

There are no synths, electric instruments, saxes, organ or rock kit. A boss's character comes from how these play,
not from new colours: the Turnkey's funk in pizzicato and horns, the Prism's prog in marcato strings and piano fifths.

The score splits two ways. **Music** carries a scene and plays on the `Music` bus:
it loops, or is the long ending. **Stings** are one-shots that a game event fires over the music.
They play through `Sfx` like any other sound effect, and each is named after the existing sound in `media/sfx/`
that it would replace or layer onto.

| Music (`media/music/midi/`) | Stings, played as SFX (`media/sfx/midi/`) |
|---|---|
| `00_title` *Facets of Green* ★ | `intro_<boss>` ×5 *A Door Opens*: replaces the synth `intro` |
| `01_jail` *Behind Green Bars* ★ | `hourglass_timesup` *Time's Up*: layers onto the synth sound of the same name |
| `03_turnkey` *Lock, Stock & Turnkey* ★ | `win` *Facet Restored*: replaces the synth `win` |
| `04_pendulum` *Pendulum Waltz in Dust* ★ | `lose` *Shattered*: replaces the synth `lose` |
| `05_prism` *Refraction* ★ | `place_1`…`place_4` *Sapphire Set*: layer onto `place`, one per stone |
| `06_hourglass` *Sands of the Last Hour* ★ | `gate_lift` *The Gate Lifts*: plays after the recorded `gate` grind |
| `07_mirror` *Mirror, Mirror* ★ | |
| `12_ending` *The Green Sapphire Is Whole* (plays once, for the credits) | |

The music keeps its cue numbers from this sheet, so 02 and 08–11 are the stings.

### 00 · *Facets of Green*: Title / Home ★
- **Where:** home screen.
- **Function:** first impression and the motif's first statement. Calm and warm, a deep breath before the jail.
- **Key / tempo / meter:** G major (E minor's relative, so S keeps its notes), ♩ = 60 (♪ = 120), 6/8.
- **Why it is calm, not sad:** open add9 and maj9 chords, phrases that settle sus4 → major, and no dominant 7ths
  pulling back. The left hand ripples upward through each chord.
- **Instruments:** solo grand piano, slow strings far behind, cello, and a music box on the last pass.
- **Form, 32 bars (~1:36), one long breath:**
  - **A (1–8):** piano alone. S over `Gadd9 – Cmaj9 – Em7 – Bm7`, answered by a phrase that lands on D.
  - **A′ (9–16):** S an octave up. The strings fade in from nothing across all eight bars, and the cello's countermelody joins halfway.
  - **B (17–24):** the fullest point, still gentle. `Cmaj9 – D/C – Bm7 – Em9 – Am9 – Bm7 – Cmaj9 – Dsus4 D`.
  - **A″ (25–32):** the music box carries S while everything else lets go. The cello fades by bar 28 and the strings by bar 30, so
    the last bars are piano and music box alone and the loop's A follows without a drop.
- **Loop seam:** `Dsus4 → D → Gadd9`, a soft V → I.
- **Touchstone:** *Dearly Beloved* (Kingdom Hearts).
- **Ambience:** none. The home screen is silent but for this.

### 01 · *Behind Green Bars*: The Jail ★ (simple and rich passes)
- **Where:** the hub, between every fight.
- **Function:** rest, orientation, progress. Dark and mysterious, a place that keeps secrets.
- **Key / tempo / meter:** E minor (Aeolian, with Phrygian shadows), ♩ = 72, 4/4.
- **Why it is dark:**
  - a low E pedal under the first half of each pass
  - the Phrygian ♭II (F major) as the shadow chord
  - a minor v (Bm) back to i at the seam, with no leading tone
  - a melody that stays low
  - no drums
- **Harmony (16 bars, both passes):**
  - First half, over the E pedal: `Em(add9) – Cmaj7 – Bm7 – Em(add9)`, then `Em(add9) – Fmaj7♯11 – Dm7 – Bsus4 Bm`.
  - Second half: `Am9 – Em/G – Fmaj7♯11 – Em – Am9 – Cmaj7 – Fmaj7♯11 – Bsus4 Bm`.
- **Form:** 32 bars (~1:47) that alternate forever. The **Simple** pass (bars 1–16) is followed by the **Rich** pass
  (bars 17–32), which turns back into the simple one.

| Voice | Simple pass | Rich pass |
|---|---|---|
| Harp | two long low notes a bar (root, fifth below), under the flute | a three-note figure dripping down each chord, high; back to the low notes for the last two bars |
| Cello | the E pedal, then the roots | same |
| Pizz Bass | heartbeat on each bar | same |
| Flute | S low, S bent through the Phrygian F, a sinking second half, a pickup into the seam | same |
| Low Strings | one long counter-note a bar | same |
| Choir | two notes of each chord, fading in and out | three notes of each chord, fading in and out |
| Clarinet | — | doubles the flute's second half an octave down; stops two bars early |
| Tremolo Strings | — | a cold shimmer, swelling in from nothing and gone by the last bar |
| Horns | — | low, on the Phrygian S, then holding C, fading out before the last bar |

- **The seams:**
  - **Rich → simple:** the rich pass spends its last four bars becoming the simple pass, so there is no drop.
    Its extra voices fade to nothing, the clarinet stops two bars early, the high harp drips give way to the low
    notes, and the flute takes the same pickup (G, F♯) into the opening E.
  - **Simple → rich:** the rich voices swell in from silence.
  - **Both:** each seam is `Bm → Em`. Everyone eases down over the last bar and back up over the first, and the
    cello holds one B through the last bar.
- **Adaptive (later):** both passes start and end the same way, so the game can loop the simple pass alone (bars 1–16)
  until a sapphire is set, then let the rich pass join.
- **Touchstone:** a Trails dungeon or night-town theme.
- **Ambience:** `amb_jail` (dripping, distant chains) at full level.

### 02 · *A Door Opens*: Boss intro sting
- **Where:** the boss title card (`hud._draw_intro`), 1.5 s.
- **Music:** a timpani roll, a low brass stab on the keeper's cell, then a bar of silence before the theme.
  There are five variants, each stab spelling that keeper's cell.

### 03 · *Lock, Stock & Turnkey*: Cell I ★ (3 phases)
- **Where:** the Turnkey's treasure vault.
- **Mood:** Persona's swagger: a heist in a vault of gold, cocky and stylish, deadly fast.
- **Key / tempo / meter:** G minor (Dorian lean), ♩ = 126, 4/4, light swing on the 16ths (56%).
- **Instruments (the shared palette):**
  - harp and a high piano playing the key cell, like tumblers clicking
  - piano comping, pizzicato strings for the funk scratch, pizzicato bass
  - clarinet lead, with flute and cello doubling it in P2
  - horn stabs
  - orchestral percussion, with the funk groove kept on bass drum, snare and toms
- **Form:**

| Section | Bars | Music |
|---|---|---|
| Intro | 4 | the key cell on harpsichord, alone, then a drum fill |
| P1 | 16 | groove `Gm9 – C9 – Gm9 – E♭maj7 D7♯9`; alto sax lead built from S in G minor |
| P2 | 16 | the Blades phase: brass doubles the lead, the bass goes to octave runs, crash on every 4 |
| P3 | 16 | the Combination dial: one 5/4 bar in every 4 (the dial's extra click), the hats go to 16ths, chromatic brass climbs on the key cell |

- **Touchstones:** *Life Will Change*, *Rivers in the Desert* (Persona 5).

### 04 · *Pendulum Waltz in Dust*: Cell II ★ (3 phases)
- **Where:** the Pendulum's library.
- **Mood:** elegant and lethal: a duel in a ballroom of books, swinging between grace and menace.
- **Key / tempo / meter:** D minor, ♩. = 60 (♩ = 180), 3/4.
- **Instruments (the shared palette):**
  - harp ostinato on the tick-tock cell; cello, strings and high strings
  - solo violin and flute sharing the tune
  - choir, horns
  - piano clockwork, ticking in eighths
  - marcato low strings answering the violin in P2
  - orchestral percussion in 3 from P2
- **The tune:** S transformed into a D-minor waltz, 16 bars.
  - **Phrase A:** S, with a turn on its held A, and a lead-in back up to the next phrase.
  - **Phrase B:** climbs to A6, then a **hemiola**: B♭, G, F in two-beat notes across two bars. The G is held over the bar line
    onto Dm/F, so the waltz briefly feels like it's in 2 before resolving. Its last bar climbs on instead of sitting still.
  - **Each statement develops:** the violin plays it first. The second time, the flute takes phrase A while the violin plays a
    countermelody under it, then the violin takes the climax with the flute an octave below.
- **Form:**

| Section | Bars | Music |
|---|---|---|
| P1 | 32 | waltz: `Dm – A7/C♯ – Dm/C – G/B – B♭maj7 – Gm6 – A7`; the tune twice, high strings holding each chord, the choir humming the climax |
| P2 | 32 | Rail Rush: marcato strings and percussion; the violin and low strings trade phrases (Trails' signature) and the flute answers each trade softly; horns hit every downbeat |
| P3 | 8 + 32 | Clockwork: piano and pizzicato ticking, the harp and high strings shimmering over them, then a snare roll with the strings swelling; the orchestra slams back up a minor third in F minor at its fullest. The violin leads, the flute plays the countermelody above, and the choir and low strings double the tune. |

- **Transitions:** every phase change is approached, not switched on a downbeat.
  - **P1 → P2:** a soft snare pickup, the low strings a bar early, and a horn swell into the drive.
  - **P2 → clockwork:** the drums, marcato strings and horns stop two bars early, and everything fades down into the ticking.
  - **Clockwork → F minor:** a snare roll with the strings swelling.
  - **F minor → P1 (the loop):** the same let-go as P2. P1 then swells back up from that level over its first two bars, a
    mirror of the fade.
- **Loop seam:** `A7 → Dm`. P3's last bar turns back from F minor to A7.
- **Touchstones:** *Masquerade of Lies* (Trails of Cold Steel); Shostakovich *Waltz No. 2*.

### 05 · *Refraction*: Cell III ★ (6 phases)
- **Where:** the Prism's crystal cave.
- **Mood:** awe turned into a storm: light splitting into colours you can't see. Bright and cold, with a progressive engine.
- **Key / tempo / meter:** B minor / B Lydian, ♩ = 152, alternating 7/8 and 4/4.
- **Instruments (the shared palette):**
  - piano and harp splitting the light into the stacked-fifths cell
  - cello bass, marcato low strings for the riff, horns holding the chords
  - flute lead, choir, strings
  - orchestral percussion
- **Form:** six 8-bar sections, each adding one colour, the way the Prism adds attacks.

| Phase | Adds |
|---|---|
| 1 | bells, bass and kit in 7/8 |
| 2 | guitar riff |
| 3 | organ, tempo feel doubled |
| 4 | the choir sings S in B minor |
| 5 | double-kick, full strings |
| 6 | everything, the key lifts to C♯ minor |

- **Touchstones:** *Fighting of the Spirit* (Tales of Phantasia); Sakuraba's prog-rock bosses.

### 06 · *Sands of the Last Hour*: Cell IV ★ (2 phases)
- **Where:** the Hourglass's desert.
- **Mood:** heat, patience, then panic. The music *is* the sand clock.
- **Key / tempo / meter:** A Phrygian dominant, ♩ = 112 rising to 124 in P2, 4/4.
- **Instruments (the shared palette):**
  - toms where the hand drums were, timpani on the down-beats
  - harp ostinato where the oud was
  - flute lead, a string ostinato, piano on the lament cell
- **Form:**

| Section | Bars | Music |
|---|---|---|
| P1 | 16 | hand drums and oud; the ney plays S bent through Phrygian (F, G♯); the lament bass descends every 4 bars |
| P2 | 16 | Time Echo: every phrase is answered one bar later by a delayed copy, as the boss repeats its attacks; strings in tremolo |

- **Time's Up:** a one-bar string glissando hit, with a separate sting so it can fire on the event.
- **Touchstones:** desert dungeons in Tales of Symphonia and the Trails series.

### 07 · *Mirror, Mirror (Final Exam)*: Gate V ★ (song form)
- **Where:** the Mirror's mind space.
- **Mood:** the final exam. It is your own song turned against you. Then it breaks, and becomes yours again.
- **Key / tempo / meter:** E minor with a G minor chorus, ♩ = 160. 4/4, with the bridge's memories in their own meters.
- **Instruments (the shared palette):**
  - piano, strings and high strings, choir, horns
  - pizzicato bass, marcato low strings, staccato strings
  - harp, solo violin, a high piano, flute
  - timpani and orchestral percussion
- **Form, ~1:46:** verse → pre-chorus → chorus → bridge → final chorus, then back to the verse.

| Section | Bars | Lead | Music |
|---|---|---|---|
| **Verse** | 16 | piano | S⁻¹ over driving strings, then the answer. The second half is richer: choir, a flute countermelody and held low strings. Percussion waits until bar 5. |
| **Pre-chorus** | 8 | violin | the inversion's head climbing `Am7 – Bm7 – Cmaj7 – D – E♭maj7 – Cm7 – D7sus4 – D7`. The harp runs up each chord, horns enter halfway, and a snare and timpani build. |
| **Chorus** | 16 | horns, choir, violin; flute in the second half | S the right way up, in G minor, `Gm9 – E♭maj7 – Cm9 – D7`. Full: the choir's chords under the melody throughout, sustained high strings over the eighth-note drive, big piano chords, harp arpeggios, a cello countermelody, staccato strings off the beat, timpani every second bar. It ends `Cm6 – B7`, its last two bars easing off. |
| **Bridge** | 16 | each memory's voice | chill: the memories as a dream over one soft string pad. **Turnkey**: a walking pizzicato bass, soft jazz piano, the key cell on harp. **Pendulum**: 3/4, harp tick-tock and violin. **Prism**: 7/8, soft high-piano fifths over held chords, a soft violin. **Hourglass**: two bars of the Phrygian flute over hushed toms, then **the lift**: `E♭maj7 – D7sus4 D7`, with a snare and timpani roll, a string run and harp sweep up D Phrygian dominant, and a horn swell into… |
| **Final chorus** | 16 | as the chorus, with flute and violin on top throughout | the chorus at its fullest. It eases off on `Cm6 – B7` back into the verse. |

- **Percussion follows the form:** none in the verse's first four bars, a build into each chorus, each chorus easing to a
  single bass drum in its last two bars, a hushed bridge until its lift. No seam slams from full kit into something quiet.
- **Seams:**
  - verse → pre-chorus `B7 → Am7`
  - pre-chorus → chorus `D7 → Gm`
  - chorus → bridge `B7 → Em`, eased off
  - bridge → final chorus `D7(♭9) → Gm`, lifted
  - final chorus → verse (the loop) `B7 → Em`, eased off
- **In the game:** the six fight phases map onto the sections. The verse is P1, the bridge's memories are P2–P5 (each can
  loop on its own), and the final chorus is P6.
- **Touchstones:** *Dearly Beloved* inverted into *Destati* (Kingdom Hearts); the Trails final-boss medley tradition.

### 08 · *Facet Restored*: Victory (8 s)
E major fanfare: S, then S′ resolving to E. Brass, timpani, a cymbal swell. It sits in the same key as the win SFX.

### 09 · *Shattered*: Defeat (5 s)
S on solo piano, slowed, the last note detuned and left hanging. A low string swell fades under it.

### 10 · *Sapphire Set* (3 s)
Harp glissando and a celesta playing the first three notes of S, at a higher pitch with every stone.
It layers on the `place` SFX.

### 11 · *The Gate Lifts* (6 s)
Low brass and choir. S rises in sequence, a step higher on each repeat, and ends on a suspended chord that resolves into 07.

### 12 · *The Green Sapphire Is Whole*: Ending (~2:22, credits)
- **Where:** the credits, after the green sapphire is made whole. It plays once, then ends.
- **Function:** catharsis. The first time S′ answers S.
- **Instruments:** piano, strings (section, violins, cello), flute, horns and choir. There is no harp or percussion, so the
  lift comes from the orchestra itself.
- **The flute backs the strings throughout:**
  - long notes held over the strings' chords
  - thirds under the violins
  - a rising run into the E-major arrival (where a harp glissando used to be)
  - unison with the violins on the climax
  - one soft held note on the final chord
- **Form:**
  - **Piano:** solo piano plays S, as in 00.
  - **The answer:** strings join, and S′ resolves it at last.
  - **Into the light:** `C – D – C – D E` turns to E major, the flute running up into it.
  - **Whole:** S in E major (S+) with the full orchestra and choir. The climax is a I–V/7–vi–IV–I cadence, and S′+ resolves.
  - **Coda:** quiet piano, S+ once more, ending on an E major chord with an added ninth (Eadd9).
  - **End:** a silent bar after the last chord lets it and the reverb ring out.
- **Touchstones:** *Simple and Clean* orchestral; the Trails epilogue themes.

---

## 5. How the music and the ambience fit together

| Room | Ambience bed | Music | How they share the space |
|---|---|---|---|
| Home | silence | 00 | the piano is the only sound |
| Jail | `amb_jail`: drips, chains, torches | 01 | music at -17 LUFS; drips hit between beats, never quantised |
| I Vault | `amb_cell1`: coins settling, a room tone | 03 | ambience ducks to -24 dB in the fight, back after victory |
| II Library | `amb_cell2`: candle flutter, pages | 04 | the harpsichord's register stays above the page rustle |
| III Cave | `amb_cell3`: drips, crystal hum | 05 | the crystal bells share the hum's key (B) on purpose |
| IV Desert | `amb_cell4`: wind | 06 | wind gusts are left at full level in P1's sparse bars |
| V Mind | `amb_cell5`: a dark drone on E | 07 | the drone is the music's tonic, so the ambience sounds like part of the score |

---

## 6. Implementation notes

**What's in the game now (first pass):**
- `scripts/music.gd` is the `Music` autoload: `play(name)` crossfades to a track, `stop()` fades it out.
  Asking for the track already playing does nothing, and the music keeps playing under the pause menu.
- `media/music/` holds five tracks, built from the GarageBand renders in `media/music_src/` (git-ignored) by
  `tools/make_music_loops.py`. Each loop is cut to its exact musical length, with the render's ring-out folded onto the
  start, so it repeats without a seam. Godot imports them with QOA compression, about 3.3 MB each in the build.

| Track | Plays | Loop |
|---|---|---|
| `title` | home screen | 96.00 s |
| `jail` | the jail | 106.67 s |
| `boss` | cells I–IV (your arrangement of the Mirror's song form) | 105.75 s |
| `final` | gate V, the Mirror | 105.75 s |
| `ending` | the ending (`scenes/ending.tscn`): an animation and credits roll timed to it, on its clock | plays once |

- A fight's music fades out (1.5 s) when it's won or lost, under the win/lose sting, and the jail's music comes back
  when you return.
- **Stings:** `tools/render_stings.py` renders the MIDI stings through FluidSynth with the GeneralUser GS soundfont
  (free for any use; kept outside the repo) into `media/sfx/`, where `Sfx` plays them by name:

| Sting | Plays when |
|---|---|
| `intro_<boss>` | on the boss's title card. The fight's music waits for it to ring out (`main.gd`, `INTRO_HOLD`). |
| `win`, `lose` | the fight ends. They replace the synth versions, whose recipes are retired in `make_sfx.py`. |
| `place_1`…`place_4` | over `place`, a step higher with each sapphire set on the altar |
| `gate_lift` | with the stone `gate` grind as the great gate unlocks |
| `hourglass_timesup.orch` | layered on the synth Time's Up |

- **Not yet:** a separate theme per boss, phase-by-phase music changes, a Music volume slider, and ducking under the
  pause menu. The rest of this section describes that fuller plan.

**The full plan:**

1. **Autoload.** Add a `Music` autoload next to `Sfx`, with these calls:
   - `play(cue)`
   - `phase(n)`, which jumps the `AudioStreamInteractive` to clip *n*
   - `layers(n)`, for the jail
   - `sting(name)`
2. **Hooks that already exist:**
   - `boss.phase_changed`, which feeds `Music.phase`
   - `main._on_boss_died`, which plays 08
   - player death, which plays 09
   - `hub` place, which plays 10 and calls `layers(n)`
   - the gate, which plays 11
   - `hud` intro, which plays 02
3. **Pause.** Music keeps playing at -10 dB under the pause menu, through a low-pass at 1.2 kHz.
4. **Beat sync (stretch goal).** Expose `Music.beat_time()` so a boss can start a telegraph on the next beat.
   This matters most for the Turnkey (P3) and the Pendulum.
5. **Settings.** A Music volume slider, saved with the rest.

---

## 7. MIDI sketches and GarageBand

`tools/make_music.py` writes one Standard MIDI File (type 1, 480 PPQ) per cue: music to `media/music/midi/`
and stings to `media/sfx/midi/`.

Each file contains:
- named tracks with General MIDI program changes
- tempo and time-signature changes
- markers at every section (`P1`, `P2`, … `Loop`)
- sustain-pedal, expression and modulation curves
- drums on channel 10

`tools/midi_check.py` reads the files back and checks them:
- note ranges
- clashes between the melody and the chords on strong beats
- every track for each cue length
- a piano-roll PNG of each cue

Every music file but the ending loops (the ending plays once and has an `End` marker a bar after its last chord,
so it rings out). Each looping file has `Loop Start` and `Loop End` markers on bar lines (the Turnkey's starts after its
intro), and its last bar leads back to its first with a cadence. Every phase section also ends on the dominant
of where it starts, so each section can loop on its own in the game. At the loop start, each track's
expression, sustain pedal and pitch bend are reset to their first-pass values. `midi_check.py` verifies the
bar lines, flags any note that would be clipped, and prints each seam (`↻ loop: B7 -> Em`).

### Importing into GarageBand
1. Drag a `.mid` file into an empty project. GarageBand creates one track per MIDI track, keeping each track's name.
2. GarageBand gives every track a piano at first. Set each one by its name using the table below.
   Drum tracks map to any GarageBand kit, because the notes follow the GM kit layout (36 kick, 38 snare, 42/46 hats, 49 crash).
3. Turn the project tempo to *Use MIDI file tempo* if GarageBand asks. Tempo and meter changes come in with the file.
4. To hear the loop, turn on the cycle region (press C) and drag it over one cue, from bar 1 to its end.
   For the Turnkey, start the cycle region at bar 5, after the intro. GarageBand doesn't read MIDI markers,
   so the bar numbers come from the cue sheet or from `midi_check.py`.

| Track name starts with | GarageBand patch |
|---|---|
| Piano | Steinway Grand Piano |
| Rhodes / Clav | Classic Electric Piano / Funky Clav |
| Harpsichord / Celesta / Music Box / Glock / Bells | Harpsichord / Celesta / Music Box / Glockenspiel / Crystal Bells (Synth) |
| Harp | Harp (Orchestral) |
| Clarinet | Clarinet (Woodwinds) |
| Bassoon | Bassoon (Woodwinds) |
| Tremolo Strings / Low Strings | String section, with the tremolo articulation if offered / Cellos |
| Strings / Violin / Cello / Pizz | Hollywood Strings section / Solo Violin / Cello / Pizzicato Strings |
| Flute / Ney | Flute / Pan Flute or Shakuhachi |
| Horns / Brass / Trumpet / Sax | French Horns / Brass Section / Trumpet / Alto Sax |
| Choir | Choir Aahs (Vintage Mellotron Choir works well) |
| Organ | Classic Rock Organ (Hammond) |
| Guitar | Hard Rock / Crunch Guitar amp on a clean guitar |
| Oud / Sitar | Koto, or Sitar if installed |
| Slap Bass / Bass / Synth Bass | Slap Bass / Fingerstyle Bass / Analog Mono |
| Arp / Pad | Retro Arpeggiator / Ambient pad |
| Percussion (boss themes) | an orchestral percussion kit if your GarageBand has one, else a soft acoustic kit with its hi-hat muted (the hats are already removed) |
| Staccato Strings | String section, staccato/spiccato articulation |
| Timpani | Timpani (Orchestral percussion) |
