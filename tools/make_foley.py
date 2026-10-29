"""Cuts the recorded (foley) sounds into media/sfx/, next to make_sfx.py's synth.

The sources are CC0 Freesound clips kept in media/sfx_src/ (git-ignored, and
hidden from Godot by a .gdignore), each named "<freesound id>__...". Credits
and links are in media/sfx/CREDITS.md.

    python3 tools/make_foley.py [names...]

A recipe mixes one or more parts, each cut from a source:
    (source id, start s, length s, at s, gain dB, extra ffmpeg filters)
then fades, peak-normalises and writes 44.1 kHz 16-bit wav: mono, or for a
loop (amb_*, *_loop) stereo, with its end crossfaded into its start so it
repeats without a seam (scripts/sfx.gd sets those to loop; Godot's import
compresses them with QOA). Names with a dot are layers: boss_death.glass plays
together with boss_death (see scripts/sfx.gd).
"""
import array
import glob
import math
import os
import subprocess
import sys
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "media", "sfx_src")
OUT = os.path.join(ROOT, "media", "sfx")
RATE = 44100

# name: (parts, fade in, fade out, peak dBFS)
RECIPES = {
    # --- the Hourglass: sand ---------------------------------------------
    "hourglass_pour": ([(627070, 11.2, 2.0, 0, 0, "highpass=f=150")], .08, .5, -8),
    "hourglass_sandfall": ([(326304, 0.8, 1.0, 0, -2, ""), (683788, 9.15, .6, 0, 0, "lowpass=f=4000")], .005, .35, -6),
    "hourglass_slide": ([(146407, 0.25, 1.3, 0, 0, "highpass=f=120")], .05, .4, -8),
    # sinking: the drag slowed and darkened, a wet suck as it closes
    "hourglass_quicksand": ([(623692, 0.8, 1.6, 0, 0, "asetrate=38400,aresample=48000,lowpass=f=3000"),
                             (447928, 0.0, .7, .55, -4, "asetrate=37485,aresample=44100")], .2, .5, -7),
    "hourglass_crack": ([(806423, 0.0, .7, 0, 0, "")], .002, .3, -6),
    "hourglass_spill": ([(758207, 0.0, 1.1, 0, 0, ""), (326304, 1.0, 1.4, .12, -3, "")], .002, .4, -5),
    # --- the Pendulum: books, the rail, the jammed blade --------------------
    "pendulum_books": ([(509531, 7.55, 1.1, 0, 0, ""), (394912, 2.05, .9, .08, -3, "")], .002, .3, -6),
    "pendulum_rush": ([(832471, 0.0, 1.1, 0, 0, ""), (739577, 0.2, .9, .05, -2, "")], .01, .3, -6),
    "pendulum_jam": ([(386224, 0.0, .6, 0, 0, "")], .001, .25, -7),
    # --- the jail -----------------------------------------------------------
    "gate": ([(578491, 4.4, 2.2, 0, 0, "")], .15, .5, -5),
    "step_1": ([(521590, .08, .3, 0, 0, "highpass=f=90")], .002, .12, -12),
    "step_2": ([(521590, .58, .3, 0, 0, "highpass=f=90")], .002, .12, -12),
    "step_3": ([(521590, 1.15, .3, 0, 0, "highpass=f=90")], .002, .12, -12),
    "step_4": ([(521590, 1.72, .3, 0, 0, "highpass=f=90")], .002, .12, -12),
    # --- layers under synthesised sounds ------------------------------------
    "boss_death.glass": ([(336425, 0.0, 2.6, 0, 0, "")], .001, .8, -8),
    "turnkey_unlock.glass": ([(758207, 0.0, 1.0, 0, 0, "")], .001, .4, -9),
    "death.fall": ([(181177, 6.75, .85, .35, 0, "")], .002, .3, -7),
    "mirror_clash.crack": ([(422623, 0.85, .6, 0, 0, "")], .002, .25, -8),
    # --- loops: ambience beds and the sapphire's hum --------------------------
    "crystal_loop": ([(460416, 30.0, 12.0, 0, 0, "")], 0, 0, -10),
    "amb_jail": ([(530161, 8.0, 22.0, 0, 0, "")], 0, 0, -6),
    "amb_cell1": ([(530161, 60.0, 22.0, 0, 0, "lowpass=f=1800")], 0, 0, -6),            # the shut vault
    "amb_cell2": ([(138259, 30.0, 22.0, 0, 0, "")], 0, 0, -6),                          # the library
    "amb_cell3": ([(530161, 100.0, 22.0, 0, 0, ""), (460416, 10.0, 22.0, 0, -14, "")], 0, 0, -6),   # the cave
    "amb_cell4": ([(402710, 8.0, 22.0, 0, 0, "")], 0, 0, -6),                           # the desert wind
    # the mind: the singing bowls an octave down, under a dark room tone
    "amb_cell5": ([(460416, 40.0, 11.5, 0, 0, "asetrate=24000,aresample=48000"),
                   (530161, 30.0, 23.0, 0, -8, "lowpass=f=800")], 0, 0, -6),
}
XFADE = 2.0   # seconds of crossfade at a loop's seam


def is_loop(name: str) -> bool:
    return name.startswith("amb_") or name.endswith("_loop")


def source(sid: int) -> str:
    hits = glob.glob(os.path.join(SRC, f"{sid}__*"))
    if not hits:
        raise FileNotFoundError(f"no source for Freesound {sid} in {SRC}")
    return hits[0]


def decode(sid, start, length, filters, ch) -> array.array:
    chain = ",".join(f for f in [filters, f"aresample={RATE}"] if f)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(length), "-i", source(sid),
                          "-af", chain, "-ac", str(ch), "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return array.array("h", raw)


def render(name: str) -> str:
    parts, fin, fout, peak = RECIPES[name]
    loop = is_loop(name)
    ch = 2 if loop else 1
    mix: list = []
    for sid, start, length, at, gain, filters in parts:
        a = decode(sid, start, length, filters, ch)
        g = 10 ** (gain / 20)
        off = int(at * RATE) * ch
        if len(mix) < off + len(a):
            mix.extend([0.0] * (off + len(a) - len(mix)))
        for i, s in enumerate(a):
            mix[off + i] += s * g
    frames = len(mix) // ch
    if loop:
        # fold the last XFADE seconds over the first, equal-power
        x = int(XFADE * RATE)
        n = frames - x
        out = mix[:n * ch]
        for i in range(x):
            f = i / x
            a_in, a_out = math.sin(f * math.pi / 2), math.cos(f * math.pi / 2)
            for c in range(ch):
                out[i * ch + c] = mix[i * ch + c] * a_in + mix[(n + i) * ch + c] * a_out
        mix, frames = out, n
    else:
        for i in range(frames):
            t = i / RATE
            g = 1.0
            if fin and t < fin:
                g = t / fin
            if fout and t > frames / RATE - fout:
                g = min(g, max(0.0, (frames / RATE - t) / fout))
            for c in range(ch):
                mix[i * ch + c] *= g
    top = max(1.0, max(abs(s) for s in mix))
    scale = 32767 * 10 ** (peak / 20) / top
    pcm = array.array("h", (int(max(-32768, min(32767, s * scale))) for s in mix))
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{name}: {frames / RATE:.2f}s, {'stereo loop' if loop else 'mono'}, peak {peak} dBFS")
    return wav


if __name__ == "__main__":
    for n in sys.argv[1:] or list(RECIPES):
        render(n)
