#!/usr/bin/env python3
"""Synthesizes Perch's water sounds from scratch (sine partials, no samples).

drop  - a bead of water landing: agent finished, timer done.
sink  - a lower, slower drop that sinks: something stopped.
plip  - a tiny, quiet drip: opening the island (off unless you turn on water sounds).
fill  - three small bubbles rising: charger plugged in.
Run: python3 scripts/make_sounds.py  (writes Resources/Sounds/*.wav)
"""
import math, random, struct, wave, os

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")

def bubble(t0, dur, f0, f1, amp, decay):
    """A resonating bubble: pitch glides up as it closes (that is what water sounds like)."""
    n = int(dur * RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = t / dur
        f = f0 + (f1 - f0) * (k ** 0.6)
        phase += 2 * math.pi * f / RATE
        env = math.exp(-t * decay) * min(1.0, t / 0.002)
        out[i] = amp * env * (math.sin(phase) + 0.18 * math.sin(2.01 * phase))
    return int(t0 * RATE), out

def mix(parts, total):
    buf = [0.0] * int(total * RATE)
    for start, sig in parts:
        for i, v in enumerate(sig):
            j = start + i
            if j < len(buf):
                buf[j] += v
    return buf

def soften(buf, room=0.22):
    """A short, soft tail so it sounds like it happened in a glass, not a computer."""
    out = list(buf)
    for d, g in ((int(0.021 * RATE), room), (int(0.037 * RATE), room * 0.6), (int(0.061 * RATE), room * 0.35)):
        for i in range(d, len(out)):
            out[i] += buf[i - d] * g
    peak = max(1e-9, max(abs(v) for v in out))
    return [v / peak * 0.7 for v in out]

def write(name, buf, gain=1.0):
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        fade = int(0.01 * RATE)
        frames = bytearray()
        for i, v in enumerate(buf):
            if i > len(buf) - fade:
                v *= (len(buf) - i) / fade
            frames += struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767))
        w.writeframes(bytes(frames))

random.seed(7)
os.makedirs(OUT, exist_ok=True)
write("drop", soften(mix([bubble(0.0, 0.16, 620, 1450, 1.0, 26), bubble(0.085, 0.12, 900, 1750, 0.35, 34)], 0.45)))
write("sink", soften(mix([bubble(0.0, 0.26, 360, 610, 1.0, 14), bubble(0.14, 0.22, 300, 470, 0.45, 16)], 0.6), room=0.3))
write("plip", soften(mix([bubble(0.0, 0.07, 1100, 2100, 1.0, 60)], 0.18), room=0.12), gain=0.55)
write("fill", soften(mix([bubble(0.00, 0.09, 520, 980, 0.8, 40), bubble(0.11, 0.09, 640, 1150, 0.85, 40),
                          bubble(0.21, 0.11, 760, 1380, 1.0, 34)], 0.5)))
print("wrote", sorted(os.listdir(OUT)))
