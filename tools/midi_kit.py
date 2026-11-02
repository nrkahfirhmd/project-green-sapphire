"""A small Standard MIDI File toolkit for composing the score in code.

Stdlib only. Beats are quarter notes everywhere; Song keeps the tempo, meter
and marker maps, Track holds notes and controller curves. See make_music.py
for the score itself and docs/music-bible.md for what it is meant to say.
"""
import random
import struct

PPQ = 480
_LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# chord qualities as intervals above the root
QUAL = {
    "": [0, 4, 7], "m": [0, 3, 7], "5": [0, 7],
    "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "mmaj7": [0, 3, 7, 11],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "dim": [0, 3, 6], "m7b5": [0, 3, 6, 10], "dim7": [0, 3, 6, 9],
    "9": [0, 4, 7, 10, 14], "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14],
    "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "7sus4": [0, 5, 7, 10],
    "7#9": [0, 4, 7, 10, 15], "7b9": [0, 4, 7, 10, 13], "maj7#11": [0, 4, 7, 11, 18],
}

SCALES = {
    "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10], "major": [0, 2, 4, 5, 7, 9, 11],
    "phrygdom": [0, 1, 4, 5, 7, 8, 10], "harmonic": [0, 2, 3, 5, 7, 8, 11],
}


def pitch(s: str) -> int:
    """'F#4' -> 66 (C4 = 60)."""
    n = _LETTERS[s[0]]
    i = 1
    while i < len(s) and s[i] in "#b":
        n += 1 if s[i] == "#" else -1
        i += 1
    return n + 12 * (int(s[i:]) + 1)


def parse(sym: str) -> dict:
    """'Ebmaj7/G' -> {root: 3, ints: [...], bass: 7}."""
    body, _, slash = sym.partition("/")
    root = _LETTERS[body[0]]
    i = 1
    while i < len(body) and body[i] in "#b" and not body[i:].startswith("b5"):
        root += 1 if body[i] == "#" else -1
        i += 1
    root %= 12
    ints = QUAL[body[i:]]
    bass = root
    if slash:
        bass = _LETTERS[slash[0]] + sum(1 if c == "#" else -1 for c in slash[1:])
    return {"root": root, "ints": ints, "bass": bass % 12}


def at_or_above(pc: int, lo: int) -> int:
    return lo + ((pc - lo) % 12)


def voicing(sym: str, lo: int, n: int = 4) -> list:
    """Close voicing of `sym` from its root at or above `lo`, at most n notes
    (the fifth goes first when there are too many)."""
    c = parse(sym)
    ints = list(c["ints"])
    while len(ints) > n and 7 in ints[1:]:
        ints.remove(7)
    ints = ints[:n]
    base = at_or_above(c["root"], lo)
    return [base + i for i in ints]


def bass_of(sym: str, lo: int) -> int:
    return at_or_above(parse(sym)["bass"], lo)


def tone(sym: str, tok: str, lo: int) -> int:
    """A bass-line token on a chord: R (the bass note), 3, 5, 7, 9, 8 (octave),
    or a signed semitone offset from the bass like +2 / -1."""
    c = parse(sym)
    b = at_or_above(c["bass"], lo)
    r = at_or_above(c["root"], b) if c["bass"] != c["root"] else b
    ints = c["ints"]
    if tok == "R":
        return b
    if tok == "8":
        return b + 12
    if tok == "3":
        return r + ints[1]
    if tok == "5":
        return r + 7 if 7 in ints else r + ints[-1]
    if tok == "7":
        sev = [i for i in ints if i in (9, 10, 11)]
        return r + (sev[0] if sev else 12)
    if tok == "9":
        return r + 14
    return b + int(tok)


def chord_pcs(sym: str) -> set:
    c = parse(sym)
    return {(c["root"] + i) % 12 for i in c["ints"]} | {c["bass"]}


def degrees(degs, tonic: int, scale: str) -> list:
    """Scale degrees (0-based, may be negative or beyond 7) to pitches."""
    sc = SCALES[scale]
    out = []
    for d in degs:
        o, k = divmod(d, 7)
        out.append(tonic + 12 * o + sc[k])
    return out


def _vlq(n: int) -> bytes:
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def tick(beat: float) -> int:
    return max(0, int(round(beat * PPQ)))


class Track:
    def __init__(self, song, name, prog, ch, pan=64, reverb=40, vol=100):
        self.song, self.name, self.prog, self.ch = song, name, prog, ch
        self.ev = []
        self.spans = []         # (start, written end) of every note, in beats
        self.rng = random.Random(song.name + name)
        self.tjit = 0.012       # timing looseness, in beats
        self.vjit = 6           # velocity looseness
        self.swing = 0.0        # 0..1: how far odd 16ths lean towards the next
        self.cc(0, 7, vol)
        self.cc(0, 10, pan)
        self.cc(0, 91, reverb)

    def note(self, beat, dur, p, vel=90, legato=0.94):
        if p is None:
            return
        if isinstance(p, str):
            p = pitch(p)
        if not 0 <= p <= 127:
            raise ValueError(f"{self.name}: pitch {p} out of range at beat {beat}")
        s16 = beat * 4.0
        if self.swing and abs(s16 - round(s16)) < 1e-6 and int(round(s16)) % 2 == 1:
            beat += self.swing * 0.25
        on = beat + self.rng.uniform(-self.tjit, self.tjit)
        v = int(max(1, min(127, vel + self.rng.uniform(-self.vjit, self.vjit))))
        t0 = tick(on)
        t1 = max(t0 + 12, tick(beat + dur * legato))
        self.spans.append((beat, beat + dur))
        self.ev.append((t0, 2, bytes([0x90 | self.ch, p, v])))
        self.ev.append((t1, 0, bytes([0x80 | self.ch, p, 0])))

    def cc(self, beat, num, val):
        self.ev.append((tick(beat), 1, bytes([0xB0 | self.ch, num, int(max(0, min(127, val)))])))

    def ramp(self, beat, dur, num, v0, v1, steps=12):
        for i in range(steps + 1):
            f = i / steps
            self.cc(beat + dur * f, num, v0 + (v1 - v0) * f)

    def bend(self, beat, semis, rng=2.0):
        v = int(max(-8192, min(8191, semis / rng * 8192))) + 8192
        self.ev.append((tick(beat), 1, bytes([0xE0 | self.ch, v & 0x7F, v >> 7])))

    def pedal(self, beat):
        """Re-pedal at a chord change: up just before, down just after."""
        self.cc(beat - 0.03, 64, 0)
        self.cc(beat + 0.03, 64, 127)

    # --- phrases ------------------------------------------------------
    def line(self, beat, spec, vel=88, tr=0, legato=0.95, shape=0.35):
        """'E5:1 B4:.5 r:.5 E4+G4:2 |' -> notes; returns the beat after.
        `shape` lifts higher notes a little louder, as a player would."""
        for tok in spec.split():
            if tok == "|":
                continue
            n, d = tok.split(":")
            d = float(eval(d)) if "/" in d else float(d)
            if n != "r":
                for p in n.split("+"):
                    q = pitch(p) + tr
                    self.note(beat, d, q, vel + (q - 72) * shape, legato)
            beat += d
        return beat

    def tones(self, beat, pitches, rhythm, vel=88, legato=0.95, tr=0, shape=0.35):
        """Pitches with a matching list of durations (None = rest)."""
        for p, d in zip(pitches, rhythm):
            if p is not None:
                self.note(beat, d, p + tr, vel + (p + tr - 72) * shape, legato)
            beat += d
        return beat

    def block(self, beat, notes, dur, vel=80, legato=0.97):
        for p in notes:
            self.note(beat, dur, p, vel, legato)

    def arp(self, beat, notes, total, step, order, vel=72, legato=1.6):
        i = 0
        b = beat
        while b < beat + total - 1e-6:
            self.note(b, step, notes[order[i % len(order)] % len(notes)] + 12 * (order[i % len(order)] // len(notes)), vel, legato)
            b += step
            i += 1

    def grid(self, beat, pats: dict, steps=4, vel_scale=1.0):
        """Drum grid: {note: 'X.x.o...'} with X accent, x hit, o ghost, g soft;
        one char per 1/steps beat. Returns the beat after."""
        vels = {"X": 118, "x": 94, "o": 60, "g": 40}
        n = 0
        for note, pat in pats.items():
            pat = pat.replace(" ", "").replace("|", "")
            n = max(n, len(pat))
            for i, c in enumerate(pat):
                if c in vels:
                    self.note(beat + i / steps, 0.2, note, vels[c] * vel_scale, legato=1.0)
        return beat + n / steps


class Song:
    def __init__(self, name, title, bpm, num=4, den=4):
        self.name, self.title = name, title
        self.rng = random.Random(name)
        self.tracks = []
        self.meta = []
        self._ch = 0
        self.length = 0.0
        self.loop_start = None
        self.tempo(0, bpm)
        self.meter(0, num, den)

    def track(self, name, prog, drums=False, **kw):
        if drums:
            ch = 9
        else:
            ch = self._ch
            self._ch += 1
            if ch >= 9:
                ch += 1
            if ch > 15:
                raise ValueError(f"{self.name}: out of MIDI channels at {name}")
        t = Track(self, name, prog, ch, **kw)
        if drums:
            t.tjit = 0.006
        self.tracks.append(t)
        return t

    def tempo(self, beat, bpm):
        us = int(round(60_000_000 / bpm))
        self.meta.append((tick(beat), 0, b"\xFF\x51\x03" + us.to_bytes(3, "big")))

    def meter(self, beat, num, den):
        dd = {1: 0, 2: 1, 4: 2, 8: 3, 16: 4}[den]
        self.meta.append((tick(beat), 1, bytes([0xFF, 0x58, 4, num, dd, 24, 8])))

    def mark(self, beat, text):
        b = text.encode("ascii")
        self.meta.append((tick(beat), 2, b"\xFF\x06" + _vlq(len(b)) + b))

    def end(self, beat):
        self.length = beat

    def loop(self, start=0.0):
        """Loop from `start` to the end. save() marks it (Loop Start / Loop
        End) and, at the loop start, puts back every controller a track
        changes (expression, sustain pedal, pitch bend) to what the first pass
        began with, so the second pass sounds like the first."""
        self.loop_start = start

    def save(self, path):
        chunks = []
        end_tick = tick(self.length)
        name = self.title.encode("ascii", "replace")
        meta = [(0, -1, b"\xFF\x03" + _vlq(len(name)) + name)] + self.meta
        if self.loop_start is not None:
            for at, text in ((self.loop_start, b"Loop Start"), (self.length, b"Loop End")):
                meta.append((tick(at), 2, b"\xFF\x06" + _vlq(len(text)) + text))
        chunks.append(self._chunk(meta, end_tick))
        for t in self.tracks:
            nm = t.name.encode("ascii", "replace")
            head = [(0, -2, b"\xFF\x03" + _vlq(len(nm)) + nm), (0, -1, bytes([0xC0 | t.ch, t.prog]))]
            if self.loop_start is not None:
                head += self._resets(t)
            # nothing may ring past the end of the loop
            # (a let-ring tail past the end is fine; a note written past it isn't)
            clipped = sum(1 for a, b in t.spans if a < self.length and b > self.length + 1e-6)
            if clipped and self.loop_start is not None:
                print(f"   {self.name}/{t.name}: {clipped} notes cut short by the loop end")
            ev = [(min(tk, end_tick), o, b) for tk, o, b in t.ev if tk < end_tick or o == 0]
            if any(b[0] & 0xF0 == 0xB0 and b[1] == 64 for _, _, b in t.ev):
                ev.append((end_tick, 0, bytes([0xB0 | t.ch, 64, 0])))
            chunks.append(self._chunk(head + ev, end_tick))
        with open(path, "wb") as f:
            f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), PPQ))
            for c in chunks:
                f.write(b"MTrk" + struct.pack(">I", len(c)) + c)

    def _resets(self, t):
        """Controller state put back at the loop start (see loop())."""
        at = tick(self.loop_start)
        out = []
        ccs = sorted((tk, b) for tk, _, b in t.ev if b[0] & 0xF0 == 0xB0 and b[1] in (11, 64))
        for num, rest in ((11, 127), (64, 0)):
            used = [(tk, b) for tk, b in ccs if b[1] == num]
            if used:
                first = [b[2] for tk, b in used if tk >= at] or [rest]
                out.append((at, 0, bytes([0xB0 | t.ch, num, first[0] if num == 11 else 0])))
        if any(b[0] & 0xF0 == 0xE0 for _, _, b in t.ev):
            out.append((at, 0, bytes([0xE0 | t.ch, 0, 64])))
        return out

    @staticmethod
    def _chunk(events, end_tick):
        out = bytearray()
        last = 0
        for tk, _, data in sorted(events, key=lambda e: (e[0], e[1])):
            out += _vlq(tk - last) + data
            last = tk
        out += _vlq(max(0, end_tick - last)) + b"\xFF\x2F\x00"
        return bytes(out)
