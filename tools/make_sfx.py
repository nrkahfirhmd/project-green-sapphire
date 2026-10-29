#!/usr/bin/env python3
"""Synthesises the game's sound effects into media/sfx/<name>.wav.

Stdlib only, no samples: every sound is layered from a few building blocks
(pitch-dropping thumps, filtered-noise whooshes, inharmonic crystal and metal
partials, grain clouds) and run through a small Freeverb. Each sound seeds the
RNG with its own name, so a re-run writes the same files.

    python3 tools/make_sfx.py              # every sound
    python3 tools/make_sfx.py hit_light    # just these

Names match scripts/sfx.gd's Sfx.play() calls, and mostly haptics.gd's
patterns: where a haptic pattern has pulses at fixed times, its sound hits on
the same beats.
"""
import array
import math
import os
import random
import struct
import sys
import wave

SR = 44100
TAU = 2.0 * math.pi
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "media", "sfx")

# partial ratios
GLASS = (1.0, 2.32, 4.25, 6.63, 9.38)          # wine glass / crystal
BAR = (1.0, 2.76, 5.40, 8.93)                  # free bar, a bright "ting"
METAL = (1.0, 2.0, 2.76, 3.3, 5.4, 6.8)        # struck steel, clangy
BELL = (0.5, 1.0, 1.19, 1.5, 2.0, 2.5, 3.0)    # church bell: hum, prime, minor third...


def N(d):
    return max(1, int(round(d * SR)))


def zeros(n):
    return array.array("d", bytes(8 * n))


def curve(v, n, geo=False):
    """Per-sample values from a constant or [(seconds, value), ...] breakpoints.
    geo interpolates geometrically (for frequencies)."""
    if not isinstance(v, (list, tuple)):
        return array.array("d", [float(v)]) * n
    pts = sorted(v)
    out = zeros(n)
    j = 0
    last = len(pts) - 1
    for i in range(n):
        t = i / SR
        while j < last - 1 and t >= pts[j + 1][0]:
            j += 1
        if last == 0:
            out[i] = pts[0][1]
            continue
        t0, v0 = pts[j]
        t1, v1 = pts[j + 1]
        k = 0.0 if t <= t0 else (1.0 if t >= t1 or t1 <= t0 else (t - t0) / (t1 - t0))
        out[i] = v0 * (v1 / v0) ** k if geo else v0 + (v1 - v0) * k
    return out


# --- sources ------------------------------------------------------------------

def noise(d):
    r = random.random
    return array.array("d", (r() * 2.0 - 1.0 for _ in range(N(d))))


def _blep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def tone(d, f, shape="sine"):
    n = N(d)
    fr = curve(f, n, True)
    out = zeros(n)
    p = random.random()
    sin = math.sin
    for i in range(n):
        dt = fr[i] / SR
        if shape == "sine":
            out[i] = sin(TAU * p)
        elif shape == "tri":
            out[i] = 4.0 * abs(p - 0.5) - 1.0
        elif shape == "saw":
            out[i] = 2.0 * p - 1.0 - _blep(p, dt)
        else:  # square
            out[i] = (1.0 if p < 0.5 else -1.0) + _blep(p, dt) - _blep((p + 0.5) % 1.0, dt)
        p += dt
        p -= int(p)
    return out


def fm(d, fc, ratio, index):
    """Two-operator FM: bells and clangs. index may be a curve."""
    n = N(d)
    fr = curve(fc, n, True)
    ix = curve(index, n)
    out = zeros(n)
    pc = pm = 0.0
    sin = math.sin
    for i in range(n):
        out[i] = sin(TAU * pc + ix[i] * sin(TAU * pm))
        pc += fr[i] / SR
        pm += fr[i] * ratio / SR
    return out


def ting(d, f, ratios=GLASS, tau=0.3, bright=0.6, detune=0.0015, attack=0.0008):
    """A struck resonant body: inharmonic partials, each a detuned pair (so it
    shimmers), higher ones dying faster."""
    n = N(d)
    out = zeros(n)
    sin = math.sin
    for k, r in enumerate(ratios):
        amp = bright ** k
        tk = tau / (1.0 + 0.7 * k)
        dec = math.exp(-1.0 / (tk * SR))
        for det in (1.0 - detune, 1.0 + detune):
            fk = f * r * det
            if fk >= SR * 0.45:
                continue
            w = TAU * fk / SR
            ph = random.random() * TAU
            a = amp * 0.5
            for i in range(n):
                out[i] += a * sin(w * i + ph)
                a *= dec
                if a < 1e-5:
                    break
    na = N(attack)
    for i in range(min(na, n)):
        out[i] *= i / na
    return out


def thump(d, f0, f1, tp=0.04, ta=0.12, a=0.001):
    """A kick: a sine whose pitch falls from f0 to f1 (time constant tp) and
    whose level dies with time constant ta."""
    n = N(d)
    out = zeros(n)
    p = 0.0
    exp, sin = math.exp, math.sin
    na = N(a)
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * exp(-t / tp)
        env = (i / na) if i < na else exp(-(t - a) / ta)
        out[i] = sin(TAU * p) * env
        p += f / SR
    return out


def click(d=0.004, hp_f=3000):
    x = svf(noise(d), hp_f, 0.7, "hp")
    n = len(x)
    for i in range(n):
        x[i] *= (1.0 - i / n) ** 2
    return x


def whoosh(d, f, env, q=1.2):
    """Band-passed noise; f and env are breakpoint curves."""
    return shape(svf(noise(d), f, q, "bp"), env)


def grains(d, rate, fmin, fmax, tau=(0.02, 0.1), ratios=GLASS, decay=None, gain=1.0):
    """A cloud of tiny tings: sparkle, shards, glitter. rate is grains per
    second; decay (seconds) makes the cloud thin out over time."""
    out = zeros(N(d))
    t = 0.0
    while True:
        t += random.expovariate(rate)
        if t >= d:
            break
        lvl = math.exp(-t / decay) if decay else 1.0
        g = ting(random.uniform(*tau) * 5, math.exp(random.uniform(math.log(fmin), math.log(fmax))),
                 ratios, tau=random.uniform(*tau), bright=0.5)
        add(out, g, t, gain * lvl * random.uniform(0.4, 1.0))
    return out


def shatter(d, f_lo=1800, f_hi=8000):
    """Breaking crystal: a dense burst of shards and grit, thinning fast."""
    out = grains(d, 260, f_lo, f_hi, (0.015, 0.09), GLASS, decay=d * 0.3)
    grit = shape(svf(noise(d), 4500, 0.6, "hp"), [(0, 1), (0.01, 0.6), (d * 0.5, 0.05), (d, 0)])
    add(out, grit, 0, 0.5)
    return out


def rumble(d, f=90, env=None):
    x = svf(svf(noise(d), f, 0.8, "lp"), f, 0.8, "lp")
    return shape(x, env or [(0, 0), (0.05, 1), (d, 0)])


# --- processing -----------------------------------------------------------------

def svf(x, fc, q=0.707, mode="lp"):
    """Topology-preserving state variable filter; fc may be a curve."""
    n = len(x)
    out = zeros(n)
    k = 1.0 / q
    const = not isinstance(fc, (list, tuple))
    fr = None if const else curve(fc, n, True)
    tan, pi = math.tan, math.pi
    ic1 = ic2 = 0.0
    g = tan(pi * min(float(fc), SR * 0.45) / SR) if const else 0.0
    for i in range(n):
        if not const:
            g = tan(pi * min(fr[i], SR * 0.45) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == "lp":
            out[i] = v2
        elif mode == "bp":
            out[i] = k * v1
        else:
            out[i] = x[i] - k * v1 - v2
    return out


def shape(x, env):
    """Multiply by a breakpoint envelope (or constant)."""
    e = curve(env, len(x))
    for i in range(len(x)):
        x[i] *= e[i]
    return x


def perc(x, a=0.001, tau=0.1):
    na = N(a)
    dec = math.exp(-1.0 / (tau * SR))
    v = 1.0
    for i in range(len(x)):
        if i < na:
            x[i] *= i / na
        else:
            x[i] *= v
            v *= dec
    return x


def drive(x, amt=2.0):
    th = math.tanh
    k = th(amt)
    for i in range(len(x)):
        x[i] = th(x[i] * amt) / k
    return x


def gain(x, g):
    for i in range(len(x)):
        x[i] *= g
    return x


def add(out, x, t=0.0, g=1.0):
    """Mix x into out starting t seconds in, growing out if needed."""
    o = N(t) if t > 0 else 0
    need = o + len(x)
    if need > len(out):
        out.extend(zeros(need - len(out)))
    for i in range(len(x)):
        out[o + i] += x[i] * g
    return out


def mix(*layers):
    """mix((signal, start_seconds, gain), ...)"""
    out = zeros(1)
    for sig, t, g in layers:
        add(out, sig, t, g)
    return out


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x))) or 1e-9


def reverb(x, wet=0.3, size=0.75, damp=0.35, tail=1.2):
    """Mono Freeverb. wet is the reverb's level relative to the dry signal's."""
    n = len(x) + N(tail)
    dry = array.array("d", x) + zeros(n - len(x))
    fb = 0.7 + 0.28 * size
    wetbuf = zeros(n)
    for L in (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617):
        buf = zeros(L)
        idx = 0
        store = 0.0
        for i in range(n):
            y = buf[idx]
            store = y * (1.0 - damp) + store * damp
            buf[idx] = dry[i] + store * fb
            wetbuf[i] += y
            idx += 1
            if idx == L:
                idx = 0
    for L in (556, 441, 341, 225):
        buf = zeros(L)
        idx = 0
        for i in range(n):
            y = buf[idx]
            v = wetbuf[i]
            wetbuf[i] = y - v
            buf[idx] = v + y * 0.5
            idx += 1
            if idx == L:
                idx = 0
    k = wet * rms(x) / rms(wetbuf)
    for i in range(n):
        dry[i] += wetbuf[i] * k
    return dry


def echo(x, t, fb=0.4, taps=3, lp=2500):
    out = array.array("d", x)
    src = x
    for j in range(1, taps + 1):
        src = svf(src, lp, 0.7, "lp")
        add(out, src, t * j, fb ** j)
    return out


def repitch(x, ratio):
    """Resample: ratio > 1 is higher and shorter."""
    n = int(len(x) / ratio)
    out = zeros(n)
    last = len(x) - 1
    for i in range(n):
        p = i * ratio
        j = int(p)
        f = p - j
        out[i] = x[j] * (1.0 - f) + x[min(j + 1, last)] * f
    return out


def save(name, x, peak_db):
    # DC block, trim the silent tail, de-click the ends, set the peak
    y = svf(x, 25, 0.7, "hp")
    peak = max(abs(v) for v in y) or 1.0
    end = len(y)
    while end > 1 and abs(y[end - 1]) < peak * 0.0008:
        end -= 1
    y = y[:end]
    fi, fo = min(N(0.0005), len(y)), min(N(0.012), len(y))
    for i in range(fi):
        y[i] *= i / fi
    for i in range(fo):
        y[len(y) - 1 - i] *= i / fo
    k = 10 ** (peak_db / 20.0) / peak
    data = struct.pack("<%dh" % len(y), *(int(max(-1.0, min(1.0, v * k)) * 32767) for v in y))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    return len(y) / SR


RECIPES = {}


def sfx(peak_db):
    """Registers a recipe; peak_db sets how loud it lands relative to the rest."""
    def reg(fn):
        RECIPES[fn.__name__] = (fn, peak_db)
        return fn
    return reg


# =============================================================================
# Interface
# =============================================================================

@sfx(-17)
def select():
    return mix((ting(0.06, 2600, (1.0, 2.32), tau=0.018), 0, 1), (click(0.003, 6000), 0, 0.4))


@sfx(-12)
def tap():
    return mix((ting(0.2, 1760, GLASS, tau=0.05, bright=0.45), 0, 1),
               (click(0.003, 5000), 0, 0.5),
               (thump(0.05, 700, 300, 0.01, 0.015), 0, 0.35))


@sfx(-12)
def toggle():
    return reverb(mix((ting(0.2, 1318, GLASS, tau=0.06, bright=0.45), 0, 1),
                      (ting(0.25, 1975, GLASS, tau=0.08, bright=0.45), 0.045, 1),
                      (click(0.003), 0, 0.4)), 0.2, 0.4, tail=0.4)


@sfx(-11)
def denied():
    def blip(f):
        return perc(svf(tone(0.07, f, "square"), 1100, 0.9), 0.002, 0.03)
    return mix((blip(196), 0, 1), (blip(175), 0.07, 0.9))


@sfx(-13)
def pause_open():
    w = whoosh(0.28, [(0, 3200), (0.28, 500)], [(0, 0), (0.04, 1), (0.28, 0)], 1.0)
    t = svf(ting(0.5, 880, GLASS, tau=0.2, bright=0.4), 1800, 0.7)
    return reverb(mix((w, 0, 0.6), (t, 0.02, 0.8)), 0.3, 0.5, tail=0.6)


@sfx(-13)
def pause_close():
    w = whoosh(0.22, [(0, 500), (0.22, 3200)], [(0, 0), (0.15, 1), (0.22, 0)], 1.0)
    return reverb(mix((w, 0, 0.6), (ting(0.4, 1318, GLASS, tau=0.12, bright=0.45), 0.12, 0.7)), 0.25, 0.4, tail=0.5)


@sfx(-17)
def fade():
    # 0.18 s out, the swap, 0.28 s in: the air swells to the swap and settles
    w = shape(svf(noise(0.5), [(0, 300), (0.18, 1400), (0.5, 250)], 0.7, "lp"),
              [(0, 0), (0.18, 1), (0.5, 0)])
    return mix((w, 0, 1), (perc(tone(0.5, 110), 0.15, 0.12), 0, 0.25))


@sfx(-4)
def door():
    body = drive(thump(0.6, 150, 42, 0.07, 0.2, 0.004), 1.6)
    air = whoosh(0.45, [(0, 300), (0.45, 120)], [(0, 1), (0.45, 0)], 0.8)
    bell = svf(ting(1.0, 440, BELL, tau=0.5, bright=0.5), 2200, 0.7)
    return reverb(mix((body, 0, 1), (air, 0, 0.5), (bell, 0.01, 0.25)), 0.45, 0.85, tail=1.4)


@sfx(-2)
def intro():
    # the boss's name slams down
    sub = drive(thump(1.4, 95, 30, 0.1, 0.45, 0.002), 2.2)
    crack = perc(svf(noise(0.15), 2000, 0.7, "hp"), 0.0005, 0.03)
    gong = gain(fm(2.0, 110, 1.4, [(0, 6), (1.5, 0.2)]), 1.0)
    perc(gong, 0.002, 0.7)
    bell = ting(2.0, 220, BELL, tau=1.1, bright=0.6)
    return reverb(mix((sub, 0, 1), (crack, 0, 0.5), (gong, 0, 0.35), (bell, 0, 0.4)), 0.5, 0.9, tail=2.2)


# =============================================================================
# The player's rapier and kit
# =============================================================================

def _swing_light_body():
    a = whoosh(0.17, [(0, 1800), (0.045, 5400), (0.17, 2300)], [(0, 0), (0.045, 1), (0.08, 0.45), (0.17, 0)], 1.6)
    b = whoosh(0.17, [(0, 800), (0.05, 1900), (0.17, 900)], [(0, 0), (0.05, 1), (0.17, 0)], 1.0)
    shing = ting(0.15, 5600, (1.0, 1.5, 2.3), tau=0.03, bright=0.5)
    return mix((a, 0, 1), (b, 0, 0.45), (shing, 0.035, 0.12))


def _swing_heavy_release():
    a = whoosh(0.34, [(0, 700), (0.07, 3800), (0.34, 1100)], [(0, 0), (0.07, 1), (0.14, 0.5), (0.34, 0)], 1.3)
    b = whoosh(0.34, [(0, 250), (0.08, 900), (0.34, 300)], [(0, 0), (0.08, 1), (0.34, 0)], 0.9)
    sub = thump(0.3, 130, 55, 0.04, 0.09, 0.01)
    shing = ting(0.25, 4200, (1.0, 1.5, 2.3), tau=0.05, bright=0.5)
    return mix((a, 0, 1), (b, 0, 0.6), (sub, 0.04, 0.45), (shing, 0.05, 0.15))


@sfx(-7)
def swing_light():
    return _swing_light_body()


@sfx(-3)
def swing_heavy():
    # the 0.26 s windup: ticks rising with the haptic pulses, a riser under them
    out = zeros(1)
    for t, f, g in ((0.0, 880, 0.22), (0.09, 1175, 0.3), (0.18, 1568, 0.4)):
        add(out, ting(0.1, f, GLASS, tau=0.025, bright=0.4), t, g)
    add(out, whoosh(0.27, [(0, 400), (0.27, 2600)], [(0, 0), (0.27, 1)], 1.4), 0, 0.35)
    add(out, shape(tone(0.27, [(0, 220), (0.27, 660)]), [(0, 0), (0.27, 1)]), 0, 0.1)
    add(out, _swing_heavy_release(), 0.24, 1.0)
    return out


def _hit(f, big):
    out = mix((click(0.004, 3000), 0, 0.8),
              (thump(0.3 if big else 0.14, 170 if big else 260, 48 if big else 110,
                     0.035 if big else 0.02, 0.12 if big else 0.05), 0, 1.0),
              (drive(perc(svf(noise(0.1), 1800 if big else 2600, 0.8, "bp"), 0.0005, 0.045 if big else 0.02), 3), 0, 0.7))
    for r, g in ((1.0, 0.45), (1.5, 0.3), (2.0, 0.18)) if big else ((1.0, 0.45), (1.5, 0.2)):
        add(out, ting(0.6 if big else 0.35, f * r, GLASS, tau=0.35 if big else 0.12, bright=0.55), 0.002, g)
    if big:
        # the haptic's second pulse: the blade grinding through
        add(out, drive(perc(svf(noise(0.06), 1200, 1.0, "bp"), 0.0005, 0.03), 2), 0.06, 0.45)
    return reverb(out, 0.25 if big else 0.15, 0.6, tail=0.9 if big else 0.4)


@sfx(-3)
def hit_light():
    return _hit(1480, False)


@sfx(-1)
def hit_heavy():
    return _hit(988, True)


@sfx(-7)
def blocked():
    # a clink off a shield, and its bounce
    one = ting(0.3, 2650, (1.0, 2.92, 4.13, 5.8), tau=0.06, bright=0.7)
    two = ting(0.25, 2390, (1.0, 2.92, 4.13, 5.8), tau=0.04, bright=0.6)
    return reverb(mix((one, 0, 1), (two, 0.045, 0.55), (click(0.003, 4000), 0, 0.6),
                      (thump(0.06, 500, 250, 0.01, 0.015), 0, 0.3)), 0.15, 0.4, tail=0.3)


@sfx(-9)
def dodge():
    a = whoosh(0.26, [(0, 500), (0.07, 1900), (0.26, 650)], [(0, 0), (0.06, 1), (0.26, 0)], 0.9)
    lo = whoosh(0.26, [(0, 180), (0.08, 400), (0.26, 160)], [(0, 0), (0.08, 1), (0.26, 0)], 0.7)
    return mix((a, 0, 1), (lo, 0, 0.6))


@sfx(-16)
def aim():
    return mix((perc(tone(0.08, [(0, 1200), (0.06, 1800)]), 0.002, 0.03), 0, 1),
               (ting(0.08, 2400, GLASS, tau=0.02), 0.01, 0.4))


@sfx(-5)
def ricochet():
    zip_ = whoosh(0.32, [(0, 700), (0.04, 4200), (0.32, 1600)], [(0, 0), (0.025, 1), (0.32, 0)], 1.4)
    laser = perc(svf(tone(0.18, [(0, 300), (0.15, 1400)], "saw"), 3200, 0.8), 0.002, 0.07)
    kick = thump(0.12, 220, 80, 0.02, 0.05)
    return mix((zip_, 0, 1), (laser, 0, 0.25), (kick, 0, 0.6),
               (grains(0.3, 60, 2500, 7000, (0.01, 0.04), decay=0.15), 0, 0.3))


@sfx(-6)
def bounce():
    boing = perc(tone(0.12, [(0, 950), (0.1, 620)]), 0.001, 0.045)
    return reverb(mix((ting(0.35, 1245, BAR, tau=0.08, bright=0.5), 0, 0.7),
                      (thump(0.12, 320, 120, 0.015, 0.05), 0, 0.9),
                      (click(0.003, 3500), 0, 0.6), (boing, 0, 0.25)), 0.15, 0.5, tail=0.35)


@sfx(-3)
def pierce():
    tear = drive(shape(svf(noise(0.2), [(0, 3200), (0.2, 1100)], 1.1, "bp"), [(0, 1), (0.2, 0)]), 2.5)
    return reverb(mix((tear, 0, 0.7), (thump(0.25, 190, 55, 0.03, 0.08), 0, 0.9),
                      (ting(0.6, 1760, GLASS, tau=0.2, bright=0.55), 0.005, 0.4),
                      (ting(0.5, 2637, GLASS, tau=0.15, bright=0.5), 0.01, 0.2)), 0.2, 0.6, tail=0.6)


@sfx(-5)
def blink():
    # gone (a reverse swell), then arrived (a pop)
    gone = whoosh(0.06, [(0, 1800), (0.06, 6500)], [(0, 0), (0.06, 1)], 1.1)
    gone_t = shape(tone(0.06, [(0, 400), (0.06, 2400)]), [(0, 0), (0.06, 1)])
    pop = mix((click(0.004, 2500), 0, 1), (thump(0.18, 420, 140, 0.015, 0.06), 0, 0.9),
              (ting(0.7, 1568, GLASS, tau=0.25, bright=0.55), 0, 0.4),
              (grains(0.45, 70, 2500, 8000, (0.01, 0.05), decay=0.15), 0, 0.3))
    return reverb(mix((gone, 0, 0.7), (gone_t, 0, 0.3), (pop, 0.06, 1)), 0.35, 0.7, tail=1.0)


@sfx(-4)
def ult_start():
    d = 0.6
    drone = zeros(N(d))
    for f, g in ((110, 1.0), (165, 0.7), (220, 0.5), (330, 0.3)):
        add(drone, tone(d, [(0, f), (d, f * 1.06)], "saw"), 0, g)
    drone = shape(svf(drone, [(0, 300), (d, 2400)], 1.2), [(0, 0), (0.1, 0.5), (d - 0.05, 1), (d, 0.6)])
    rise = whoosh(d, [(0, 300), (d, 3500)], [(0, 0), (d, 1)], 1.2)
    return reverb(mix((drone, 0, 0.35), (rise, 0, 0.5),
                      (ting(0.6, 1319, GLASS, tau=0.3, bright=0.5), 0, 0.35),
                      (thump(0.25, 160, 60, 0.03, 0.1), 0.08, 0.7)), 0.35, 0.8, tail=1.0)


@sfx(-6)
def ult_slash():
    w = whoosh(0.11, [(0, 2500), (0.025, 6500), (0.11, 3000)], [(0, 0), (0.022, 1), (0.11, 0)], 1.6)
    return mix((w, 0, 1), (ting(0.15, 3520, (1.0, 1.5, 2.76), tau=0.04, bright=0.5), 0.015, 0.3),
               (click(0.003, 4000), 0.015, 0.4))


@sfx(-1)
def ult_end():
    out = mix((drive(thump(0.8, 130, 35, 0.05, 0.25, 0.001), 2.0), 0, 1),
              (perc(svf(noise(0.2), 1500, 0.7, "hp"), 0.0005, 0.05), 0, 0.6))
    for f in (659, 831, 988, 1319):                     # E major, Jade
        add(out, ting(2.0, f, GLASS, tau=1.1, bright=0.45), 0.005, 0.22)
    add(out, grains(1.0, 60, 2500, 8000, (0.02, 0.08), decay=0.4), 0.02, 0.35)
    add(out, thump(0.3, 110, 50, 0.04, 0.1), 0.11, 0.4)
    return reverb(out, 0.45, 0.85, tail=2.0)


@sfx(-9)
def ult_ready():
    return reverb(mix((ting(1.0, 1319, GLASS, tau=0.5, bright=0.5), 0, 1),
                      (ting(1.2, 1976, GLASS, tau=0.6, bright=0.5), 0.12, 1)), 0.4, 0.8, tail=1.4)


@sfx(-15)
def ready():
    return reverb(ting(0.4, 2093, GLASS, tau=0.12, bright=0.45), 0.25, 0.6, tail=0.5)


@sfx(-2)
def hurt():
    body = thump(0.3, 150, 50, 0.03, 0.1)
    crunch = drive(perc(svf(noise(0.12), 1500, 0.7, "lp"), 0.0005, 0.05), 3)
    sting = perc(svf(tone(0.2, [(0, 560), (0.18, 170)], "square"), 1900, 0.9), 0.001, 0.09)
    return mix((body, 0, 1), (crunch, 0, 0.7), (sting, 0, 0.3), (thump(0.15, 110, 50, 0.02, 0.06), 0.11, 0.5))


@sfx(-12)
def heartbeat():
    lub = thump(0.18, 75, 45, 0.03, 0.06, 0.004)
    dub = thump(0.16, 66, 42, 0.03, 0.05, 0.004)
    return svf(mix((lub, 0, 1), (dub, 0.18, 0.7)), 320, 0.7)


@sfx(-2)
def death():
    d = 1.4
    fall = shape(tone(d, [(0, 440), (1.2, 55)]), [(0, 1), (d, 0)])
    grind = shape(svf(tone(d, [(0, 220), (1.2, 40)], "saw"), [(0, 2200), (d, 180)], 0.9), [(0, 1), (d, 0)])
    out = mix((fall, 0, 0.35), (grind, 0, 0.3), (shatter(1.0), 0, 0.35))
    for t, g in ((0, 1.0), (0.23, 0.7), (0.42, 0.5)):   # the haptic's three thuds
        add(out, thump(0.4, 120, 40, 0.04, 0.12), t, g)
    return reverb(out, 0.5, 0.85, tail=2.0)


# =============================================================================
# Bosses, shared
# =============================================================================

@sfx(-11)
def telegraph():
    rise = shape(tone(0.24, [(0, 880), (0.2, 1320)]), [(0, 0), (0.14, 1), (0.24, 0)])
    air = whoosh(0.24, [(0, 3000), (0.24, 7000)], [(0, 0), (0.14, 1), (0.24, 0)], 0.9)
    return reverb(mix((rise, 0, 0.4), (air, 0, 0.25), (ting(0.35, 1760, GLASS, tau=0.1, bright=0.45), 0.12, 0.3)),
                  0.3, 0.6, tail=0.6)


@sfx(-1)
def phase():
    out = zeros(1)
    for t, f, g in ((0.0, 196, 0.7), (0.12, 247, 0.85), (0.24, 294, 1.0)):    # G B D, rising
        add(out, thump(0.5, f * 0.8, 45, 0.04, 0.15), t, g)
        bell = perc(fm(1.6, f, 1.41, [(0, 5), (1.2, 0.3)]), 0.002, 0.5)
        add(out, bell, t, 0.3 * g)
        add(out, ting(1.6, f * 2, BELL, tau=0.8, bright=0.55), t, 0.25 * g)
    add(out, rumble(1.4, 80), 0, 0.5)
    return reverb(out, 0.5, 0.9, tail=2.2)


@sfx(-1)
def boss_death():
    out = mix((rumble(2.4, 70, [(0, 0), (0.05, 1), (1.2, 0.6), (2.4, 0)]), 0, 0.6),
              (shatter(1.8, 1500, 8000), 0.3, 0.5),
              (whoosh(0.46, [(0, 400), (0.46, 3000)], [(0, 0), (0.46, 1)], 1.0), 0, 0.3))
    for t, g in ((0, 0.8), (0.16, 0.6), (0.30, 0.6), (0.46, 1.0)):     # haptic beats; the last is the break
        add(out, drive(thump(0.6, 140, 32, 0.05, 0.2), 1.8), t, g)
    add(out, perc(svf(noise(0.3), 1200, 0.7, "hp"), 0.0005, 0.06), 0.46, 0.7)
    add(out, perc(fm(2.5, 98, 1.41, [(0, 7), (2.0, 0.2)]), 0.002, 0.9), 0.46, 0.3)
    add(out, ting(2.5, 392, BELL, tau=1.2, bright=0.55), 0.46, 0.3)
    return reverb(out, 0.5, 0.92, tail=2.6)


@sfx(-3)
def impact():
    return mix((thump(0.4, 95, 36, 0.03, 0.13), 0, 1),
               (perc(svf(noise(0.15), 600, 0.7, "lp"), 0.0005, 0.05), 0, 0.6),
               (click(0.004, 2000), 0, 0.3))


# =============================================================================
# Sapphires and the jail
# =============================================================================

@sfx(-6)
def crystal_land():
    return reverb(mix((ting(0.8, 1976, GLASS, tau=0.28, bright=0.55), 0, 1),
                      (click(0.003, 3000), 0, 0.5), (thump(0.1, 300, 140, 0.015, 0.04), 0, 0.4),
                      (ting(0.5, 1976, GLASS, tau=0.15, bright=0.5), 0.18, 0.45)), 0.25, 0.6, tail=0.8)


@sfx(-4)
def pickup():
    out = zeros(1)
    for i, f in enumerate((659, 831, 988, 1319)):
        add(out, ting(1.2, f, GLASS, tau=0.35 + 0.15 * i, bright=0.5), 0.06 * i, 0.55 + 0.15 * i)
    add(out, grains(0.8, 80, 3000, 9000, (0.01, 0.05), decay=0.3), 0.18, 0.35)
    add(out, thump(0.2, 180, 90, 0.02, 0.06), 0.18, 0.35)
    return reverb(out, 0.4, 0.8, tail=1.6)


@sfx(-9)
def fly():
    w = whoosh(0.55, [(0, 800), (0.25, 3200), (0.55, 1400)], [(0, 0), (0.25, 1), (0.55, 0)], 1.1)
    g = shape(grains(0.55, 90, 3000, 9000, (0.01, 0.04)), [(0, 0.2), (0.3, 1), (0.55, 0.3)])
    return reverb(mix((w, 0, 0.7), (g, 0, 0.5)), 0.25, 0.6, tail=0.6)


@sfx(-2)
def place():
    out = mix((drive(thump(0.5, 140, 52, 0.04, 0.16), 1.5), 0, 1), (click(0.004, 2500), 0, 0.6))
    for f in (494, 740, 988):                            # B, F#, B: open and settled
        add(out, ting(2.0, f, BELL, tau=0.9, bright=0.5), 0.003, 0.25)
    add(out, ting(0.5, 1976, GLASS, tau=0.15, bright=0.5), 0.09, 0.25)
    return reverb(out, 0.45, 0.85, tail=2.0)


@sfx(-12)
def lamp():
    pad = zeros(N(1.0))
    for f in (523, 659, 784):
        add(pad, tone(1.0, f), 0, 0.3)
    shape(pad, [(0, 0), (0.12, 1), (1.0, 0)])
    return reverb(mix((pad, 0, 1), (ting(0.8, 1568, GLASS, tau=0.3, bright=0.45), 0, 0.3)), 0.4, 0.8, tail=1.2)


@sfx(-2)
def win():
    out = zeros(1)
    # E major, the key of the pickup arpeggio that sounds in the same frame
    for t, f in ((0.0, 659), (0.12, 831), (0.24, 988)):
        add(out, ting(0.6, f, GLASS, tau=0.25, bright=0.5), t, 0.6)
        add(out, thump(0.15, 220, 110, 0.02, 0.05), t, 0.3)
    for f in (1319, 1661, 1976, 2637):
        add(out, ting(2.0, f, GLASS, tau=1.0, bright=0.45), 0.36, 0.3)
    swell = shape(svf(add(tone(1.8, 330, "saw"), tone(1.8, 494, "saw"), 0, 0.8), 1600, 0.7), [(0, 0), (0.4, 1), (1.8, 0)])
    add(out, swell, 0.24, 0.12)
    add(out, grains(1.2, 50, 3000, 9000, (0.02, 0.06), decay=0.5), 0.36, 0.35)
    return reverb(out, 0.45, 0.85, tail=2.2)


@sfx(-5)
def lose():
    out = zeros(1)
    # G, E flat, C, after the death sound's three thuds (same frame) have landed
    for t, f, d in ((0.5, 392, 0.4), (0.75, 311, 0.4), (1.0, 262, 1.3)):
        add(out, perc(svf(tone(d, f, "tri"), 1400, 0.7), 0.01, 0.15 if d < 1 else 0.5), t, 0.6)
    add(out, shape(svf(tone(1.8, 65, "saw"), 300, 0.7), [(0, 0), (0.5, 1), (1.8, 0)]), 0.5, 0.3)
    return reverb(out, 0.45, 0.85, tail=1.8)


# =============================================================================
# The Turnkey: steel keys and a lock
# =============================================================================

def _key_clank(f):
    return mix((ting(0.3, f, METAL, tau=0.07, bright=0.55), 0, 0.55),
               (thump(0.1, 200, 90, 0.015, 0.035), 0, 0.6), (click(0.003, 2500), 0, 0.5))


@sfx(-5)
def turnkey_wall():
    out = zeros(1)
    for i in range(7):                                   # the keys march in step
        add(out, _key_clank(random.uniform(560, 700)), 0.16 * i, 1.0 - 0.06 * i)
    return reverb(out, 0.25, 0.6, tail=0.6)


@sfx(-9)
def turnkey_volley():
    d = 0.6
    a = tone(d, 1100)
    b = tone(d, 1650)
    out = zeros(N(d))
    for i in range(len(out)):
        t = i / SR
        am = 0.5 + 0.5 * math.sin(TAU * (12 * t + 20 * t * t))     # spin speeding up
        out[i] = (a[i] + 0.6 * b[i]) * am
    shape(out, [(0, 0), (0.4, 1), (d, 0)])
    return reverb(mix((out, 0, 0.6), (whoosh(d, [(0, 1500), (d, 4000)], [(0, 0), (0.5, 1), (d, 0)], 1.2), 0, 0.3)), 0.3, 0.6, tail=0.6)


@sfx(-9)
def turnkey_fire():
    return mix((whoosh(0.14, [(0, 1500), (0.03, 4200), (0.14, 2000)], [(0, 0), (0.025, 1), (0.14, 0)], 1.4), 0, 1),
               (ting(0.3, 2349, METAL, tau=0.05, bright=0.5), 0, 0.35))


@sfx(-5)
def turnkey_lock():
    def chunk():
        return mix((click(0.004, 2500), 0, 0.8), (thump(0.2, 210, 85, 0.02, 0.06), 0, 1),
                   (ting(0.35, 740, METAL, tau=0.08, bright=0.55), 0, 0.4),
                   (click(0.004, 3500), 0.04, 0.6), (ting(0.3, 988, METAL, tau=0.06, bright=0.5), 0.04, 0.3))
    whine = shape(tone(0.8, [(0, 600), (0.8, 900)]), [(0, 0), (0.3, 1), (0.8, 0)])
    return reverb(mix((chunk(), 0, 1), (chunk(), 0.4, 1), (whine, 0, 0.12)), 0.25, 0.6, tail=0.7)


@sfx(-6)
def turnkey_blades():
    d = 0.6
    scrape = whoosh(d, 4200, [(0, 0), (0.35, 1), (d, 0)], 3.0)
    ring = shape(add(tone(d, 3136), tone(d, 4186), 0, 0.6), [(0, 0), (0.35, 1), (d, 0)])
    return reverb(mix((scrape, 0, 0.7), (ring, 0, 0.12),
                      (whoosh(d, [(0, 900), (d, 3000)], [(0, 0), (0.5, 1), (d, 0)], 1.0), 0, 0.4),
                      (ting(0.6, 3136, METAL, tau=0.25, bright=0.5), 0.45, 0.3)), 0.3, 0.6, tail=0.8)


@sfx(-9)
def turnkey_dial():
    out = zeros(1)
    t, gap = 0.0, 0.12
    while t < 1.0:                                       # a ratchet, speeding up
        add(out, mix((click(0.003, 3000), 0, 1), (ting(0.04, 3000, METAL, tau=0.01, bright=0.5), 0, 0.5)), t, 0.8)
        t += gap
        gap = max(0.04, gap * 0.88)
    add(out, _key_clank(520), t, 1.0)
    return reverb(out, 0.2, 0.5, tail=0.5)


@sfx(-5)
def turnkey_knock():
    out = mix((ting(0.7, 1568, METAL, tau=0.2, bright=0.6), 0, 0.8), (click(0.003, 3000), 0, 0.7),
              (thump(0.1, 320, 150, 0.015, 0.035), 0, 0.5))
    for t, f, g in ((0.09, 1320, 0.3), (0.16, 1480, 0.18)):     # the key tumbling away
        add(out, ting(0.3, f, METAL, tau=0.05, bright=0.5), t, g)
    return reverb(out, 0.2, 0.6, tail=0.6)


@sfx(-2)
def turnkey_unlock():
    out = mix((click(0.004, 3000), 0, 0.9), (click(0.004, 2500), 0.06, 1.0),
              (thump(0.3, 220, 70, 0.03, 0.1), 0.06, 0.9), (ting(0.4, 1175, METAL, tau=0.1, bright=0.55), 0.06, 0.4),
              (shatter(0.7), 0.07, 0.5))
    for i, f in enumerate((784, 988, 1175, 1568)):
        add(out, ting(1.0, f, GLASS, tau=0.5, bright=0.5), 0.1 + 0.04 * i, 0.25)
    return reverb(out, 0.4, 0.75, tail=1.4)


@sfx(-3)
def turnkey_parry():
    return reverb(mix((ting(0.9, 1046, METAL, tau=0.3, bright=0.65), 0, 0.8),
                      (thump(0.2, 250, 90, 0.02, 0.06), 0, 0.8), (click(0.004, 2500), 0, 0.8),
                      (whoosh(0.22, [(0, 800), (0.22, 4200)], [(0, 0.3), (0.1, 1), (0.22, 0)], 1.3), 0.02, 0.5)),
                  0.3, 0.7, tail=0.9)


# =============================================================================
# The Pendulum: a heavy blade on a long arm
# =============================================================================

def _big_whoosh(d):
    h = d * 0.5
    a = whoosh(d, [(0, 200), (h, 950), (d, 260)], [(0, 0), (h, 1), (d, 0)], 0.7)
    b = whoosh(d, [(0, 700), (h, 2600), (d, 800)], [(0, 0), (h, 1), (d, 0)], 1.2)
    return mix((a, 0, 1), (b, 0, 0.4))


@sfx(-6)
def pendulum_swing():
    hum = shape(tone(1.4, 70), [(0, 0), (0.35, 1), (0.7, 0.2), (1.05, 1), (1.4, 0)])
    return mix((_big_whoosh(0.7), 0, 1), (_big_whoosh(0.7), 0.7, 0.9), (hum, 0, 0.25))


@sfx(-1)
def pendulum_cut():
    # the blade bites the floor and sticks, quivering
    thunk = drive(thump(0.6, 120, 38, 0.04, 0.18), 2.2)
    crack = perc(svf(noise(0.2), 900, 0.7, "hp"), 0.0005, 0.04)
    twang = zeros(N(1.2))
    t_ = tone(1.2, 180)
    for i in range(len(twang)):
        t = i / SR
        twang[i] = t_[i] * (0.6 + 0.4 * math.sin(TAU * 13 * t)) * math.exp(-t / 0.35)
    return reverb(mix((thunk, 0, 1), (crack, 0, 0.6), (ting(1.2, 330, METAL, tau=0.45, bright=0.6), 0, 0.3),
                      (twang, 0.01, 0.3), (rumble(0.5, 120), 0, 0.4)), 0.35, 0.8, tail=1.4)


@sfx(-6)
def pendulum_unwind():
    d = 1.2
    # one turn spiralling out: three passes of the blade, each nearer and lower
    w = whoosh(d, [(0, 1200), (0.2, 500), (0.4, 1500), (0.6, 400), (0.8, 1200), (1.0, 300), (d, 600)],
               [(0, 0), (0.2, 0.6), (0.3, 0.2), (0.6, 0.8), (0.7, 0.3), (1.0, 1), (d, 0)], 0.8)
    return mix((w, 0, 1), (shape(tone(d, [(0, 90), (d, 60)]), [(0, 0), (0.6, 1), (d, 0)]), 0, 0.2))


@sfx(-8)
def pendulum_clock():
    out = mix((ting(2.4, 196, BELL, tau=1.0, bright=0.5), 0, 0.35))
    for i in range(9):                                   # tick, tock
        f = 2400 if i % 2 == 0 else 1800
        tick = mix((perc(svf(noise(0.03), f, 4.0, "bp"), 0.0005, 0.008), 0, 1),
                   (ting(0.06, f * 0.75, BAR, tau=0.012, bright=0.4), 0, 0.5))
        add(out, tick, 0.35 * i, 0.8)
    return reverb(out, 0.3, 0.7, tail=1.0)


@sfx(-1)
def pendulum_riposte():
    # steel meets steel and the blade is thrown back: the Pendulum's big moment
    clang = ting(1.4, 587, (1.0, 2.0, 2.76, 3.3, 5.4, 7.1), tau=0.55, bright=0.75, detune=0.0022)
    bell = perc(fm(1.4, 587, 1.41, [(0, 8), (0.8, 0.5)]), 0.001, 0.4)
    return reverb(mix((clang, 0, 0.7), (bell, 0, 0.25), (click(0.005, 2000), 0, 1),
                      (perc(svf(noise(0.15), 3000, 0.7, "hp"), 0.0005, 0.035), 0, 0.6),
                      (drive(thump(0.35, 180, 55, 0.03, 0.1), 1.8), 0, 0.8)), 0.4, 0.8, tail=1.6)


# =============================================================================
# The Prism: light and crystal
# =============================================================================

@sfx(-1)
def prism_slam():
    out = mix((drive(thump(0.6, 110, 40, 0.04, 0.16), 2.0), 0, 1),
              (perc(svf(noise(0.2), 1500, 0.7, "hp"), 0.0005, 0.04), 0, 0.5))
    for i, f in enumerate((1175, 1397, 1661, 1976, 2349)):    # the spikes, rising along the cone
        add(out, ting(0.6, f, GLASS, tau=0.22, bright=0.55), 0.03 + 0.045 * i, 0.3)
        add(out, perc(svf(noise(0.04), 4000, 0.7, "hp"), 0.0005, 0.01), 0.03 + 0.045 * i, 0.25)
    add(out, grains(0.6, 70, 3000, 9000, (0.01, 0.05), decay=0.3), 0.05, 0.3)
    return reverb(out, 0.35, 0.75, tail=1.2)


@sfx(-5)
def prism_spectrum():
    out = zeros(1)
    for i in range(3):
        d = 0.4
        vw = zeros(N(d))
        for f in (330, 495, 660):
            add(vw, tone(d, [(0, f * 0.9), (d, f * 1.1)]), 0, 0.33)
        perc(vw, 0.01, 0.12)
        sw = whoosh(d, [(0, 600), (d, 5000)], [(0, 1), (d, 0)], 1.0)
        add(out, mix((vw, 0, 0.6), (sw, 0, 0.35), (ting(0.5, 1320 * (1 + 0.12 * i), GLASS, tau=0.15), 0, 0.3)),
            0.28 * i, 0.8 + 0.1 * i)
    return reverb(out, 0.35, 0.75, tail=1.0)


@sfx(-5)
def prism_charge():
    d = 0.5
    w = whoosh(d, [(0, 600), (d, 2600)], [(0, 0.3), (0.05, 1), (d, 0)], 1.0)
    buzz = shape(svf(tone(d, [(0, 160), (d, 330)], "saw"), 1800, 1.0), [(0, 1), (d, 0)])
    return mix((w, 0, 1), (buzz, 0, 0.25), (thump(0.2, 180, 70, 0.02, 0.06), 0, 0.6),
               (grains(d, 90, 3000, 9000, (0.01, 0.04)), 0, 0.3))


@sfx(-5)
def prism_beam():
    d = 0.65
    beam = add(tone(d, 220, "saw"), tone(d, 221.7, "saw"), 0, 1.0)
    add(beam, fm(d, 880, 1.5, 1.5), 0, 0.4)
    beam = drive(svf(beam, [(0, 1500), (0.1, 4500), (d, 2200)], 1.4, "bp"), 1.6)
    shape(beam, [(0, 0), (0.01, 1), (0.45, 0.8), (d, 0)])
    zap = perc(tone(0.1, [(0, 3000), (0.1, 600)]), 0.0005, 0.03)
    return reverb(mix((beam, 0, 0.8), (zap, 0, 0.4), (click(0.003, 3000), 0, 0.5)), 0.25, 0.6, tail=0.6)


@sfx(-4)
def prism_shardfall():
    out = zeros(1)
    for _ in range(4):                                   # whistling down, then landing
        f = random.uniform(2600, 3400)
        add(out, shape(tone(0.22, [(0, f), (0.22, f * 0.45)]), [(0, 0), (0.15, 1), (0.22, 0)]), random.uniform(0, 0.05), 0.12)
    for _ in range(6):
        t = random.uniform(0.2, 0.32)
        add(out, ting(0.4, random.uniform(1500, 2800), GLASS, tau=0.12, bright=0.55), t, 0.3)
        add(out, perc(svf(noise(0.04), 3000, 0.7, "hp"), 0.0005, 0.012), t, 0.3)
    add(out, thump(0.3, 120, 45, 0.03, 0.1), 0.22, 0.6)
    return reverb(out, 0.3, 0.7, tail=0.9)


@sfx(-10)
def prism_lens():
    d = 3.0
    out = zeros(N(d))
    t = 0.0
    while True:                                          # crackle
        t += random.expovariate(45)
        if t >= d:
            break
        add(out, perc(svf(noise(0.008), 2500, 0.7, "hp"), 0.0002, 0.002), t, random.uniform(0.3, 1.0))
    sizzle = svf(noise(d), 6000, 1.0, "bp")
    hum = add(tone(d, 90), tone(d, 180), 0, 0.5)
    for i in range(len(hum)):
        hum[i] *= 0.7 + 0.3 * math.sin(TAU * 6 * i / SR)
    return shape(mix((out, 0, 0.6), (sizzle, 0, 0.2), (hum, 0, 0.25)), [(0, 0), (0.2, 1), (d - 0.4, 1), (d, 0)])


@sfx(-7)
def prism_refraction():
    d = 4.0
    hum = add(add(tone(d, 110, "saw"), tone(d, 110.8, "saw"), 0, 1), tone(d, 165, "saw"), 0, 0.6)
    sweep = [(i * 0.1, 1700 + 1300 * math.sin(TAU * 1.5 * i * 0.1)) for i in range(41)]
    hum = svf(hum, sweep, 2.0, "bp")
    return reverb(shape(mix((hum, 0, 0.7), (grains(d, 30, 3000, 9000, (0.02, 0.06)), 0, 0.3)),
                        [(0, 0), (0.3, 1), (d - 0.5, 1), (d, 0)]), 0.3, 0.7, tail=1.0)


# =============================================================================
# The Hourglass: glass and time
# =============================================================================

@sfx(-1)
def hourglass_timesup():
    blast = whoosh(1.2, [(0, 4500), (1.2, 180)], [(0, 1), (1.2, 0)], 0.7)
    return reverb(mix((drive(thump(0.9, 120, 30, 0.06, 0.3), 2.2), 0, 1), (blast, 0, 0.6),
                      (shatter(0.9, 1500, 7000), 0.02, 0.35),
                      (perc(fm(2.0, 82, 1.41, [(0, 6), (1.5, 0.2)]), 0.002, 0.8), 0, 0.3)), 0.45, 0.9, tail=2.0)


@sfx(-3)
def hourglass_flip():
    up = whoosh(0.3, [(0, 600), (0.3, 4000)], [(0, 0), (0.28, 1), (0.3, 0)], 1.2)
    out = mix((up, 0, 0.5), (ting(0.6, 1760, GLASS, tau=0.25, bright=0.6), 0.28, 0.6),
              (thump(0.3, 200, 70, 0.03, 0.1), 0.28, 0.8), (click(0.003, 3000), 0.28, 0.6))
    for i, f in enumerate((880, 1109, 1319)):
        add(out, ting(1.2, f, GLASS, tau=0.6, bright=0.45), 0.3 + 0.05 * i, 0.25)
    return reverb(out, 0.4, 0.8, tail=1.4)


@sfx(-5)
def hourglass_rewind():
    d = 0.9
    tape = zeros(N(d))
    p = 0.0
    for i in range(len(tape)):
        t = i / SR
        f = 300 * (1 + 4 * t / d) * (1 + 0.08 * math.sin(TAU * 9 * t))     # warbling up
        tape[i] = 2.0 * p - 1.0
        p = (p + f / SR) % 1.0
    tape = shape(svf(tape, 2200, 1.0), [(0, 0), (0.7, 1), (d, 0)])
    rev = whoosh(d, [(0, 400), (d, 3500)], [(0, 0), (0.85, 1), (d, 0)], 1.0)
    return reverb(mix((tape, 0, 0.3), (rev, 0, 0.6), (ting(0.6, 1319, GLASS, tau=0.2), d - 0.05, 0.4)),
                  0.35, 0.7, tail=0.9)


# =============================================================================
# The Mirror: the player's own kit, reflected
# =============================================================================

def _mirrored(x):
    return reverb(echo(repitch(x, 0.86), 0.09, 0.35, 2), 0.5, 0.8, tail=1.0)


@sfx(-6)
def mirror_light():
    return _mirrored(_swing_light_body())


@sfx(-4)
def mirror_heavy():
    return _mirrored(_swing_heavy_release())


@sfx(-2)
def mirror_great():
    return mix((_mirrored(_swing_heavy_release()), 0, 1), (repitch(_swing_heavy_release(), 0.6), 0, 0.6),
               (thump(0.4, 110, 40, 0.04, 0.12), 0.05, 0.5))


@sfx(0)
def mirror_clash():
    a = ting(1.4, 523, METAL, tau=0.55, bright=0.75, detune=0.004)
    b = ting(1.4, 554, METAL, tau=0.5, bright=0.7, detune=0.004)    # a semitone apart: it grates
    return reverb(mix((a, 0, 0.5), (b, 0, 0.5), (click(0.006, 1500), 0, 1),
                      (drive(thump(0.5, 200, 45, 0.03, 0.15), 2.0), 0, 0.9),
                      (shatter(0.5, 2000, 8000), 0.01, 0.4)), 0.45, 0.85, tail=1.8)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    want = set(sys.argv[1:])
    unknown = want - RECIPES.keys()
    if unknown:
        sys.exit("unknown: " + ", ".join(sorted(unknown)))
    for name, (fn, peak) in RECIPES.items():
        if want and name not in want:
            continue
        random.seed(name)
        print("%-20s %.2fs" % (name, save(name, fn(), peak)))
