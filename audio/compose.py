#!/usr/bin/env python3
"""Turns audio/raw/*.mp3 into the files the app plays, in App/Resources/Audio.

Effects become mono 22.05 kHz WAV: one-shots have their silence trimmed and get a short fade at
both ends; loops have their tail cross-faded into their head so the repeat has no click. Every
effect is brought to the same peak level. The music and the two finish stings become AAC.

    python3 audio/compose.py
"""
import array
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE.parent / "App" / "Resources" / "Audio"
RATE = 22050
PEAK = 0.9 * 32767
LOOPS = {"engine", "boost"}
MUSIC = {"theme", "finish", "win"}
SILENCE = 0.02 * 32767
CROSSFADE = 0.25   # seconds of a loop's tail folded into its head
FADE = 0.004       # seconds, both ends of a one-shot


def decode(mp3):
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", str(mp3), str(wav)],
                       check=True, capture_output=True)
        with wave.open(str(wav)) as w:
            return array.array("h", w.readframes(w.getnframes()))


def trimmed(samples):
    loud = [i for i, s in enumerate(samples) if abs(s) > SILENCE]
    if not loud:
        return samples
    return samples[max(loud[0] - int(0.005 * RATE), 0):min(loud[-1] + int(0.03 * RATE), len(samples))]


def looped(samples):
    """Drops the tail and blends it into the head, so the last sample runs straight into the first."""
    n = int(CROSSFADE * RATE)
    body = samples[:len(samples) - n]
    tail = samples[len(samples) - n:]
    for i in range(n):
        t = i / n
        body[i] = int(body[i] * t + tail[i] * (1 - t))
    return body


def faded(samples):
    n = min(int(FADE * RATE), len(samples) // 2)
    for i in range(n):
        samples[i] = int(samples[i] * i / n)
        samples[-1 - i] = int(samples[-1 - i] * i / n)
    return samples


def levelled(samples):
    peak = max(abs(s) for s in samples) or 1
    return array.array("h", (int(s * PEAK / peak) for s in samples))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for mp3 in sorted(RAW.glob("*.mp3")):
        name = mp3.stem
        if name in MUSIC:
            target = OUT / f"{name}.m4a"
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "112000", str(mp3), str(target)],
                           check=True, capture_output=True)
            print(f"{name:8} music {target.stat().st_size // 1024} KB")
            continue
        samples = decode(mp3)
        samples = looped(samples) if name in LOOPS else faded(trimmed(samples))
        samples = levelled(samples)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(samples.tobytes())
        rms = (sum(s * s for s in samples) / len(samples)) ** 0.5 / 32767
        print(f"{name:8} {len(samples) / RATE:5.2f} s  rms {rms:.3f}  {'loop' if name in LOOPS else ''}")


if __name__ == "__main__":
    sys.exit(main())
