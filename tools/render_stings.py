"""Renders the score's stings (media/sfx/midi/*.mid) to sound effects.

    python3 tools/render_stings.py <soundfont.sf2> [names...]

Each sting is played through FluidSynth with a General MIDI soundfont (the
score was arranged for GeneralUser GS, which is free for any use; it isn't
kept in the repo), then trimmed of trailing silence, faded and peak-levelled
into media/sfx/ as 44.1 kHz stereo wav, where scripts/sfx.gd plays it by
name. A sting named after an existing sound replaces it (win, lose); one with
a dot is a layer that plays on top of it (hourglass_timesup.orch).
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
MIDI = os.path.join(ROOT, "media", "sfx", "midi")
OUT = os.path.join(ROOT, "media", "sfx")
PEAK = -3.0                      # dBFS: as loud as the synthesised moments
# the file each sting becomes, when not its own name
NAMES = {"hourglass_timesup": "hourglass_timesup.orch"}


def peak_db(path: str) -> float:
    r = subprocess.run(["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    for line in r.stderr.splitlines():
        if "max_volume" in line:
            return float(line.split(":")[1].split()[0])
    raise RuntimeError("no level for " + path)


def render(sf2: str, mid: str) -> None:
    name = os.path.basename(mid)[:-4]
    out = os.path.join(OUT, NAMES.get(name, name) + ".wav")
    raw = out + ".raw.wav"
    subprocess.run(["fluidsynth", "-ni", "-q", "-r", "44100", "-g", "0.8", "-F", raw, sf2, mid], check=True)
    # cut the silence FluidSynth leaves after the last note, keep a soft tail
    tmp = out + ".tmp.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af",
                    # (reversed, so the fade-in here is a short fade-out at the cut; a
                    # fade-out after the second areverse would start at 0 and mute it all)
                    "areverse,silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.05,"
                    "afade=t=in:st=0:d=0.05,areverse", tmp], check=True)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", tmp],
                               capture_output=True, text=True).stdout)
    gain = PEAK - peak_db(tmp)
    fade = min(0.4, dur * 0.2)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af",
                    f"volume={gain}dB,afade=t=out:st={dur - fade}:d={fade}", "-ar", "44100", "-ac", "2",
                    "-sample_fmt", "s16", out], check=True)
    os.remove(raw)
    os.remove(tmp)
    print(f"{NAMES.get(name, name)}: {dur:.2f}s, peak {PEAK} dBFS")


if __name__ == "__main__":
    sf2, names = sys.argv[1], sys.argv[2:]
    mids = [os.path.join(MIDI, n + ".mid") for n in names] if names else sorted(glob.glob(os.path.join(MIDI, "*.mid")))
    for m in mids:
        render(sf2, m)
