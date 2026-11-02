"""Reads the score's MIDI files back with an independent parser and checks them.

    python3 tools/midi_check.py [--roll DIR] [files...]

Per file: valid SMF structure, length in seconds, and per track the note
count and range, notes left hanging, and pitches outside the instrument's
playable range. For melody tracks it reports how often a note struck on a
beat sits a minor second or minor ninth from the bass under it (the clash an
ear notices first). For a file with Loop Start / Loop End markers (every
music cue) it checks the loop runs bar line to bar line, that nothing starts in
the last sliver before the end (it would be clipped), and reports each seam:
the chord at the end of the loop and of each section, and the one it lands on.
--roll writes a piano-roll PNG per file (needs ffmpeg).
Exits non-zero on structural errors or out-of-range notes.
"""
import glob
import os
import subprocess
import sys

MEDIA = os.path.join(os.path.dirname(__file__), "..", "media")
MIDI_DIRS = [os.path.join(MEDIA, "music", "midi"), os.path.join(MEDIA, "sfx", "midi")]
# playable ranges by GM program (inclusive), loosely from orchestration texts
RANGES = {
    0: (21, 108), 4: (28, 103), 6: (29, 89), 7: (36, 96), 8: (60, 108), 9: (65, 108), 10: (60, 108),
    15: (40, 96), 16: (36, 96), 19: (24, 108), 29: (40, 88), 30: (40, 88), 33: (28, 67), 36: (28, 67),
    38: (21, 72), 40: (55, 103), 42: (36, 76), 44: (28, 103), 45: (28, 96), 46: (24, 103), 47: (40, 60),
    48: (28, 103), 49: (28, 103), 52: (40, 86), 56: (52, 86), 57: (34, 72), 60: (34, 77), 61: (34, 84),
    65: (49, 82), 66: (44, 76), 73: (60, 98), 75: (60, 96), 77: (55, 91), 81: (36, 96), 98: (48, 108),
    104: (48, 84), 106: (48, 88), 116: (24, 60),
}
MELODY = ("Sax", "Violin", "Flute", "Ney", "Lead", "Trumpet", "Music Box")


def vlq(data, i):
    n = 0
    while True:
        b = data[i]
        i += 1
        n = (n << 7) | (b & 0x7F)
        if not b & 0x80:
            return n, i


def read(path):
    data = open(path, "rb").read()
    assert data[:4] == b"MThd", "no header"
    fmt, ntrk, ppq = int.from_bytes(data[8:10], "big"), int.from_bytes(data[10:12], "big"), int.from_bytes(data[12:14], "big")
    i = 14
    tracks = []
    tempos = []
    markers = []
    meters = []
    for _ in range(ntrk):
        assert data[i:i + 4] == b"MTrk", "bad track chunk"
        ln = int.from_bytes(data[i + 4:i + 8], "big")
        j, end = i + 8, i + 8 + ln
        tk, status = 0, 0
        tr = {"name": "", "prog": None, "notes": [], "hanging": 0, "ch": None}
        on = {}
        while j < end:
            d, j = vlq(data, j)
            tk += d
            b = data[j]
            if b == 0xFF:
                typ = data[j + 1]
                ml, j2 = vlq(data, j + 2)
                body = data[j2:j2 + ml]
                if typ == 0x03:
                    tr["name"] = body.decode("ascii", "replace")
                elif typ == 0x51:
                    tempos.append((tk, int.from_bytes(body, "big")))
                elif typ == 0x06:
                    markers.append((tk, body.decode("ascii", "replace")))
                elif typ == 0x58:
                    meters.append((tk, body[0], 2 ** body[1]))
                j = j2 + ml
                continue
            if b & 0x80:
                status = b
                j += 1
            kind, ch = status & 0xF0, status & 0x0F
            if kind in (0xC0, 0xD0):
                if kind == 0xC0:
                    tr["prog"] = data[j]
                j += 1
                continue
            a, v = data[j], data[j + 1]
            j += 2
            tr["ch"] = ch
            if kind == 0x90 and v > 0:
                on.setdefault((ch, a), []).append((tk, v))
            elif kind == 0x80 or (kind == 0x90 and v == 0):
                st = on.get((ch, a))
                if st:
                    t0, vel = st.pop(0)
                    tr["notes"].append((t0, tk, a, vel))
        tr["hanging"] = sum(len(v) for v in on.values())
        tr["end"] = tk
        tracks.append(tr)
        i = end
    return {"fmt": fmt, "ppq": ppq, "tracks": tracks, "tempos": sorted(tempos), "markers": sorted(markers),
            "meters": sorted(meters)}


def seconds(song, tk):
    t, last_tk, us = 0.0, 0, 500000
    for at, u in song["tempos"]:
        if at >= tk:
            break
        t += (at - last_tk) * us / song["ppq"] / 1e6
        last_tk, us = at, u
    return t + (tk - last_tk) * us / song["ppq"] / 1e6


def clashes(song):
    """Share of on-beat melody notes a minor 2nd / 9th from the bass."""
    ppq = song["ppq"]
    harmony = [n for t in song["tracks"] if t["ch"] not in (None, 9) and not any(k in t["name"] for k in MELODY)
               for n in t["notes"]]
    out = {}
    for t in song["tracks"]:
        if not any(k in t["name"] for k in MELODY):
            continue
        hits = bad = 0
        for t0, t1, p, _ in t["notes"]:
            if t0 % ppq > ppq * 0.05:
                continue
            under = [q for (a, b, q, _) in harmony if a <= t0 < b]
            if not under:
                continue
            hits += 1
            if (p - min(under)) % 12 == 1:
                bad += 1
        if hits:
            out[t["name"]] = (bad, hits)
    return out


def bar_lines(song, end):
    """Every bar line up to `end`, from the meter map."""
    ppq = song["ppq"]
    meters = song["meters"] or [(0, 4, 4)]
    lines, tk, k = [], 0, 0
    while tk <= end:
        while k + 1 < len(meters) and meters[k + 1][0] <= tk:
            k += 1
        lines.append(tk)
        _, num, den = meters[k]
        tk += int(ppq * 4 * num / den)
    return lines


NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def chord_at(song, tk):
    """Bass note and pitch classes sounding at tick tk (drums left out)."""
    ps = [n[2] for t in song["tracks"] if t["ch"] not in (None, 9) for n in t["notes"] if n[0] <= tk < n[1]]
    if not ps:
        return "-"
    pcs = sorted({p % 12 for p in ps})
    return f"{NOTE_NAMES[min(ps) % 12]}{min(ps) // 12 - 1} [{' '.join(NOTE_NAMES[p] for p in pcs)}]"


def loop_report(song):
    """(problems, seam lines) for a looping file."""
    mk = {m: tk for tk, m in song["markers"]}
    if "End" in mk and "Loop Start" not in mk:
        # plays once (the ending): it just has to finish on a bar line, with
        # its last note done before the End
        end = mk["End"]
        last = max(n[1] for t in song["tracks"] for n in t["notes"])
        problems = [] if end in bar_lines(song, end) else ["End is off the bar line"]
        if last > end:
            problems.append("notes run past the End")
        return problems, [f"plays once: last chord {chord_at(song, last - song['ppq'])}, rings out to the End"]
    if "Loop Start" not in mk or "Loop End" not in mk:
        return ["no Loop Start / Loop End markers"], []
    a, b = mk["Loop Start"], mk["Loop End"]
    ppq = song["ppq"]
    lines = bar_lines(song, b)
    problems = []
    for name, at in (("Loop Start", a), ("Loop End", b)):
        if at not in lines:
            problems.append(f"{name} is off the bar line")
    late = [n for t in song["tracks"] for n in t["notes"] if b - ppq // 8 < n[0] < b]
    if late:
        problems.append(f"{len(late)} notes start in the last 1/32 before the loop end")
    seams = [f"loop: {chord_at(song, b - ppq // 2)} -> {chord_at(song, a + ppq // 4)}"]
    for tk, m in song["markers"]:
        if m not in ("Loop Start", "Loop End") and a < tk < b:
            seams.append(f"{m}: {chord_at(song, tk - ppq // 2)} -> {chord_at(song, tk + ppq // 4)}")
    return problems, seams


def roll(song, path, png):
    ppq = song["ppq"]
    end = max((n[1] for t in song["tracks"] for n in t["notes"]), default=ppq)
    px_per_beat = 8
    w = max(64, int(end / ppq * px_per_beat) + 4)
    lo, hi = 24, 108
    h = (hi - lo) * 3
    img = bytearray([24, 30, 24] * w * h)
    palette = [(105, 160, 98), (187, 226, 182), (150, 200, 120), (90, 140, 200), (220, 180, 90), (200, 110, 110),
               (160, 120, 210), (90, 200, 190), (230, 140, 60), (140, 140, 140)]
    for bt in range(0, int(end / ppq) + 1, 4):
        x = bt * px_per_beat
        for y in range(h):
            if x < w:
                img[(y * w + x) * 3:(y * w + x) * 3 + 3] = bytes([40, 52, 40])
    for k, t in enumerate(song["tracks"]):
        if t["ch"] == 9:
            continue
        col = bytes(palette[k % len(palette)])
        for t0, t1, p, _ in t["notes"]:
            if not lo <= p < hi:
                continue
            y0 = (hi - 1 - p) * 3
            for x in range(int(t0 / ppq * px_per_beat), max(int(t0 / ppq * px_per_beat) + 1, int(t1 / ppq * px_per_beat))):
                for y in (y0, y0 + 1):
                    if 0 <= x < w:
                        img[(y * w + x) * 3:(y * w + x) * 3 + 3] = col
    ppm = png + ".ppm"
    with open(ppm, "wb") as f:
        f.write(f"P6 {w} {h} 255\n".encode() + img)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ppm, png], check=True)
    os.remove(ppm)


def main():
    args = sys.argv[1:]
    roll_dir = None
    if "--roll" in args:
        k = args.index("--roll")
        roll_dir = args[k + 1]
        del args[k:k + 2]
        os.makedirs(roll_dir, exist_ok=True)
    files = args or [f for d in MIDI_DIRS for f in sorted(glob.glob(os.path.join(d, "*.mid")))]
    errors = 0
    for path in files:
        song = read(path)
        end = max(t["end"] for t in song["tracks"])
        name = os.path.basename(path)
        print(f"{name}: {seconds(song, end):.1f}s, {len(song['tracks']) - 1} tracks, "
              f"markers {[m for _, m in song['markers']]}")
        for t in song["tracks"][1:]:
            ps = [n[2] for n in t["notes"]]
            if not ps:
                print(f"   ! {t['name']}: no notes")
                continue
            rng = RANGES.get(t["prog"]) if t["ch"] != 9 else None
            out = [p for p in ps if rng and not rng[0] <= p <= rng[1]]
            flag = ""
            if out:
                flag = f"  OUT OF RANGE x{len(out)} ({min(out)}..{max(out)} vs {rng})"
                errors += 1
            if t["hanging"]:
                flag += f"  HANGING x{t['hanging']}"
                errors += 1
            print(f"   {t['name']:<20} prog {t['prog']!s:>3} ch {t['ch']:>2}  notes {len(ps):>4}  {min(ps)}..{max(ps)}{flag}")
        if os.sep + "music" + os.sep in os.path.abspath(path):
            problems, seams = loop_report(song)
            for s in seams:
                print(f"   ↻ {s}")
            for pr in problems:
                print(f"   ! LOOP: {pr}")
                errors += 1
        for nm, (bad, hits) in clashes(song).items():
            print(f"   ~ {nm}: {bad}/{hits} on-beat notes a minor 2nd/9th over the bass ({100 * bad / hits:.0f}%)")
        if roll_dir:
            roll(song, path, os.path.join(roll_dir, name.replace(".mid", ".png")))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
