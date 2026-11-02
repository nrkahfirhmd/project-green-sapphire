"""The Green Sapphire score, composed in code as General MIDI sketches.

    python3 tools/make_music.py [cue-name ...]

Writes one Standard MIDI File per cue: music (scene themes that loop, and
the ending) to media/music/midi/<nn>_<cue>.mid, and stings (one-shots a game
event fires over the music) to media/sfx/midi/<sfx name>.mid, named after the
sound in media/sfx/ each would replace or layer onto. Both are for
arranging and rendering in GarageBand (track names say which patch to use;
see docs/music-bible.md §7). Every cue is built on the Green Sapphire motif
(S) and the keepers' cells described in the bible, §2.

Conventions: beats are quarter notes; `bar` is the current bar length in
beats; sections are marked with MIDI markers (P1, P2, ..., Loop).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from midi_kit import Song, pitch, voicing, bass_of, tone, degrees  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "media", "music", "midi")
SFX_OUT = os.path.join(ROOT, "media", "sfx", "midi")

# GM programs (0-based)
PIANO, RHODES, CLAV, HARPSI, CELESTA, GLOCK, MUSICBOX, VIBES, DULCIMER = 0, 4, 7, 6, 8, 9, 10, 11, 15
ORGAN, CHURCH = 16, 19
NYLON, OVERDRIVE, DIST = 24, 29, 30
FINGER, SLAP, SYNBASS = 33, 36, 38
VIOLIN, CELLO, TREMOLO, PIZZ, HARP, TIMPANI, STRINGS, SLOWSTR = 40, 42, 44, 45, 46, 47, 48, 49
CHOIR = 52
TRUMPET, TROMBONE, HORN, BRASS = 56, 57, 60, 61
ALTO, TENOR = 65, 66
FLUTE, PANFLUTE, SHAKU = 73, 75, 77
SAWLEAD, PAD, CRYSTAL = 81, 88, 98
SITAR, SHAMISEN, TAIKO = 104, 106, 116

# GM drum notes
KICK, KICK2, RIM, SNARE, CLAP, HAT, PHAT, OHAT = 36, 35, 37, 38, 39, 42, 44, 46
TOM_LO, TOM_MID, TOM_HI, CRASH, RIDE, BELL, TAMB, SPLASH = 45, 47, 50, 49, 51, 53, 54, 55
BONGO_HI, CONGA_MUTE, CONGA_LO, SHAKER = 60, 62, 64, 70

# --- the Green Sapphire motif -----------------------------------------
# S as scale degrees from the tonic (E): 1 5 b7 8 9 b3' 9 b7 5
S_DEG = [0, 4, 6, 7, 8, 9, 8, 6, 4]
S_44 = [1, 1, 2, 1.5, .5, 2, 2, 2, 4]          # four bars of 4/4
S_68 = [1, .5, 1.5, 1, .5, 1.5, 1.5, 1.5, 3]   # four bars of 6/8 or 3/4
S_78 = [1, 1, 1.5, 1, 1, 1.5, 1.5, 2, 4]       # three 7/8 bars and one 4/4
# S' (the answer, held back until the ending): b3' 9 8 b7 | 8
SA_DEG = [9, 8, 7, 6, 7]


def S(tonic, scale="minor"):
    return degrees(S_DEG, tonic, scale)


def S_inv(top):
    """The Mirror's voice: S turned upside down around its first note."""
    s = S(pitch("E4"))
    return [top - (p - s[0]) for p in s]


def chords(song, start, prog, bar, fn):
    """Walk a progression: prog entries are a chord or a tuple of chords
    splitting the bar evenly; fn(beat, sym, dur) for each."""
    b = start
    for item in prog:
        parts = item if isinstance(item, tuple) else (item,)
        d = bar / len(parts)
        for sym in parts:
            fn(b, sym, d)
            b += d
    return b


def pad(t, start, prog, bar, lo, vel=58, n=4, swell=True):
    def f(b, sym, d):
        t.block(b, voicing(sym, lo, n), d, vel)
        if swell:
            t.ramp(b, d, 11, 70, 105, 6)
    return chords(None, start, prog, bar, f)


def roots(t, start, prog, bar, lo, vel=80, legato=0.98):
    return chords(None, start, prog, bar, lambda b, sym, d: t.note(b, d, bass_of(sym, lo), vel, legato))


CLARINET = 71


def orchestral(kit, name="Percussion"):
    """Recast a drum-kit track as orchestral percussion, to match the title
    and jail: bass drum, a softer snare, toms and the suspended cymbal stay;
    hats, ride, tambourine and double-kick go; hand drums become toms."""
    drop = {HAT, PHAT, OHAT, RIDE, BELL, TAMB, SPLASH, KICK2, SHAKER}
    remap = {CONGA_LO: TOM_LO, CONGA_MUTE: TOM_MID, BONGO_HI: TOM_HI, CLAP: SNARE}
    out = []
    for tk, o, b in kit.ev:
        kind = b[0] & 0xF0
        if kind in (0x80, 0x90):
            n = b[1]
            if n in drop:
                continue
            n = remap.get(n, n)
            v = b[2]
            if kind == 0x90 and n == SNARE:
                v = max(1, int(v * 0.7))
            b = bytes([b[0], n, v])
        out.append((tk, o, b))
    kit.ev = out
    kit.name = name


def save(song):
    """Music is numbered (00_title); a sting is named after its sfx (win)."""
    out = OUT if song.name[:2].isdigit() else SFX_OUT
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, song.name + ".mid")
    song.save(path)
    print(f"{song.name}: {song.title}, {song.length:.0f} beats, {len(song.tracks)} tracks")


# ======================================================================
# 00 Facets of Green — title. G major, 6/8, piano with strings breathing in
# and out. Calm, not sad: open add9/maj9 chords, phrases that land on
# sus -> major instead of a dominant 7th's pull, and a left hand that ripples
# upward. The arc is one long breath: piano alone, strings fade in through
# A2, fullest in B, fade out through A3, so the loop comes back to piano
# alone without a drop.
# ======================================================================
def title():
    s = Song("00_title", "Facets of Green", 60, 6, 8)
    bar = 3.0
    pno = s.track("Piano", PIANO, pan=64, reverb=80)
    strings = s.track("Strings", SLOWSTR, pan=50, reverb=90, vol=78)
    cello = s.track("Cello", CELLO, pan=40, reverb=80, vol=84)
    box = s.track("Music Box", MUSICBOX, pan=84, reverb=90, vol=72)
    A = ["Gadd9", "Cmaj9", "Em7", "Bm7", "Gadd9", "Cmaj9", "Am7", ("Dsus4", "D")]
    B = ["Cmaj9", "D/C", "Bm7", "Em9", "Am9", "Bm7", "Cmaj9", ("Dsus4", "D")]

    def lh(dyn):
        def f(b, sym, d):
            # a ripple upward and back: bass, fifth, octave, ninth, tenth, octave
            bass = bass_of(sym, pitch("C2"))
            v = voicing(sym, bass, 3)
            r = v[0]
            pat = [bass, r + 7, r + 12, r + 14, r + 12 + (v[1] - r), r + 12]
            shape = [50, 40, 42, 46, 48, 40]
            for i in range(int(round(d / 0.5))):
                pno.note(b + i * 0.5, 0.5, pat[i % 6], shape[i % 6] * dyn, legato=2.2)
            pno.pedal(b)
        return f

    s_line = S(pitch("E4"))      # E B D E F# G F# D B: all in G major
    answer = "G5:1 A5:.5 B5:1.5 | G5:1 E5:.5 D5:1.5 | C5:1 D5:.5 E5:1.5 | D5:3"
    b_line = ("E5:1.5 G5:1.5 | F#5:1 E5:.5 D5:1.5 | D5:3 | B4:1 D5:.5 E5:1.5 | "
              "C5:1.5 E5:1.5 | D5:1 F#5:.5 B5:1.5 | G5:1 E5:.5 B5:1.5 | A5:1.5 F#5:1.5")
    counter = ("B2:3 | E3:1.5 G3:1.5 | G3:3 | F#3:3 | D3:1.5 B2:1.5 | C3:1.5 E3:1.5 | "
               "E3:1.5 C3:1.5 | A2:1.5 F#2:1.5")

    t = 0.0
    # A: piano alone, soft
    s.mark(t, "A")
    chords(None, t, A, bar, lh(0.95))
    pno.tones(t, s_line, S_68, vel=66)
    pno.line(t + 4 * bar, answer, vel=64)
    t += 8 * bar

    # A2: the melody an octave up; strings breathe in from nothing, the cello
    # joins halfway
    s.mark(t, "A2")
    chords(None, t, A, bar, lh(1.0))
    pno.tones(t, s_line, S_68, vel=70, tr=12)
    pno.line(t + 4 * bar, answer, vel=68, tr=12)
    pad(strings, t, A, bar, pitch("G3"), vel=46, swell=False)
    strings.ramp(t, 8 * bar, 11, 8, 88, 24)
    cello.line(t + 4 * bar, " | ".join(counter.split(" | ")[4:]), vel=58)
    cello.ramp(t + 4 * bar, 4 * bar, 11, 40, 96, 12)
    t += 8 * bar

    # B: the fullest it gets, still gentle
    s.mark(t, "B")
    chords(None, t, B, bar, lh(1.05))
    pno.line(t, b_line, vel=72)
    pad(strings, t, B, bar, pitch("G3"), vel=50, swell=False)
    strings.ramp(t, 4 * bar, 11, 88, 104, 12)
    strings.ramp(t + 4 * bar, 4 * bar, 11, 104, 92, 12)
    roots(cello, t, B, bar, pitch("C2"), vel=58)
    cello.cc(t, 11, 96)
    t += 8 * bar

    # A3: the music box carries the motif and everything else lets go: the
    # strings fade to nothing by bar 7, the cello by bar 5, so the last bars
    # are piano and music box alone, as the loop's A begins
    s.mark(t, "A3")
    chords(None, t, A, bar, lh(0.95))
    pno.tones(t, s_line, S_68, vel=62)
    box.tones(t, s_line, S_68, vel=64, tr=12)
    pno.line(t + 4 * bar, answer, vel=58)
    box.line(t + 4 * bar, " | ".join(answer.split(" | ")[:3]), vel=54)
    pad(strings, t, A[:6], bar, pitch("G3"), vel=44, swell=False)
    strings.ramp(t, 6 * bar, 11, 92, 0, 24)
    cello.line(t, " | ".join(counter.split(" | ")[:4]), vel=52)
    cello.ramp(t, 4 * bar, 11, 92, 0, 16)
    t += 8 * bar
    s.end(t)
    s.loop(0)
    return s


# ======================================================================
# 01 Behind Green Bars — the jail. E minor (Aeolian, Phrygian shadows), 72.
# Dark and mysterious: a low E pedal under the first half of each pass, the
# Phrygian bII (F) as the shadow chord, a minor v (Bm) back to i at the seam
# with no leading tone, a melody that stays low, and no drums.
# Two 16-bar passes over the same harmony and melody, alternating forever:
#   simple: one voice per job (low harp, cello, pizz, flute, low strings,
#     a hummed choir)
#   rich: the full dark arrangement (high harp drips, clarinet doubling,
#     tremolo shimmer, a three-voice choir, low horns)
# The rich pass spends its last four bars turning back into the simple one,
# so the cycle never drops: its extra voices fade out, the clarinet stops two
# bars early, the harp's high drips give way to the simple low notes, and
# the flute takes the same pickup into the opening E.
# ======================================================================
def jail():
    s = Song("01_jail", "Behind Green Bars", 72)
    bar = 4.0
    CLARINET = 71
    R = 16 * bar                    # where the rich pass starts
    harp = s.track("Harp", HARP, pan=50, reverb=100, vol=86)
    cello = s.track("Cello", CELLO, pan=40, reverb=80, vol=88)
    pizz = s.track("Pizz Bass", PIZZ, pan=60, reverb=70, vol=88)
    fl = s.track("Flute", FLUTE, pan=70, reverb=90, vol=90)
    low = s.track("Low Strings", STRINGS, pan=34, reverb=80, vol=84)
    choir = s.track("Choir", CHOIR, pan=64, reverb=100, vol=70)
    clar = s.track("Clarinet (rich)", CLARINET, pan=30, reverb=80, vol=82)
    trem = s.track("Tremolo Strings (rich)", TREMOLO, pan=56, reverb=90, vol=68)
    horns = s.track("Horns (rich)", HORN, pan=76, reverb=90, vol=82)

    prog = ["Emadd9", "Cmaj7/E", "Bm7/E", "Emadd9", "Emadd9", "Fmaj7#11/E", "Dm7/E", ("Bsus4", "Bm"),
            "Am9", "Em/G", "Fmaj7#11", "Em", "Am9", "Cmaj7", "Fmaj7#11", ("Bsus4", "Bm")]
    melody = [
        None,   # bars 1-4: S, played from S_44 below
        "E4:1 B4:1 D5:2 | E5:1.5 F5:.5 G5:2 | F5:2 D5:2 | B4:4",
        "C5:2 B4:1 A4:1 | G4:3 r:1 | A4:1.5 B4:.5 C5:2 | B4:4",
        # the last bar breathes, then a pickup (G F#) leads into the opening
        # E, so the melody runs across every seam instead of stopping at it
        "E5:2 D5:1 C5:1 | B4:2 G4:2 | A4:1 B4:1 C5:1 E5:1 | D5:2 r:1 G4:.5 F#4:.5",
    ]

    # harp, simple: two long low notes a bar (root, then the fifth below),
    # under the flute; rich: a three-note figure dripping down each chord
    def harp_low(b, sym, d):
        r = bass_of(sym.split("/")[0], pitch("E3"))
        if d >= 4:
            harp.note(b, 2, r, 56, legato=2.0)
            harp.note(b + 2, 2, r - 5, 46, legato=2.0)
        else:
            harp.note(b, d, r, 52, legato=2.0)
        harp.pedal(b)

    def harp_drip(b, sym, d):
        v = voicing(sym, pitch("E3"), 4)
        hi = sorted(v)[-3:]
        for k, off in enumerate((0.0, 0.75, 1.5)):
            if off < d:
                harp.note(b + off, min(1.5, d - off), hi[2 - k] + 12, 58 - k * 6, legato=2.5)
        if d >= 4:
            harp.note(b + 3.0, 1.0, v[0] + 12, 40, legato=2.5)
        harp.pedal(b)

    def pass_(t0, rich):
        # harp: the rich pass drips until its last two bars, then goes low
        for i, item in enumerate(prog):
            fn = harp_drip if rich and i < 14 else harp_low
            chords(None, t0 + i * bar, [item], bar, fn)
        # cello: the E pedal, re-bowed every four bars, then the roots, one
        # held B through the last bar
        for k in range(2):
            cello.note(t0 + k * 4 * bar, 4 * bar, pitch("E2"), 64, legato=1.0)
        roots(cello, t0 + 8 * bar, prog[8:15] + ["Bm"], bar, pitch("C2"), vel=62, legato=1.0)
        for k in range(4):
            cello.ramp(t0 + k * 4 * bar, 2 * bar, 11, 64, 98, 8)
            cello.ramp(t0 + k * 4 * bar + 2 * bar, 2 * bar, 11, 98, 64, 8)
        # pizzicato heartbeat
        def pizz_bar(b, sym, d):
            pizz.note(b, 1, tone(sym, "R", pitch("E1")), 78)
            if d >= 4:
                pizz.note(b + 2.5, .5, tone(sym, "5", pitch("E1")), 56)
        chords(None, t0, prog, bar, pizz_bar)
        # flute
        fl.tones(t0, S(pitch("E4")), S_44, vel=74)
        fl.line(t0 + 4 * bar, melody[1], vel=72)
        fl.line(t0 + 8 * bar, melody[2] + " | " + melody[3], vel=76 if rich else 74)
        # low strings: one long counter-note a bar
        low.line(t0, "B3:4 | C4:4 | B3:4 | B3:4 | G3:4 | A3:4 | A3:4 | F#3:4 | "
                     "C4:4 | B3:4 | A3:4 | G3:4 | C4:4 | E4:4 | C4:4 | B3:4", vel=60, legato=1.0)
        # choir: two notes of each chord simple, three rich
        def hum(b, sym, d):
            v = voicing(sym, pitch("B3"), 3)
            choir.block(b, v if rich else [v[0], v[-1]], d, 50 if rich else 46)
        chords(None, t0, prog, bar, hum)
        choir.ramp(t0, 4 * bar, 11, 0, 96 if rich else 88, 12)
        choir.ramp(t0 + 12 * bar, 4 * bar, 11, 96 if rich else 88, 0, 12)
        # everyone eases down over the last bar and back up over the first,
        # so every seam is the softest point on both sides of it
        for tr_ in (fl, low, pizz, harp):
            tr_.ramp(t0, bar, 11, 78, 100, 6)
            tr_.ramp(t0 + 15 * bar, bar, 11, 100, 78, 6)

    pass_(0, False)
    s.mark(0, "Simple")
    pass_(R, True)
    s.mark(R, "Rich")

    # the rich pass's own voices: they swell in from nothing, and are gone
    # again before its last bar
    clar.line(R + 8 * bar, melody[2] + " | E5:2 D5:1 C5:1 | B4:2 G4:2", vel=70, tr=-12)   # stops 2 bars early
    clar.ramp(R + 12 * bar, 2 * bar, 11, 100, 40, 8)
    clar.cc(R + 8 * bar, 11, 100)
    pad(trem, R, prog[:15], bar, pitch("E4"), vel=44, n=3, swell=False)
    trem.ramp(R, 2 * bar, 11, 0, 90, 8)
    for k in range(1, 3):
        trem.ramp(R + k * 4 * bar - 2 * bar, 2 * bar, 11, 90, 50, 8)
        trem.ramp(R + k * 4 * bar, 2 * bar, 11, 50, 90, 8)
    trem.ramp(R + 11 * bar, 4 * bar, 11, 90, 0, 12)
    horns.line(R + 8 * bar, "E3:1 B3:1 D4:2 | E4:1.5 F4:.5 G4:2 | F4:2 D4:2 | B3:4 | C3:4 | C3:4 | C3:3", vel=66)
    horns.cc(R + 8 * bar, 11, 100)
    horns.ramp(R + 12 * bar, 3 * bar, 11, 100, 0, 12)
    s.end(2 * R)
    s.loop(0)
    return s


# ======================================================================
# 02 A Door Opens — the five intro stings.
# ======================================================================
def stings_intro():
    cells = {
        "turnkey": (["G4", "Ab4", "A4", None, "D4"], "Gm", "G2"),
        "pendulum": (["D5", "A4", "D5", "A4"], "Dm", "D2"),
        "prism": (["B3", "F#4", "C#5", "G#5"], "Bm", "B1"),
        "hourglass": (["A4", "G#4", "G4", "F#4", "F4", "E4"], "A", "A1"),
        "mirror": (["E5", "A4", "F#4"], "Em", "E2"),
    }
    out = []
    for k, (cell, sym, low) in cells.items():
        s = Song(f"intro_{k}", f"A Door Opens ({k})", 100)
        timp = s.track("Timpani", TIMPANI, reverb=70)
        brass = s.track("Brass", BRASS, reverb=70)
        low_b = s.track("Low Brass", TROMBONE, reverb=70)
        for i in range(16):
            timp.note(i * 0.25, 0.25, pitch(low) + 12, 36 + i * 5, legato=1.0)
        brass.block(4, voicing(sym, pitch("G3"), 4), 1.5, 112)
        b = 4.0
        for n in cell:
            if n:
                low_b.note(b, 0.5, pitch(n) - 12, 104)
                brass.note(b, 0.5, pitch(n), 96)
            b += 0.5
        timp.note(4, 2, pitch(low) + 12, 120)
        s.end(b + 2.0)
        out.append(s)
    return out


# ======================================================================
# 03 Lock, Stock & Turnkey — G minor, 126, acid-jazz funk, 3 phases.
# ======================================================================
def turnkey():
    s = Song("03_turnkey", "Lock, Stock & Turnkey", 126)
    # the shared palette: harp and piano for the key cell, piano comping,
    # pizzicato for the funk, clarinet and flute leads, horns for the stabs
    harpsi = s.track("Harp", HARP, pan=84, reverb=70, vol=92)
    glock = s.track("Piano High", PIANO, pan=96, reverb=70, vol=74)
    rhodes = s.track("Piano", PIANO, pan=44, reverb=60, vol=88)
    clav = s.track("Pizz Strings", PIZZ, pan=80, reverb=50, vol=80)
    bass = s.track("Pizz Bass", PIZZ, pan=64, reverb=40, vol=108)
    sax = s.track("Clarinet", CLARINET, pan=70, reverb=70)
    tpt = s.track("Flute", FLUTE, pan=56, reverb=70, vol=92)
    ten = s.track("Cello", CELLO, pan=76, reverb=70, vol=90)
    brass = s.track("Horns", HORN, pan=50, reverb=70, vol=92)
    kit = s.track("Drums", 0, drums=True)
    for t in (rhodes, clav, bass, sax, tpt, ten, kit):
        t.swing = 0.12
    bar = 4.0
    prog = ["Gm9", "C9", "Gm9", ("Ebmaj7", "D7#9")]
    cell = "G5:.25 Ab5:.25 A5:.25 r:.75 D5:.5"   # three clicks up, then the bolt drops

    def groove(b, n, busy=False, crash=True):
        for i in range(n):
            pats = {
                KICK: "X.....x..xX....." if i % 2 == 0 else "X.....x...X..x..",
                SNARE: "....X..o.o..X..o",
                HAT: "xoxoxoxoxoxoxoxo" if busy else "x.x.x.x.x.x.x.xo",
            }
            if not busy:
                pats[OHAT] = "..............x."
            if crash and i % 4 == 0:
                pats[CRASH] = "X..............."
            kit.grid(b + i * bar, pats)

    def bass_bar(b, sym, d, runs=False):
        lo = pitch("E1")
        if runs:
            for i in range(int(d / 0.25)):
                bass.note(b + i * 0.25, 0.25, tone(sym, "R", lo) + (12 if i % 2 else 0), 104 if i % 4 == 0 else 84, 0.8)
            return
        hits = [(0, "R", .5, 116), (.75, "8", .25, 96), (1.5, "R", .25, 90), (2, "5", .25, 100),
                (2.5, "7", .25, 92), (2.75, "8", .25, 98), (3.5, "R", .25, 86)]
        for off, tok, ln, v in hits:
            if off < d:
                bass.note(b + off, ln, tone(sym, tok, lo), v, 0.85)

    def comp(b, sym, d):
        v = voicing(sym, pitch("F3"), 4)
        for off, ln in [(0.75, .25), (1.5, .5), (2.75, .25), (3.5, .5)]:
            if off < d:
                rhodes.block(b + off, v, ln, 78)

    def clav_bar(b, sym, d):
        v = voicing(sym, pitch("C4"), 3)
        for i in range(int(d / 0.25)):
            if i % 4 in (1, 2, 3) and i % 8 != 4:
                clav.block(b + i * 0.25, v, 0.2, 70 if i % 2 else 58)

    lead1 = ("G4:.5 r:.25 D5:.75 F5:.5 G5:1 r:1 | A5:.25 Bb5:.75 A5:.5 G5:.5 F5:1 r:1 | "
             "G5:.5 F5:.25 D5:.75 r:.5 Bb4:.5 C5:.5 D5:1 | Eb5:1 D5:.5 C5:.5 F#5:1 r:1 | "
             "D5:.5 G5:.5 Bb5:.75 A5:.25 G5:1 r:1 | F5:.5 G5:.25 A5:.75 C6:1 Bb5:.5 A5:1 | "
             "G5:.25 F5:.25 D5:.5 F5:.5 G5:2.5 | r:1 Eb5:.5 F5:.5 F#5:.5 A5:.5 C6:1")
    lead2 = lead1.rsplit("|", 1)[0] + "| r:1 D5:.5 F#5:.5 A5:.5 C6:.5 D6:1"

    t = 0.0
    s.mark(t, "Intro")
    for i in range(2):
        harpsi.line(t + i * bar, cell, vel=96)
        harpsi.line(t + i * bar + 2, cell, vel=90)
    harpsi.line(t + 2 * bar, cell, vel=100)
    rhodes.block(t + 2 * bar + 2, voicing("Gm9", pitch("F3"), 4), 2, 70)
    kit.grid(t + 3 * bar, {SNARE: "xxxxxxxxXXXXXXXX", TOM_HI: "........x.x.....", TOM_LO: "............x.xX",
                           KICK: "X.......X......."})
    t += 4 * bar

    # P1: the heist groove; the sax plays S in G minor, funked up
    s.mark(t, "P1")
    loop_from = t
    for rep in range(4):
        chords(None, t + rep * 4 * bar, prog, bar, lambda b, sym, d: (bass_bar(b, sym, d), comp(b, sym, d)))
    groove(t, 16)
    sax.line(t, lead1, vel=92, tr=-12)
    sax.line(t + 8 * bar, lead2, vel=96, tr=-12)
    for i in range(0, 16, 4):
        glock.line(t + i * bar + 3 * bar + 2, cell, vel=70)
    t += 16 * bar

    # P2: the Blades — brass doubles, octave-run bass, clav, crashes
    s.mark(t, "P2")
    for rep in range(4):
        chords(None, t + rep * 4 * bar, prog, bar, lambda b, sym, d: (bass_bar(b, sym, d, runs=rep % 2 == 1), comp(b, sym, d), clav_bar(b, sym, d)))
    groove(t, 16, busy=False)
    sax.line(t, lead1, vel=98, tr=-12)
    tpt.line(t, lead1, vel=96)
    ten.line(t, lead1, vel=88, tr=-12)
    sax.line(t + 8 * bar, lead2, vel=102, tr=-12)
    tpt.line(t + 8 * bar, lead2, vel=100)
    ten.line(t + 8 * bar, lead2, vel=92, tr=-12)
    for i in range(16):
        sym = prog[i % 4] if not isinstance(prog[i % 4], tuple) else prog[i % 4][0]
        brass.block(t + i * bar + 3.5, voicing(sym, pitch("Bb3"), 3), .25, 104)
    t += 16 * bar

    # P3: the Combination — a 5/4 bar in every four (the dial's extra
    # click), 16th hats, the brass climbing the key cell chromatically
    s.mark(t, "P3")
    for rep in range(4):
        for i, sym in enumerate(prog):
            d = 5.0 if i == 3 else bar
            if i == 3:
                s.meter(t, 5, 4)
                chords(None, t, [("Ebmaj7", "D7#9")], 4.0, lambda b, sy, dd: (bass_bar(b, sy, dd, runs=True), comp(b, sy, dd)))
                kit.grid(t, {KICK: "X.....x..xX.........", SNARE: "....X..o.o..X...XXXX", HAT: "xoxoxoxoxoxoxoxoxoxo"})
                climb = ["G4", "Ab4", "A4", "Ab4", "A4", "Bb4", "A4", "Bb4", "B4", "D5"]
                for k, n in enumerate(climb):
                    brass.note(t + 2.5 + k * 0.25, 0.25, pitch(n), 96 + k * 2)
                harpsi.line(t + 3, cell, vel=100)       # the cell fills the bar's last two beats
                glock.line(t + 3, cell, vel=86)
                # the dial's extra beat holds the D7#9, so the loop lands V -> i
                bass.note(t + 4, 1, pitch("D2"), 104, .9)
                rhodes.block(t + 4, voicing("D7#9", pitch("F3"), 4), 1, 80)
            else:
                if i == 0:
                    s.meter(t, 4, 4)
                bass_bar(t, sym, d, runs=rep >= 2)
                comp(t, sym, d)
                clav_bar(t, sym, d)
                kit.grid(t, {KICK: "X.....x..xX.....", SNARE: "....X..o.o..X..o", HAT: "xoxoxoxoxoxoxoxo",
                             CRASH: "X..............." if i == 0 else "................"})
            t += d
    # the sax plays S in fragments over P3's first and third phrases
    p3 = t - (4 * (3 * bar + 5.0))
    for k in (0, 2):
        sax.line(p3 + k * (3 * bar + 5), "G5:.5 r:.25 D6:.75 F6:.5 G6:1 r:1 | A6:.25 Bb6:.75 A6:.5 G6:.5 F6:1 r:1 | "
                                           "G6:.5 F6:.25 D6:.75 r:.5 Bb5:.5 C6:.5 D6:1", vel=100, tr=-12)
        tpt.line(p3 + k * (3 * bar + 5), "G5:.5 r:.25 D6:.75 F6:.5 G6:1 r:1 | A6:.25 Bb6:.75 A6:.5 G6:.5 F6:1 r:1 | "
                                           "G6:.5 F6:.25 D6:.75 r:.5 Bb5:.5 C6:.5 D6:1", vel=96, tr=-12)
    orchestral(kit)
    s.end(t)
    s.loop(loop_from)       # the intro plays once; the loop is P1-P3
    return s


# ======================================================================
# 04 Pendulum Waltz in Dust — D minor, 3/4, 180 (one in a bar), 3 phases.
# The tune: S in D minor as a waltz. Its second phrase climbs to a hemiola
# (three two-beat notes across two bars, the G suspended over the bar line)
# and its last bar climbs back into the next phrase. Second time through, the
# flute takes the tune and the violin plays a countermelody under it, then
# the violin takes the climax with the flute an octave below.
# Every phase change is approached, not switched: P1 leads into P2 with a
# snare pickup, the low strings a bar early and a horn swell; P2 and the F
# minor climax each drop their drums and drive two bars before the end and
# fade, so the clockwork and the loop arrive soft.
# ======================================================================
def pendulum():
    s = Song("04_pendulum", "Pendulum Waltz in Dust", 180, 3, 4)
    # the shared palette: harp ticking, a solo violin and flute, choir, horns,
    # high strings, piano for the clockwork, marcato low strings
    harpsi = s.track("Harp", HARP, pan=80, reverb=70, vol=94)
    vln = s.track("Violin", VIOLIN, pan=58, reverb=80)
    strings = s.track("Strings", STRINGS, pan=44, reverb=80, vol=84)
    cello = s.track("Cello & Bass", CELLO, pan=40, reverb=70, vol=100)
    organ = s.track("Choir", CHOIR, pan=64, reverb=100, vol=72)
    celesta = s.track("Piano", PIANO, pan=90, reverb=80, vol=84)
    pizz = s.track("Pizz", PIZZ, pan=30, reverb=60, vol=90)
    gtr = s.track("Low Strings", STRINGS, pan=96, reverb=60, vol=86)
    fl = s.track("Flute", FLUTE, pan=70, reverb=90, vol=88)
    horns = s.track("Horns", HORN, pan=76, reverb=90, vol=84)
    hi_str = s.track("High Strings", SLOWSTR, pan=36, reverb=90, vol=78)
    kit = s.track("Drums", 0, drums=True, vol=96)
    bar = 3.0
    prog = ["Dm", "A7/C#", "Dm/C", "G/B", "Bbmaj7", "Gm6", "A7", "A7",
            "Dm", "Dm/C", "Bbmaj7", "A7", "Gm", "Dm/F", "Em7b5", "A7"]
    tick_tock = lambda sym: [voicing(sym, pitch("D4"), 3)[0], voicing(sym, pitch("D4"), 3)[0] + 7]

    # the tune: S as a waltz, a turn on the held A, a lead-in back up
    mel_a = ("D5:1 A5:.5 C6:1.5 | D6:1 E6:.5 F6:1.5 | E6:1.5 C6:1.5 | A5:2 G5:.5 A5:.5 | "
             "D6:1 C6:.5 Bb5:1.5 | G5:1 Bb5:.5 E6:1.5 | C#6:1.5 A5:1.5 | E5:1 G5:1 A5:1")
    # the climb, the hemiola (Bb G F in halves across bars 13-14, the G held
    # over the bar line onto Dm/F), and a last bar that climbs on
    mel_b = ("F5:1 A5:.5 D6:1.5 | E6:1 F6:.5 G6:1.5 | F6:1.5 D6:1.5 | C#6:1 E6:.5 A6:1.5 | "
             "Bb6:2 G6:2 F6:2 | Bb5:1 G5:.5 E5:1.5 | C#6:2 D6:.5 E6:.5")
    # a countermelody for the violin under the flute's turn with the tune
    counter = "A5:3 | G5:3 | A5:3 | B5:3 | F5:3 | E5:3 | E5:3 | C#5:1.5 E5:1.5"

    def waltz(t0, tr=0, rock=False, vel=1.0, home=False, rich=0, drive_bars=32):
        """32 bars of waltz. The drive (marcato strings, percussion, horn
        hits) plays for the first `drive_bars`, so a phase can let go of it
        before it ends."""
        p = prog * 2
        if home:
            p[-1] = "F#7"       # sounds as A7 a minor third up: V of D minor, home for the loop
        def f(b, sym, d):
            driving = round((b - t0) / bar) < drive_bars
            cello.note(b, 1, bass_of(sym, pitch("D2")) + tr, 96 * vel)
            for k in (1, 2):
                strings.block(b + k, [p_ + tr for p_ in voicing(sym, pitch("F3"), 3)], .5, 66 * vel)
            tt = tick_tock(sym)
            for i in range(6):
                harpsi.note(b + i * 0.5, .5, tt[i % 2] + tr, 80 * vel if i % 2 == 0 else 66 * vel)
            if rock and driving:
                for i in range(6):
                    gtr.block(b + i * 0.5, [bass_of(sym, pitch("D3")) + tr, bass_of(sym, pitch("D3")) + 7 + tr], .45, 92 if i == 0 else 70)
                kit.grid(b, {KICK: "X.....", SNARE: "..X.X."}, steps=2)
            if rich >= 1:
                # high strings hold each chord over the waltz
                hi_str.block(b, [p_ + tr for p_ in voicing(sym, pitch("A4"), 3)], d, 50 * vel)
            if rich >= 2 and driving:
                # horns on the downbeat
                horns.block(b, [p_ + tr for p_ in voicing(sym, pitch("F3"), 3)], 1, 74 * vel)
        chords(None, t0, p, bar, f)
        return t0 + 32 * bar

    def let_go(at, bars, tracks):
        """Fade these tracks down over `bars` bars ending at `at`."""
        for tr_ in tracks:
            tr_.ramp(at - bars * bar, bars * bar, 11, 112, 60, 8)

    def the_tune(t0, tr=0, vel=0, flute_lead=True):
        """The tune twice: violin first; then the flute leads (if flute_lead)
        with the violin's countermelody under it, and the violin takes the
        climax with the flute an octave below."""
        vln.line(t0, mel_a + " | " + mel_b, vel=88 + vel, tr=tr)
        b2 = t0 + 16 * bar
        if flute_lead:
            fl.line(b2, mel_a, vel=86 + vel, tr=tr)
            vln.line(b2, counter, vel=74 + vel, tr=tr, legato=1.0)
        else:
            vln.line(b2, mel_a, vel=92 + vel, tr=tr)
            fl.line(b2, counter, vel=70 + vel, tr=tr + 12, legato=1.0)
        vln.line(b2 + 8 * bar, mel_b, vel=96 + vel, tr=tr)
        fl.line(b2 + 8 * bar, mel_b, vel=80 + vel, tr=tr - 12)
        for i in range(32):
            vln.ramp(t0 + i * bar, bar, 11, 80, 110, 3)

    t = 0.0
    s.mark(t, "P1")
    # the loop comes back soft (the F minor climax lets go to 60), so P1 swells
    # up from there over its first two bars: a mirror of the fade
    for tr_ in (strings, hi_str, fl, organ, gtr, horns, harpsi, cello):
        tr_.cc(0, 11, 60)
        tr_.ramp(0, 2 * bar, 11, 60, 104, 8)
    waltz(t, rich=1)
    the_tune(t)
    organ.line(t + 24 * bar, mel_b, vel=50, tr=-12)     # the choir hums the climax
    # into P2: a soft snare pickup, the low strings a bar early, a horn swell
    kit.grid(t + 31 * bar, {SNARE: "....x.x.xxxx"}, steps=4, vel_scale=0.6)
    for i in range(6):
        gtr.block(t + 31 * bar + i * .5, [pitch("A2"), pitch("E3")], .45, 50 + i * 8)
    horns.block(t + 30 * bar, voicing("A7", pitch("F3"), 3), 2 * bar, 60)
    horns.ramp(t + 30 * bar, 2 * bar, 11, 30, 110, 8)
    t += 32 * bar

    # P2: Rail Rush — marcato strings and percussion; the violin and the low
    # strings trade phrases, horns hit each downbeat, timpani drive
    s.mark(t, "P2")
    for tr_ in (strings, gtr, vln, horns, hi_str, fl):
        tr_.cc(t, 11, 112)
    waltz(t, rock=True, vel=1.08, rich=2, drive_bars=30)
    ha = mel_a.split(" | ")
    hb = mel_b.split(" | ")
    for rep in range(2):
        b0 = t + rep * 16 * bar
        vln.line(b0, " | ".join(ha[:4]), vel=96)
        gtr.line(b0 + 4 * bar, " | ".join(ha[4:]), vel=100, tr=-12)
        vln.line(b0 + 8 * bar, " | ".join(hb[:4]), vel=100)
        gtr.line(b0 + 12 * bar, " | ".join(hb[4:]), vel=104, tr=-12)
        # the flute answers each trade an octave up, softly
        fl.line(b0 + 4 * bar, " | ".join(ha[4:]), vel=70)
        fl.line(b0 + 12 * bar, " | ".join(hb[4:]), vel=74)
    for i in range(0, 32, 8):
        kit.grid(t + i * bar, {CRASH: "X....."}, steps=2)
    # into the clockwork: the drums and drive stop two bars early, and
    # everything fades down to the ticking
    let_go(t + 32 * bar, 4, (strings, gtr, vln, hi_str, fl, harpsi, cello))
    t += 32 * bar

    # P3: Clockwork — piano and pizz ticking alone, the harp and high strings
    # shimmering over them; then the orchestra slams back a minor third up,
    # in F minor, at its fullest
    s.mark(t, "P3")
    for tr_ in (harpsi, cello, strings):
        tr_.cc(t, 11, 104)
    for i, sym in enumerate(prog[:8]):
        b = t + i * bar
        tt = tick_tock(sym)
        for k in range(6):          # eighths: at 180 the ticking reads, not blurs
            celesta.note(b + k * 0.5, .5, tt[k % 2] + 12, 84 if k % 2 == 0 else 62)
        pizz.note(b, 1, bass_of(sym, pitch("D2")), 90)
        pizz.note(b + 1.5, .5, bass_of(sym, pitch("D2")) + 7, 70)
        hi_str.block(b, voicing(sym, pitch("A4"), 3), bar, 38)
        if i % 2 == 0:
            harpsi.note(b, 1.5, voicing(sym, pitch("D5"), 3)[-1], 56, legato=2.0)
    hi_str.ramp(t, 8 * bar, 11, 40, 100, 12)
    # into F minor: a snare roll with the strings swelling under it
    kit.grid(t + 6 * bar, {SNARE: "x...x...x.x."}, steps=4, vel_scale=0.6)
    kit.grid(t + 7 * bar, {SNARE: "xxxxxxXXXXXX", TOM_LO: "...........X"}, steps=4)
    strings.block(t + 6 * bar, voicing("A7", pitch("E3"), 4), 2 * bar, 60)
    strings.ramp(t + 6 * bar, 2 * bar, 11, 40, 120, 10)
    t += 8 * bar
    s.mark(t, "P3 (F minor)")
    for tr_ in (strings, gtr, vln, horns, hi_str, fl, organ, harpsi, cello):
        tr_.cc(t, 11, 116)
    waltz(t, tr=3, rock=True, vel=1.12, home=True, rich=2, drive_bars=30)
    the_tune(t, tr=3, vel=12, flute_lead=False)
    organ.line(t, mel_a + " | " + mel_b, vel=70, tr=3 - 12)
    gtr.line(t + 16 * bar, mel_a + " | " + mel_b, vel=96, tr=3 - 12)
    # back to the start: the drums and drive stop two bars early and the
    # climax fades, so the loop arrives at a soft waltz
    let_go(t + 32 * bar, 4, (strings, gtr, vln, hi_str, fl, organ, harpsi, cello, horns))
    t += 32 * bar
    orchestral(kit)
    s.end(t)
    s.loop(0)
    return s


# ======================================================================
# 05 Refraction — B minor, 152, 7/8 and 4/4, six phases.
# ======================================================================
def prism():
    s = Song("05_prism", "Refraction", 152, 7, 8)
    # the shared palette: piano and harp split the light into fifths, cello
    # carries the bass, marcato low strings the riff, horns the held chords,
    # flute the lead
    bells = s.track("Piano", PIANO, pan=90, reverb=90, vol=84)
    arp = s.track("Harp", HARP, pan=30, reverb=90, vol=74)
    bass = s.track("Cello & Bass", CELLO, pan=64, reverb=60, vol=104)
    gtr = s.track("Low Strings", STRINGS, pan=96, reverb=60, vol=88)
    organ = s.track("Horns", HORN, pan=40, reverb=80, vol=80)
    choir = s.track("Choir", CHOIR, pan=64, reverb=100, vol=92)
    strings = s.track("Strings", STRINGS, pan=50, reverb=80, vol=88)
    lead = s.track("Flute", FLUTE, pan=70, reverb=80, vol=88)
    kit = s.track("Drums", 0, drums=True)
    meters = [3.5, 3.5, 3.5, 4.0, 3.5, 3.5, 3.5, 4.0]
    prog = ["Bm", "Gmaj7", "Em9", ("F#7sus4", "F#7"), "Bm", "Gmaj7#11", "A", "F#7"]

    def fifths(sym, lo):
        r = bass_of(sym.split("/")[0], lo)
        return [r, r + 7, r + 14, r + 21]

    def section(t0, phase, key=0):
        b = t0
        for i, (L, item) in enumerate(zip(meters, prog)):
            # a lifted section turns back home on its last bar: F#7, V of B minor
            tr = 0 if key and i == len(meters) - 1 else key
            s.meter(b, 7, 8) if L == 3.5 else s.meter(b, 4, 4)
            syms = item if isinstance(item, tuple) else (item,)
            main = syms[0]
            # bells: the stacked-fifths cell, in eighths, always
            fv = [p + tr for p in fifths(main, pitch("B4"))]
            for k in range(int(L / 0.5)):
                bells.note(b + k * 0.5, .5, fv[k % 4], 80 if k in (0, 2, 4) else 62, legato=2.0)
            # bass on the 2+2+3 groups (4/4 bars: straight eighths)
            groups = [0, 1, 2] if L == 3.5 else [0, 1, 2, 3]
            for g, off in enumerate(groups):
                sym = syms[min(len(syms) - 1, int(off / (L / len(syms))))]
                r = bass_of(sym, pitch("C2")) + tr
                bass.note(b + off, .5, r, 108)
                bass.note(b + off + .5, .5, r + 12, 80)
                if L == 3.5 and g == 2:
                    bass.note(b + off + 1.0, .5, r + 7, 86)
            if phase >= 2:
                for off in groups:
                    sym = syms[min(len(syms) - 1, int(off / (L / len(syms))))]
                    r = bass_of(sym, pitch("B2")) + tr
                    gtr.block(b + off, [r, r + 7, r + 12], .45, 100)
                    gtr.block(b + off + .5, [r, r + 7], .3, 72)
            if phase >= 3:
                for k, sym in enumerate(syms):
                    organ.block(b + k * L / len(syms), [p + tr for p in voicing(sym, pitch("D3"), 4)], L / len(syms), 70)
                for k in range(int(L / 0.25)):
                    arp.note(b + k * 0.25, .25, fv[(k * 3) % 4] - 12, 60 + (16 if k % 2 == 0 else 0))
            if phase >= 5:
                for k, sym in enumerate(syms):
                    v = [p + tr for p in voicing(sym, pitch("B3"), 4)]
                    for j in range(int(L / len(syms) / 0.25)):
                        strings.note(b + k * L / len(syms) + j * 0.25, .25, v[j % len(v)], 74)
            # drums
            n16 = int(L * 4)
            if L == 3.5:
                pats = {KICK: "X...X.........", SNARE: "........X.....", HAT: "x.x.x.x.x.x.x."}
                if phase >= 3:
                    pats = {KICK: "X...X.....x...", SNARE: "....X...X...X.", HAT: "xoxoxoxoxoxoxo"}
                if phase >= 5:
                    pats[KICK2] = "xxxxxxxxxxxxxx"
            else:
                pats = {KICK: "X.....X.X.......", SNARE: "....X.......X.XX", HAT: "x.x.x.x.x.x.x.x."}
                if phase >= 3:
                    pats[HAT] = "xoxoxoxoxoxoxoxo"
                if phase >= 5:
                    pats[KICK2] = "xxxxxxxxxxxxxxxx"
            if i == 0:
                pats[CRASH] = "X" + "." * (n16 - 1)
            kit.grid(b, pats)
            b += L
        return b

    t = 0.0
    sapphire = S(pitch("B4"))
    for phase in range(1, 7):
        s.mark(t, f"P{phase}")
        tr = 2 if phase == 6 else 0
        if phase >= 4:
            low = [p - 12 for p in sapphire]
            choir.tones(t, low, S_78, vel=86, tr=tr)
            choir.tones(t + 14.5, low, S_78, vel=90, tr=tr)
            if phase < 6:       # sopranos double above, but not once it lifts a tone
                choir.tones(t + 14.5, sapphire, S_78, vel=84, tr=tr)
        if phase in (3, 5, 6):
            lead.line(t, "F#5:1 C#6:1 B5:1.5 | A5:1 F#5:1 E5:1.5 | D5:1 E5:1 F#5:1.5 | C#6:2 A#5:2", vel=92, tr=tr)
        if phase >= 5:
            strings.ramp(t, 29, 11, 70, 120, 16)
        t = section(t, phase, tr)
    orchestral(kit)
    s.end(t)
    s.loop(0)
    return s


# ======================================================================
# 06 Sands of the Last Hour — A Phrygian dominant, 112 -> 124, 2 phases.
# ======================================================================
def hourglass():
    s = Song("06_hourglass", "Sands of the Last Hour", 112)
    # the shared palette: harp for the oud ostinato, flute for the ney, piano
    # for the cimbalom, timpani for the taiko, toms for the hand drums
    oud = s.track("Harp", HARP, pan=40, reverb=70, vol=100)
    ney = s.track("Flute", FLUTE, pan=64, reverb=90)
    cimb = s.track("Piano", PIANO, pan=90, reverb=80, vol=86)
    strings = s.track("Strings", STRINGS, pan=50, reverb=80, vol=84)
    trem = s.track("Tremolo Strings", TREMOLO, pan=76, reverb=80, vol=80)
    cello = s.track("Cello & Bass", CELLO, pan=40, reverb=70, vol=100)
    taiko = s.track("Timpani", TIMPANI, pan=64, reverb=80, vol=110)
    hand = s.track("Hand Drums", 0, drums=True, vol=96)
    bar = 4.0
    A = pitch("A3")
    # the lament: A G# G F# F E over four bars
    prog = ["A", ("E7/G#", "Gm/G"), ("D/F#", "Dm/F"), "E7"]
    maqsum = {CONGA_LO: "X..x..X.........", BONGO_HI: "..x.x....x..x.x.", CONGA_MUTE: "g.......g..g...."}

    def ground(t0, bars, echo=False, vel=1.0):
        for i in range(bars):
            b = t0 + i * bar
            item = prog[i % 4]
            syms = item if isinstance(item, tuple) else (item,)
            for k, sym in enumerate(syms):
                d = bar / len(syms)
                cello.note(b + k * d, d, bass_of(sym, pitch("E2")), 96 * vel)
                cimb.note(b + k * d, d, bass_of(sym, pitch("E4")), 70 * vel, legato=1.5)
            # oud ostinato around the tonic, bending to E on the dominant bar
            root = A if i % 4 != 3 else pitch("E3")
            if i % 4 != 3:
                figure = [0, 0, 1, 0, 4, 0, 1, 0]
            else:
                figure = [0, 0, 1, 0, 4, 0, 6, 4]
            fig = [root + degrees([f], 0, "phrygdom")[0] for f in figure]
            for k in range(16):
                oud.note(b + k * 0.25, .25, fig[k % 8], 92 if k % 4 == 0 else 70)
            hand.grid(b, maqsum, vel_scale=vel)
            taiko.note(b, 1, pitch("A2"), 110 * vel)
            if i % 4 == 3:
                taiko.note(b + 3, .5, pitch("A2"), 90 * vel)
                taiko.note(b + 3.5, .5, pitch("A2"), 100 * vel)
            for k in range(8):
                strings.note(b + k * .5, .5, A + (1 if k % 2 else 0) - (5 if i % 4 == 3 else 0), 64 * vel)
            if echo:
                trem.block(b, [p for p in (A + 12, A + 16, A + 19)] if i % 4 != 3 else [pitch("E4"), pitch("G#4"), pitch("B4")], bar, 70)

    ney_tune = (
        "A4:1.5 E5:.5 G5:2 | A5:1 Bb5:1 C#6:2 | Bb5:1.5 G5:.5 E5:2 | E5:4 | "
        "C#6:.5 D6:.5 C#6:1 Bb5:2 | A5:1 G5:1 F5:2 | E5:.5 F5:.5 G#5:1 A5:2 | G#5:4")
    t = 0.0
    s.mark(t, "P1")
    ground(t, 16)
    ney.line(t + 4 * bar, ney_tune, vel=88)
    t += 16 * bar

    s.mark(t, "P2 (Time Echo)")
    s.tempo(t, 124)
    ground(t, 16, echo=True, vel=1.1)
    ney.line(t, ney_tune, vel=96)
    ney.line(t + 8 * bar, ney_tune, vel=100)
    # every phrase answered a bar later: the boss repeats its attacks
    cimb.line(t + bar, ney_tune, vel=74)
    # the second echo drops its last bar so it can't spill over the loop
    cimb.line(t + 9 * bar, " | ".join(ney_tune.split(" | ")[:7]), vel=78)
    t += 16 * bar
    orchestral(hand)
    s.end(t)
    s.loop(0)

    # Time's Up: a string run to the top, a tutti hit
    tu = Song("hourglass_timesup", "Time's Up", 124)
    st = tu.track("Strings", STRINGS, reverb=70)
    hit = tu.track("Brass", BRASS, reverb=70)
    tk = tu.track("Taiko", TAIKO, reverb=70)
    run = degrees(range(0, 15), pitch("A3"), "phrygdom")
    for k, p in enumerate(run):
        st.note(k * 0.125, .125, p, 70 + k * 3)
    hit.block(2, [pitch("A2"), pitch("E3"), pitch("A3"), pitch("C#4"), pitch("E4")], 2, 120)
    st.block(2, [pitch("A3"), pitch("C#5"), pitch("A5")], 2, 118)
    tk.note(2, 2, pitch("A1"), 127)
    tu.end(4.5)
    return [s, tu]


# ======================================================================
# 07 Mirror, Mirror (Final Exam) — E minor, 160, in song form:
#   Verse (16)       piano: S upside down, over driving strings
#   Pre-chorus (8)   violin: the inversion's head climbing a rising line to D7
#   Chorus (16)      G minor: S the right way up on horns, choir and violin,
#                    then the flute doubling; it turns via Cm6 to B7, home
#   Bridge (16)      chill: the memories as a dream, four bars each in their
#                    own meter and voice over one soft string pad: a walking
#                    Turnkey, a Pendulum waltz, Prism fifths, the Hourglass
#                    flute; it ends soft on B7, back into the verse
# Percussion builds and releases with the form: none in the verse's first
# four bars, a snare build into the chorus, the chorus easing off in its last
# two bars, and a bridge that stays hushed, so no seam slams from full kit
# into the quiet.
# For the game's six phases: verse = P1, bridge memories = P2-P5, chorus = P6.
# ======================================================================
def mirror():
    s = Song("07_mirror", "Mirror, Mirror (Final Exam)", 160)
    pno = s.track("Piano", PIANO, pan=60, reverb=70)
    strings = s.track("Strings", STRINGS, pan=44, reverb=80, vol=96)
    choir = s.track("Choir", CHOIR, pan=64, reverb=100, vol=92)
    horns = s.track("Horns", HORN, pan=76, reverb=80, vol=96)
    bass = s.track("Pizz Bass", PIZZ, pan=64, reverb=40, vol=106)
    gtr = s.track("Low Strings", STRINGS, pan=96, reverb=60, vol=84)
    brass = s.track("Staccato Strings", STRINGS, pan=52, reverb=70, vol=92)
    harpsi = s.track("Harp", HARP, pan=84, reverb=70, vol=90)
    vln = s.track("Violin", VIOLIN, pan=58, reverb=80, vol=96)
    bells = s.track("Piano High", PIANO, pan=90, reverb=90, vol=80)
    ney = s.track("Flute", FLUTE, pan=70, reverb=90, vol=96)
    timp = s.track("Timpani", TIMPANI, pan=64, reverb=70)
    hi_str = s.track("High Strings", SLOWSTR, pan=36, reverb=90, vol=84)
    kit = s.track("Drums", 0, drums=True)
    E = pitch("E4")
    inv = S_inv(pitch("E5"))   # E5 A4 F#4 E4 D4 C#4 D4 F#4 A4
    answer = "E6:1 A5:1 F#5:2 | E5:1.5 D5:.5 C#5:2 | E5:2 G5:2 | F#5:2 D#5:2"

    def drive(t0, prog, bar=4.0, vel=1.0):
        """Strings driving in eighths on the chord roots, octave-jumping."""
        def f(b, sym, d):
            r = bass_of(sym, pitch("E2"))
            for k in range(int(d / 0.5)):
                strings.note(b + k * .5, .5, r + (12 if k % 2 else 0), 84 * vel if k % 4 == 0 else 66 * vel)
            bass.note(b, d, bass_of(sym, pitch("E1")), 100 * vel, 0.9)
        return chords(None, t0, prog, bar, f)

    t = 0.0
    # --- Verse: the motif upside down on piano; percussion from bar 5 ------
    s.mark(t, "Verse")
    verse = ["Em9", "A/C#", "Bm7", "Cmaj7", "Em9", "A/C#", "Cmaj7", "B7"] * 2
    drive(t, verse, vel=0.9)
    pno.tones(t, inv, S_44, vel=90)
    pno.tones(t, [p - 12 for p in inv], S_44, vel=78)
    pno.line(t + 16, answer, vel=94)
    pno.tones(t + 32, inv, S_44, vel=96, tr=12)
    pno.line(t + 48, answer, vel=100)
    pad(choir, t + 32, verse[8:], 4.0, pitch("B3"), vel=64, swell=False)
    choir.ramp(t + 32, 32, 11, 50, 100, 16)
    # second half, richer: a flute countermelody and held low strings
    ney.line(t + 32, "B4:4 | C#5:4 | D5:4 | E5:4 | B4:4 | A4:4 | G4:4 | F#4:4", vel=70, legato=1.0)
    pad(gtr, t + 32, verse[8:], 4.0, pitch("E3"), vel=56, n=3, swell=False)
    for i in range(4, 16):
        kit.grid(t + i * 4, {KICK: "X.......X.......", SNARE: "....x.......x..." if i >= 8 else "............o..."})
    t += 64

    # --- Pre-chorus: the violin climbs; a rising line to D7 ----------------
    s.mark(t, "Pre-Chorus")
    pre = ["Am7", "Bm7", "Cmaj7", "D", "Ebmaj7", "Cm7", "D7sus4", "D7"]
    drive(t, pre, vel=1.0)
    vln.line(t, "E5:1 A4:1 F#5:2 | F#5:1 B4:1 D5:2 | G5:1 C5:1 E5:2 | A5:1 D5:1 F#5:2 | "
                "Bb5:1 Eb5:1 G5:2 | C6:1 G5:1 Eb5:2 | D5:2 G5:2 | A5:2 F#5:2", vel=100)
    vln.ramp(t, 32, 11, 80, 120, 16)
    pad(horns, t + 16, pre[4:], 4.0, pitch("G3"), vel=72, n=3, swell=False)
    horns.ramp(t + 16, 16, 11, 60, 110, 12)
    pad(choir, t, pre, 4.0, pitch("B3"), vel=70, swell=False)
    # the harp runs up each chord, climbing with the violin
    def harp_up(b, sym, d):
        v = voicing(sym, pitch("D4"), 4)
        for k in range(8):
            harpsi.note(b + k * .5, .5, v[k % len(v)] + 12 * (k // len(v)), 60 + k * 3, legato=2.0)
    chords(None, t, pre, 4.0, harp_up)
    for i in range(6):
        kit.grid(t + i * 4, {KICK: "X.......X.......", SNARE: "....x.......x..."})
    # the build: snare eighths then sixteenths, rising, and a timpani roll
    kit.grid(t + 24, {KICK: "X.......X.......", SNARE: "x.x.x.x.x.x.x.x."}, vel_scale=0.8)
    kit.grid(t + 28, {KICK: "X...X...X...X...", SNARE: "xxxxxxxxXXXXXXXX"}, vel_scale=0.9)
    for k in range(16):
        timp.note(t + 28 + k * .25, .25, pitch("D3"), 60 + k * 4, legato=1.0)
    t += 32

    # --- Chorus: S the right way up, in G minor -----------------------------
    # Played twice: after the pre-chorus, and again (final, richest) after the
    # bridge. Both end Cm6 -> B7, easing off, to head home to E minor.
    ch_a = ["Gm9", "Ebmaj7", "Cm9", "D7", "Gm9", "Ebmaj7", "Am7b5", "D7"]
    ch_b = ["Gm9", "Ebmaj7", "Cm9", "D7", "Gm9", "Ebmaj7", "Cm6", "B7"]   # turns home to E minor
    sap = S(pitch("G4"))

    def chorus(t, final):
        prog_all = ch_a + ch_b
        drive(t, prog_all, vel=1.15)
        for half, prog_ in ((0, ch_a), (32, ch_b)):
            b0 = t + half
            horns.tones(b0, [p - 12 for p in sap], S_44, vel=106)
            horns.tones(b0, [p - 24 for p in sap], S_44, vel=96)
            choir.tones(b0, sap, S_44, vel=98)
            vln.tones(b0, [p + 12 for p in sap], S_44, vel=106)
        # richer: the choir's chords under the melody all the way, sustained
        # high strings over the drive, big piano chords, horn harmony
        pad(choir, t, prog_all, 4.0, pitch("B3"), vel=72, n=3, swell=False)
        pad(hi_str, t, prog_all, 4.0, pitch("D5"), vel=64, n=3, swell=False)
        for i, sym in enumerate(prog_all):
            b = t + i * 4
            pno.block(b, [bass_of(sym, pitch("G1")), bass_of(sym, pitch("G1")) + 12], 2, 84)
            pno.block(b, voicing(sym, pitch("G4"), 4), 2, 76)
            pno.block(b + 2.5, voicing(sym, pitch("G4"), 4), 1, 62)
            pno.pedal(b)
        # first time: piano and violin answer; the flute doubles the second
        # half. The answer bends through Cm6 to B7, back to E minor.
        if not final:
            pno.line(t + 16, "Bb5:1 A5:1 G5:2 | G5:1.5 F5:.5 Eb5:2 | Eb5:2 C6:2 | A5:2 F#5:2", vel=106)
            vln.line(t + 16, "Bb6:1 A6:1 G6:2 | G6:1.5 F6:.5 Eb6:2 | Eb6:2 C7:2 | A6:2 F#6:2", vel=108)
        ney.tones(t + (0 if final else 32), [p + 12 for p in sap], S_44, vel=100)
        if final:
            # the final chorus: the flute stays up top through both halves
            ney.line(t + 16, "G6:1 F6:1 Eb6:2 | Eb6:1.5 D6:.5 C6:2 | C6:2 A5:2 | A5:2 F#5:2", vel=96)
            ney.tones(t + 32, [p + 12 for p in sap], S_44, vel=104)
            vln.line(t + 16, "Bb6:1 A6:1 G6:2 | G6:1.5 F6:.5 Eb6:2 | Eb6:2 C7:2 | A6:2 F#6:2", vel=112)
        pno.line(t + 48, "Bb5:1 A5:1 G5:2 | G5:1.5 F5:.5 Eb5:2 | Eb5:2 C6:2 | B5:2 D#6:2", vel=104)
        vln.line(t + 48, "Bb6:1 A6:1 G6:2 | G6:1.5 F6:.5 Eb6:2 | Eb6:2 C7:2 | B6:2 D#6:2", vel=104)
        ney.line(t + 48, "G6:1 F6:1 Eb6:2 | Eb6:1.5 D6:.5 C6:2 | C6:2 A5:2 | F#5:2 B5:2", vel=92)
        # harp arpeggios, a cello countermelody, staccato strings off the beat
        def harp_arp(b, sym, d):
            v = voicing(sym, pitch("G3"), 4)
            for k in range(8):
                harpsi.note(b + k * .5, .5, (v + [p + 12 for p in v])[[0, 1, 2, 3, 4, 3, 2, 1][k]], 66, legato=2.0)
        chords(None, t, ch_a + ch_b[:6], 4.0, harp_arp)
        gtr.line(t, "D3:4 | Eb3:4 | Eb3:4 | F#3:4 | D3:4 | Bb2:4 | C3:4 | C3:2 F#3:2 | "
                    "D3:4 | Eb3:4 | Eb3:4 | F#3:4 | D3:4 | Bb2:4 | Eb3:4 | D#3:4", vel=74, legato=1.0)
        def offbeats(b, sym, d):
            for k in range(4):
                brass.block(b + k + .5, voicing(sym, pitch("G4"), 3), .25, 70)
        chords(None, t, ch_a + ch_b[:6], 4.0, offbeats)
        for i in range(16):
            if i < 14:
                pats = {KICK: "X.......X.......", SNARE: "....X.......X..."}
                if i % 4 == 0 and i < 12:
                    pats[CRASH] = "X..............."
            else:
                pats = {KICK: "X..............."}      # easing off
            kit.grid(t + i * 4, pats)
            if i % 2 == 0 and i < 14:
                timp.note(t + i * 4, 1, bass_of(prog_all[i], pitch("G2")), 104 if i % 4 == 0 else 86)
        timp.note(t + 60, 2, pitch("B2"), 80)
        # the last two bars hold Cm6 -> B7 and let go: everything fades
        # under the answer, so what follows comes in hushed
        for tr_ in (strings, horns, choir, vln, pno, hi_str, ney):
            tr_.cc(t, 11, 120)
            tr_.ramp(t + 56, 8, 11, 120, 64, 8)
        return t + 64

    s.mark(t, "Chorus")
    t = chorus(t, False)

    # --- Bridge: the memories as a dream, chill -------------------------------
    # one soft string pad runs under all four, so they feel like one memory
    # drifting into the next; every voice plays gently
    b0 = t
    for tr_ in (strings, horns, choir, vln, pno):
        tr_.cc(b0, 11, 90)
    s.mark(t, "Bridge: Turnkey")
    # a walking pizzicato bass, soft jazz piano, the key cell on harp
    tk = ["Em9", "A9", "Em9", ("Cmaj7", "B7#9")]
    chords(None, t, tk, 4.0, lambda b, sym, d: [
        bass.note(b + k, 1, tone(sym, tok, pitch("E1")), 74 - k * 4, .9)
        for k, tok in enumerate(["R", "5", "8", "5"][:int(d)])])
    chords(None, t, tk, 4.0, lambda b, sym, d: [
        pno.block(b + off, voicing(sym, pitch("F3"), 4), .9, 52) for off in (1.5, 3.5) if off < d])
    for i in range(4):
        harpsi.line(t + i * 4 + 2, "E5:.5 F5:.5 F#5:.5 r:.5", vel=58)
        kit.grid(t + i * 4, {KICK: "o.......o.......", SNARE: "....g.......g..."})
    pad(strings, t, tk, 4.0, pitch("G3"), vel=40, n=3, swell=False)
    t += 16

    s.mark(t, "Bridge: Pendulum")
    s.meter(t, 3, 4)
    for i, sym in enumerate(["Em", "B7/D#", "Em/D", "A/C#"]):
        b = t + i * 3
        r = voicing(sym, pitch("E4"), 3)[0]
        for k in range(6):
            harpsi.note(b + k * .5, .5, r + (7 if k % 2 else 0), 64 if k % 2 == 0 else 50, legato=1.5)
        bass.note(b, 3, bass_of(sym, pitch("E1")), 70, .95)
        strings.block(b, voicing(sym, pitch("G3"), 3), 3, 42)
    vln.tones(t, inv, S_68, vel=78)
    t += 12

    s.mark(t, "Bridge: Prism")
    s.meter(t, 7, 8)
    for i, sym in enumerate(["Em", "Cmaj7", "Am", "B"]):
        b = t + i * 3.5
        r = bass_of(sym, pitch("E4"))
        fv = [r, r + 7, r + 14, r + 21]
        for k in range(7):
            bells.note(b + k * .5, .5, fv[k % 4], 62 if k in (0, 2, 4) else 48, legato=2.5)
        bass.note(b, 3.5, bass_of(sym, pitch("E1")), 68, .95)
        gtr.block(b, [bass_of(sym, pitch("E2")), bass_of(sym, pitch("E2")) + 7], 3.5, 50)
        strings.block(b, voicing(sym, pitch("G3"), 3), 3.5, 40)
        kit.grid(b, {KICK: "o............."})
    vln.tones(t, inv[:5], [1, 1, 1.5, 1, 9.5], vel=66)
    t += 14

    # the Hourglass memory, then the lift: its last two bars swing round to
    # D7 (V of G minor) with a snare and timpani roll, a string run, a harp
    # sweep and a horn swell, into the final chorus
    s.mark(t, "Bridge: Hourglass")
    s.meter(t, 4, 4)
    hg = ["E", ("Dm/F", "E/G#"), "Ebmaj7", ("D7sus4", "D7")]
    chords(None, t, hg[:2], 4.0, lambda b, sym, d: (bass.note(b, d, bass_of(sym, pitch("E1")), 76),
                                                    strings.block(b, voicing(sym, pitch("G#3"), 3), d, 50)))
    for i in range(2):
        kit.grid(t + i * 4, {CONGA_LO: "o.....o.........", BONGO_HI: "....g.......g..."})
    ph = degrees(S_DEG, E, "phrygdom")
    ney.tones(t, ph[:6], S_44[:6], vel=80)
    ney.line(t + 8, "F5:2 D5:2 | A4:2 C5:1 D5:1", vel=88)
    lift = t + 8
    chords(None, lift, hg[2:], 4.0, lambda b, sym, d: (bass.note(b, d, bass_of(sym, pitch("E1")), 90),
                                                       strings.block(b, voicing(sym, pitch("G3"), 4), d, 70),
                                                       horns.block(b, voicing(sym, pitch("G3"), 3), d, 70)))
    for tr_, lo_, hi_ in ((strings, 70, 120), (horns, 40, 120), (hi_str, 40, 110)):
        tr_.ramp(lift, 8, 11, lo_, hi_, 12)
    pad(hi_str, lift, hg[2:], 4.0, pitch("D5"), vel=56, n=3, swell=False)
    kit.grid(lift, {KICK: "X.......X.......", SNARE: "....x...x.x.x.x."}, vel_scale=0.7)
    kit.grid(lift + 4, {KICK: "X...X...X...X...", SNARE: "xxxxxxxxXXXXXXXX"}, vel_scale=0.85)
    for k in range(16):
        timp.note(lift + 4 + k * .25, .25, pitch("D3"), 50 + k * 5, legato=1.0)
    run = degrees(range(0, 15), pitch("D4"), "phrygdom")      # G harmonic minor from D: fits D7
    for k, n in enumerate(run[:14]):                       # strings run up into the chorus
        vln.note(lift + 4 + k * (4 / 14), 4 / 14, n, 70 + k * 3)
    for k in range(16):                                    # harp sweep
        harpsi.note(lift + 6 + k * .125, .5, degrees([k], pitch("D4"), "phrygdom")[0], 60 + k * 3, legato=3.0)
    t += 16

    # --- Final chorus: the richest point, then home to the verse -------------
    s.mark(t, "Final Chorus")
    t = chorus(t, True)
    # the verse starts quiet: the drive and the strings swell back up
    strings.cc(0, 11, 70)
    strings.ramp(0, 16, 11, 70, 110, 8)
    orchestral(kit)
    s.end(t)
    s.loop(0)
    return s


# ======================================================================
# 08-11 Stings
# ======================================================================
def stings():
    out = []
    # 08 Facet Restored — victory, E major
    v = Song("win", "Facet Restored", 100)
    brass = v.track("Brass", BRASS, reverb=70)
    horns = v.track("Horns", HORN, reverb=80)
    strings = v.track("Strings", STRINGS, reverb=80)
    timp = v.track("Timpani", TIMPANI, reverb=70)
    kit = v.track("Drums", 0, drums=True)
    sap = S(pitch("E4"), "major")
    brass.tones(0, sap[:6], [.5, .5, .5, .5, .5, 1.5], vel=108)
    horns.tones(0, [p - 12 for p in sap[:6]], [.5, .5, .5, .5, .5, 1.5], vel=96)
    prog = ["E", "B/D#", "C#m7", "A", ("B7sus4", "B7"), "E"]
    pad(strings, 0, ["E", "B/D#"], 2.0, pitch("G#3"), vel=80, swell=False)
    brass.line(4, "G#5:1 F#5:1 | E5:1 D#5:1 | E5:4", vel=112)        # S' at last, in the light
    horns.line(4, "B4:1 A4:1 | G#4:1 F#4:1 | G#4:4", vel=100)
    pad(strings, 4, ["C#m7", "B7", "E"], 2.0, pitch("G#3"), vel=86)
    strings.block(8, [pitch("E3"), pitch("B3"), pitch("E4"), pitch("G#4"), pitch("B4")], 4, 96)
    for k in range(16):
        timp.note(6 + k * .125, .125, pitch("B2"), 60 + k * 4, legato=1.0)
    timp.note(8, 2, pitch("E3"), 124)
    kit.grid(8, {CRASH: "X", KICK: "X"})
    v.end(12.5)
    out.append(v)

    # 09 Shattered — defeat
    d = Song("lose", "Shattered", 56)
    pno = d.track("Piano", PIANO, reverb=90)
    low = d.track("Strings", SLOWSTR, reverb=90, vol=84)
    pno.tones(0, S(pitch("E4"))[:5], [1, 1, 1, 1.5, 1.5], vel=70)
    pno.note(6, 4, pitch("B4"), 62)
    pno.bend(6.5, 0.0)
    for k in range(1, 9):
        pno.bend(6.5 + k * 0.25, -0.35 * k / 8)          # the last note sags out of tune
    pno.pedal(0)
    low.block(1, [pitch("E2"), pitch("B2")], 8, 60)
    low.ramp(1, 8, 11, 40, 100, 8)
    low.ramp(7, 3, 11, 100, 0, 6)
    d.end(10.5)
    out.append(d)

    # 10 Sapphire Set — one per stone, each a step brighter
    for n, up in enumerate([0, 2, 4, 5], start=1):
        st = Song(f"place_{n}", f"Sapphire Set {n}", 96)
        harp = st.track("Harp", HARP, reverb=90)
        cel = st.track("Celesta", CELESTA, reverb=90)
        run = degrees(range(0, 15), pitch("E4") + up, "major")
        for k, p in enumerate(run):
            harp.note(k * 0.0625, .5, p, 60 + k * 3, legato=3.0)
        cel.tones(1.0, [p + up for p in S(pitch("E6"), "major")[:3]], [.5, .5, 2], vel=90)
        st.end(4.0)
        out.append(st)

    # 11 The Gate Lifts — S's head rising a step at a time
    g = Song("gate_lift", "The Gate Lifts", 84)
    low_b = g.track("Low Brass", TROMBONE, reverb=80)
    choir = g.track("Choir", CHOIR, reverb=100)
    timp = g.track("Timpani", TIMPANI, reverb=70)
    for k, up in enumerate([0, 2, 3, 5]):
        head = [p + up for p in S(pitch("E3"))[:3]]
        low_b.tones(k * 2, head, [.5, .5, 1], vel=86 + k * 8)
        choir.block(k * 2, [h + 12 for h in head], 2, 70 + k * 8)
    choir.block(8, [pitch("B3"), pitch("E4"), pitch("F#4"), pitch("B4")], 4, 100)   # suspended, into the fight
    low_b.block(8, [pitch("B1"), pitch("B2")], 4, 104)
    for k in range(32):
        timp.note(k * 0.25, .25, pitch("E3"), 40 + k * 2, legato=1.0)
    g.end(12.5)
    out.append(g)
    return out


# ======================================================================
# 12 The Green Sapphire Is Whole — the ending, for the credits. Plays once
# and rings out. Piano, strings, flute, horns and choir: the flute backs the
# strings throughout (held top notes, thirds under the violins, unison at
# the climax) and carries the run into E major.
# ======================================================================
def ending():
    s = Song("12_ending", "The Green Sapphire Is Whole", 76)
    pno = s.track("Piano", PIANO, pan=64, reverb=80)
    strings = s.track("Strings", SLOWSTR, pan=48, reverb=90, vol=90)
    vln = s.track("Violins", STRINGS, pan=36, reverb=90, vol=90)
    cello = s.track("Cello & Bass", CELLO, pan=40, reverb=80, vol=96)
    horns = s.track("Horns", HORN, pan=76, reverb=90, vol=92)
    choir = s.track("Choir", CHOIR, pan=64, reverb=100, vol=88)
    flute = s.track("Flute", FLUTE, pan=80, reverb=90, vol=90)
    bar = 4.0

    def lh(b, sym, d, vel=56):
        bass = bass_of(sym, pitch("C2"))
        v = voicing(sym, bass, 3)
        pat = [bass, v[0] + 7, v[0] + 12, v[1] + 12]
        for k in range(int(d / 0.5)):
            pno.note(b + k * .5, .5, pat[[0, 1, 2, 3, 2, 1, 2, 1][k % 8]], vel - (k % 2) * 6, legato=2.0)
        pno.pedal(b)

    t = 0.0
    s.mark(t, "Piano")
    a = ["Em9", "Cmaj7", "G", "D/F#", "Em9", "Am7", "Cmaj7", "B7"]
    chords(None, t, a, bar, lh)
    pno.tones(t, S(pitch("E5")), S_44, vel=74)
    pno.line(t + 16, "G5:2 E5:2 | C5:2 E5:2 | E5:1 D5:1 C5:1 B4:1 | D#5:4", vel=70)
    t += 32

    # strings join; S is answered by S' for the first time
    s.mark(t, "The answer")
    a2 = ["Em9", "Cmaj7", "G", "D/F#", "Cmaj7", "D", "Em", "Em"]
    chords(None, t, a2, bar, lambda b, sym, d: lh(b, sym, d, 60))
    pad(strings, t, a2, bar, pitch("G3"), vel=56)
    roots(cello, t, a2, bar, pitch("C2"), vel=70)
    vln.tones(t, S(pitch("E5")), S_44, vel=82)
    vln.line(t + 16, "G5:2 F#5:2 | E5:2 D5:2 | E5:8", vel=86)     # S'
    flute.line(t, "B5:4 | G5:4 | B5:4 | A5:4", vel=62)            # held over the strings' chords
    flute.line(t + 16, "B5:2 A5:2 | G5:2 F#5:2 | G5:8", vel=72)
    t += 32

    # the turn to E major: bVI - bVII - I
    s.mark(t, "Into the light")
    turn = ["Cmaj7", "D", "Cmaj7", ("D", "E")]
    chords(None, t, turn, bar, lambda b, sym, d: lh(b, sym, d, 64))
    pad(strings, t, turn, bar, pitch("G3"), vel=70)
    roots(cello, t, turn, bar, pitch("C2"), vel=80)
    vln.line(t, "E5:2 G5:2 | A5:2 B5:2 | C6:2 B5:2 | A5:2 G#5:2", vel=92)
    # thirds under the violins, then a run up into the E-major arrival
    flute.line(t, "C5:2 E5:2 | F#5:2 G5:2 | A5:2 G5:2 | F#5:2 "
                  "E5:.25 F#5:.25 G#5:.25 A5:.25 B5:.25 C#6:.25 D#6:.25 E6:.25", vel=80)
    t += 16

    # S+ — the motif in E major, the whole orchestra and choir
    s.mark(t, "Whole")
    maj = ["E", "B/D#", "C#m7", "A", "E/G#", "A", "B7sus4", "B7"]
    climax = ["E", "B7", "C#m", "A", "E", "B7", "E", "E"]
    for prog_, t0 in ((maj, t), (climax, t + 32)):
        chords(None, t0, prog_, bar, lambda b, sym, d: lh(b, sym, d, 70))
        pad(strings, t0, prog_, bar, pitch("G#3"), vel=84)
        pad(choir, t0, prog_, bar, pitch("B3"), vel=80)
        roots(cello, t0, prog_, bar, pitch("C2"), vel=96)
    sp = S(pitch("E5"), "major")
    vln.tones(t, sp, S_44, vel=104)
    horns.tones(t, [p - 24 for p in sp], S_44, vel=98)
    flute.tones(t, sp, S_44, vel=84)
    vln.line(t + 16, "G#6:2 F#6:2 | E6:2 D#6:2 | E6:2 G#6:2 | F#6:2 D#6:2", vel=106)
    horns.line(t + 16, "G#4:2 F#4:2 | E4:2 D#4:2 | E4:2 B4:2 | A4:2 F#4:2", vel=100)
    flute.line(t + 16, "E6:2 D#6:2 | C#6:2 B5:2 | B5:2 E6:2 | D#6:2 B5:2", vel=86)   # thirds under
    t += 32
    vln.tones(t, sp, S_44, vel=112)
    flute.tones(t, sp, S_44, vel=92)                                      # unison at the climax
    choir.tones(t, [p - 12 for p in sp], S_44, vel=100)
    horns.tones(t, [p - 24 for p in sp], S_44, vel=106)
    vln.line(t + 16, "G#6:2 F#6:2 | E6:2 D#6:2 | E6:8", vel=112)          # S'+, resolved
    horns.line(t + 16, "B4:2 A4:2 | G#4:2 F#4:2 | G#4:8", vel=106)
    flute.line(t + 16, "E6:2 D#6:2 | C#6:2 B5:2 | B5:8", vel=94)        # thirds under S'+
    t += 32

    # coda: the piano alone, S in major, ending on Eadd9
    s.mark(t, "Coda")
    coda = ["E", "C#m7", "A", "B7sus4", "E", "Aadd9", "Eadd9", "Eadd9"]
    chords(None, t, coda, bar, lambda b, sym, d: lh(b, sym, d, 48))
    pno.tones(t, sp, S_44, vel=62)
    pno.line(t + 16, "G#5:2 F#5:2 | E5:2 D#5:2 | E5:4 | B5+E6+F#6:4", vel=58)
    strings.block(t + 24, [pitch("E3"), pitch("B3"), pitch("F#4"), pitch("G#4")], 8, 44)
    strings.ramp(t + 24, 8, 11, 90, 0, 8)
    flute.line(t + 24, "G#5:8", vel=50)                                   # one soft held note on the last chord
    flute.ramp(t + 24, 8, 11, 100, 0, 8)
    t += 32
    # plays once, for the credits: a silent bar after the last chord lets it
    # (and the reverb) ring out instead of being cut off
    s.mark(t + bar, "End")
    s.end(t + bar)
    return s


CUES = {
    "title": title, "jail": jail, "intro": stings_intro, "turnkey": turnkey, "pendulum": pendulum,
    "prism": prism, "hourglass": hourglass, "mirror": mirror, "stings": stings, "ending": ending,
}

if __name__ == "__main__":
    for name in sys.argv[1:] or list(CUES):
        made = CUES[name]()
        for song in made if isinstance(made, list) else [made]:
            save(song)
