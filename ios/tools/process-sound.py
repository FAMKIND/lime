#!/usr/bin/env python3
"""Processes one of lime's own sound sources into a CAF, keeping the source's quality (LIME-152e, LIME-152g).

    python3 ios/tools/process-sound.py SOURCE.m4a OUT.caf [--loop]

As the source: the same channel count (stereo stays stereo), the same sample rate, linear PCM 16-bit, and **no loudness normalisation**: the
level is the source's. Only pure leading and trailing silence is trimmed (below -60 dBFS, keeping 5 ms), a peak ceiling of -1 dBFS is applied
by lowering the whole file *if and only if* the source's peak is above it, and a short raised-cosine fade (8 ms) is put at both ends (for a
looping sound the cut is also moved to the nearest zero crossing, so a loop has no click at its seam). Prints the final channels, rate,
duration, RMS and peak. Needs only macOS's `afconvert` and `afinfo`; the sources stay out of git.
"""
import array, math, os, re, subprocess, sys, tempfile, wave

PEAK_CEILING_DB = -1.0
SILENCE = 10 ** (-60 / 20)
FADE_MS = 8


def db(x):
    return 20 * math.log10(x) if x > 0 else -120.0


def source_format(path):
    info = subprocess.run(["afinfo", path], capture_output=True, text=True, check=True).stdout
    match = re.search(r"Data format:\s+(\d+) ch,\s+(\d+) Hz", info)
    return int(match.group(1)), int(match.group(2))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    loop = "--loop" in sys.argv
    source, out = args
    channels, rate = source_format(source)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "in.wav")
        subprocess.run(["afconvert", source, wav, "-f", "WAVE", "-d", "LEI16@%d" % rate, "-c", str(channels)], check=True)
        with wave.open(wav) as w:
            frames = w.readframes(w.getnframes())
        raw = [s / 32768.0 for s in array.array("h", frames)]
        count = len(raw) // channels
        loudest = [max(abs(raw[i * channels + c]) for c in range(channels)) for i in range(count)]
        mixed = [sum(raw[i * channels:(i + 1) * channels]) / channels for i in range(count)]
        original = count / rate
        first = next(i for i, s in enumerate(loudest) if s > SILENCE)
        last = count - 1 - next(i for i, s in enumerate(reversed(loudest)) if s > SILENCE)
        margin = int(0.005 * rate)
        a, b = max(0, first - margin), min(count, last + 1 + margin)
        if loop:
            # The nearest zero crossing (of the channels' mix), so the loop's seam is a crossing at both ends.
            while a < count - 1 and mixed[a] * mixed[a + 1] > 0 and a < first + margin * 4:
                a += 1
            while b > a + 1 and mixed[b - 1] * mixed[b - 2] > 0 and b > last - margin * 4:
                b -= 1
        trimmed = raw[a * channels:b * channels]
        n = len(trimmed) // channels
        peak = max(abs(s) for s in trimmed)
        gain = 1.0
        limited = False
        if peak > 10 ** (PEAK_CEILING_DB / 20):
            gain = 10 ** (PEAK_CEILING_DB / 20) / peak
            limited = True
        fade = int(FADE_MS / 1000 * rate)
        shaped = [s * gain for s in trimmed]
        for i in range(min(fade, n)):
            k = 0.5 - 0.5 * math.cos(math.pi * i / fade)
            for c in range(channels):
                shaped[i * channels + c] *= k
                shaped[(n - 1 - i) * channels + c] *= k
        pcm = array.array("h", [max(-32768, min(32767, int(round(s * 32767)))) for s in shaped])
        final_rms = math.sqrt(sum((s / 32768) ** 2 for s in pcm) / len(pcm))
        final_peak = max(abs(s) for s in pcm) / 32768
        edge = lambda part: math.sqrt(sum((s / 32768) ** 2 for s in part) / len(part))
        wav_out = os.path.join(tmp, "out.wav")
        with wave.open(wav_out, "wb") as w:
            w.setnchannels(channels); w.setsampwidth(2); w.setframerate(rate); w.writeframes(pcm.tobytes())
        subprocess.run(["afconvert", wav_out, out, "-f", "caff", "-d", "LEI16@%d" % rate, "-c", str(channels)], check=True)
    edge_n = int(0.05 * rate) * channels
    print("%s: %d ch, %d Hz, %.3f s (source %.3f s), RMS %.1f dBFS, peak %.1f dBFS%s (source peak %.1f dBFS); first 50 ms %.1f dBFS, last 50 ms %.1f dBFS, seam step %.4f"
          % (os.path.basename(out), channels, rate, n / rate, original, db(final_rms), db(final_peak), " (peak-limited)" if limited else "", db(peak),
             db(edge(pcm[:edge_n])), db(edge(pcm[-edge_n:])), max(abs(pcm[c] - pcm[-channels + c]) for c in range(channels)) / 32768))


if __name__ == "__main__":
    main()
