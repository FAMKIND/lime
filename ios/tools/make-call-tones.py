#!/usr/bin/env python3
"""Generates Lime's call tones (LIME-118): the ringback, the connect blip and the end tone.

    python3 ios/tools/make-call-tones.py

Writes mono 16-bit 44.1 kHz WAVs to a temporary folder and converts them to CAF with `afconvert` into
ios/Lime/Resources/Sounds/. Nothing here is taken from anyone else's recordings: they are plain sine tones.

- lime-ringback.caf: the North American telephone ringback (440 + 480 Hz, 2 s on, 4 s off; a public telephony standard), one 6 s cycle
  that the app loops. Level about -18 dBFS (modest).
- lime-connect.caf: two soft notes (C6 then E6, 90 ms each, 12 ms fades) when the media comes up.
- lime-end.caf: a short descending pair (E5 then C5) when a call ends.
"""
import math, os, struct, subprocess, sys, tempfile, wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Lime", "Resources", "Sounds")

def tone(freqs, seconds, level, fade=0.012):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / fade, (seconds - t) / fade)
        v = sum(math.sin(2 * math.pi * f * t) for f in freqs) / len(freqs)
        out.append(v * env * level)
    return out

def silence(seconds):
    return [0.0] * int(RATE * seconds)

def write(name, samples):
    tmp = tempfile.mkdtemp()
    wav = os.path.join(tmp, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
    caf = os.path.join(OUT, name + ".caf")
    subprocess.run(["afconvert", wav, caf, "-f", "caff", "-d", "LEI16@44100", "-c", "1"], check=True)
    print(f"{caf}: {len(samples) / RATE:.2f} s")

level = 10 ** (-18 / 20)
write("lime-ringback", tone([440, 480], 2.0, level) + silence(4.0))
write("lime-connect", tone([1046.5], 0.09, level) + tone([1318.5], 0.09, level))
write("lime-end", tone([659.3], 0.12, level) + tone([523.3], 0.18, level))
