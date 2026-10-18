#!/usr/bin/env python3
"""Processes one of lime's own sound sources into a CAF (LIME-152e).

    python3 ios/tools/process-sound.py SOURCE.m4a OUT.caf [--loop]

Mono, 16-bit, 44.1 kHz; pure leading and trailing silence trimmed (below -60 dBFS, keeping 5 ms); the level set to an RMS of -16 dBFS, lowered if
that would take the peak above -1 dBFS; a short raised-cosine fade at both ends (and, for a looping sound, the cut moved to the nearest zero
crossing) so a loop has no click at its seam. Prints the final duration, RMS and peak. Needs only macOS's `afconvert`; the sources stay out of git.
"""
import array, math, os, struct, subprocess, sys, tempfile, wave

TARGET_RMS_DB = -16.0
PEAK_CEILING_DB = -1.0
SILENCE = 10 ** (-60 / 20)
RATE = 44100
FADE_MS = 8


def db(x):
    return 20 * math.log10(x) if x > 0 else -120.0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    loop = "--loop" in sys.argv
    source, out = args
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "in.wav")
        subprocess.run(["afconvert", source, wav, "-f", "WAVE", "-d", "LEI16@%d" % RATE, "-c", "1"], check=True)
        with wave.open(wav) as w:
            frames = w.readframes(w.getnframes())
        samples = [s / 32768.0 for s in array.array("h", frames)]
        original = len(samples) / RATE
        first = next(i for i, s in enumerate(samples) if abs(s) > SILENCE)
        last = len(samples) - 1 - next(i for i, s in enumerate(reversed(samples)) if abs(s) > SILENCE)
        margin = int(0.005 * RATE)
        a, b = max(0, first - margin), min(len(samples), last + 1 + margin)
        if loop:
            # The nearest zero crossing, so the loop's seam is a crossing at both ends.
            while a < len(samples) - 1 and samples[a] * samples[a + 1] > 0 and a < first + margin * 4:
                a += 1
            while b > a + 1 and samples[b - 1] * samples[b - 2] > 0 and b > last - margin * 4:
                b -= 1
        trimmed = samples[a:b]
        rms = math.sqrt(sum(s * s for s in trimmed) / len(trimmed))
        peak = max(abs(s) for s in trimmed)
        gain = 10 ** (TARGET_RMS_DB / 20) / rms
        limited = False
        if peak * gain > 10 ** (PEAK_CEILING_DB / 20):
            gain = 10 ** (PEAK_CEILING_DB / 20) / peak
            limited = True
        fade = int(FADE_MS / 1000 * RATE)
        out_samples = [s * gain for s in trimmed]
        for i in range(min(fade, len(out_samples))):
            k = 0.5 - 0.5 * math.cos(math.pi * i / fade)
            out_samples[i] *= k
            out_samples[-1 - i] *= k
        pcm = array.array("h", [max(-32768, min(32767, int(round(s * 32767)))) for s in out_samples])
        final_rms = math.sqrt(sum((s / 32768) ** 2 for s in pcm) / len(pcm))
        final_peak = max(abs(s) for s in pcm) / 32768
        edge = lambda part: math.sqrt(sum((s / 32768) ** 2 for s in part) / len(part))
        wav_out = os.path.join(tmp, "out.wav")
        with wave.open(wav_out, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(pcm.tobytes())
        subprocess.run(["afconvert", wav_out, out, "-f", "caff", "-d", "LEI16@%d" % RATE, "-c", "1"], check=True)
    n = int(0.05 * RATE)
    print("%s: %.3f s (source %.3f s), RMS %.1f dBFS, peak %.1f dBFS%s; first 50 ms %.1f dBFS, last 50 ms %.1f dBFS, seam step %.4f"
          % (os.path.basename(out), len(pcm) / RATE, original, db(final_rms), db(final_peak), " (peak-limited)" if limited else "",
             db(edge(pcm[:n])), db(edge(pcm[-n:])), abs(pcm[0] - pcm[-1]) / 32768))


if __name__ == "__main__":
    main()
