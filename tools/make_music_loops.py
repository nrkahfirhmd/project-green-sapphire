"""Turns the rendered music (GarageBand bounces) into game-ready loops.

    python3 tools/make_music_loops.py [names...]

The renders live in media/music_src/ (git-ignored, hidden from Godot). Each
runs a little past its last bar: the reverb and release ringing out. A loop
can't keep that tail at its end (the seam would cut it), so it is folded onto
the loop's start, where the same ringing would sound when the music comes
round again, and the file is cut to the exact musical length. Godot then
loops it whole (scripts/music.gd). A cue that plays once (the ending) is
copied as it is.

Loop lengths come from the score's MIDI (tools/make_music.py):
  title   32 bars of 6/8 at 60          = 96.00 s
  jail    32 bars of 4/4 at 72          = 106.67 s
  boss    the Mirror's song form, 282 beats at 160 = 105.75 s
  final   the same form                  = 105.75 s
"""
import array
import os
import subprocess
import sys
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "media", "music_src")
OUT = os.path.join(ROOT, "media", "music")
RATE = 44100

# name: (render in media/music_src, loop length in seconds, or None to play once)
TRACKS = {
    "title": ("green_sapphire_title_screen.wav", 32 * 3 * 60 / 60),
    "jail": ("green_sapphire_jail.wav", 32 * 4 * 60 / 72),
    "boss": ("green_sapphire_all_boss.wav", 282 * 60 / 160),
    "final": ("green_sapphire_final_boss.wav", 282 * 60 / 160),
    "ending": ("green_sapphire_ending.wav", None),
}


def decode(path: str) -> array.array:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "2", "-ar", str(RATE), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    return array.array("h", raw)


def make(name: str) -> None:
    src, loop_s = TRACKS[name]
    a = decode(os.path.join(SRC, src))
    if loop_s is not None:
        n = int(round(loop_s * RATE)) * 2           # samples, stereo interleaved
        if len(a) < n:
            raise ValueError(f"{name}: render is {len(a) / 2 / RATE:.2f}s, shorter than its {loop_s:.2f}s loop")
        out = [float(x) for x in a[:n]]
        tail = a[n:]
        for i, x in enumerate(tail[:n]):            # the ring-out lands on the start
            out[i] += x
        peak = max(1.0, max(abs(x) for x in out))
        scale = min(1.0, 32000.0 / peak)            # never clip where the tail stacks up
        a = array.array("h", (int(x * scale) for x in out))
        note = f"loop {loop_s:.2f}s, {len(tail) / 2 / RATE:.2f}s tail folded in" + (f", scaled {scale:.3f}" if scale < 1 else "")
    else:
        note = "plays once"
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(a.tobytes())
    print(f"{name}: {len(a) / 2 / RATE:.2f}s, {note}")


if __name__ == "__main__":
    for n in sys.argv[1:] or list(TRACKS):
        make(n)
