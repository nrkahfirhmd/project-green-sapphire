"""Cuts the recorded (foley) sounds into media/sfx/, next to make_sfx.py's synth.

The sources are CC0 Freesound previews, kept out of the repo; credits and links
are in media/sfx/CREDITS.md. Put them in one folder as <freesound id>.mp3 and
run:  python3 tools/make_foley.py <source dir> [names...]

Each recipe: (source id, start s, length s, fade in s, fade out s, peak dBFS,
extra ffmpeg filters). Output is 44.1 kHz mono 16-bit wav, peak-normalised.
"""
import os
import subprocess
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "media", "sfx")

RECIPES = {
    # the neck glows and the sand drains: a steady salt/sand pour
    "hourglass_pour": (137259, 1.4, 2.0, 0.08, 0.5, -8.0, "highpass=f=180"),
}


def peak_db(path: str) -> float:
    r = subprocess.run(["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True)
    for line in r.stderr.splitlines():
        if "max_volume" in line:
            return float(line.split(":")[1].split()[0])
    raise RuntimeError("no level for " + path)


def make(src_dir: str, name: str) -> None:
    sid, start, length, fin, fout, peak, extra = RECIPES[name]
    src = os.path.join(src_dir, f"{sid}.mp3")
    out = os.path.join(OUT, name + (".ogg" if name.startswith("amb_") else ".wav"))
    chain = [extra] if extra else []
    chain += [f"afade=t=in:d={fin}", f"afade=t=out:st={length - fout}:d={fout}"]
    tmp = out + ".tmp.wav"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", str(start), "-t", str(length), "-i", src,
                    "-ac", "1", "-ar", "44100", "-af", ",".join(chain), tmp], check=True)
    gain = peak - peak_db(tmp)
    codec = ["-c:a", "libvorbis", "-q:a", "5"] if out.endswith(".ogg") else ["-sample_fmt", "s16"]
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp, "-af", f"volume={gain}dB", *codec, out],
                   check=True)
    os.remove(tmp)
    print(f"{name}: {length:.2f}s, peak {peak} dBFS")


if __name__ == "__main__":
    src_dir, names = sys.argv[1], sys.argv[2:] or list(RECIPES)
    for n in names:
        make(src_dir, n)
