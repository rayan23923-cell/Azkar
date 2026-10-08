#!/usr/bin/env python3
"""Writes the TEST_ONLY Hisn audio fixtures used by HisnAudioTests and the device test build.

- test-silence-1s.wav: one second of digital silence (unit tests).
- test-tone-30s.wav: 30 seconds of a soft synthetic beep, one short beep per second and a
  longer one every 10 seconds, so seeking and pausing can be heard on a device (Phase 3C).

8 kHz, mono, 16-bit WAV, generated here so no recording from any source is committed. Neither
is a recitation and neither ships in the production app: they live in the test target's
resources, the app's repository rejects TEST_ONLY assets, and only the separate fixture
build (HISN_AUDIO_FIXTURE) copies the tone in. Deterministic: running it again gives the same
bytes and checksums.
"""
import hashlib
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "Packages/IslamicCore/Tests/HisnAudioTests/Fixtures/HisnAudio"

RATE, CHANNELS, BITS = 8000, 1, 16


def silence(seconds):
    return b"\x00\x00" * RATE * seconds * CHANNELS


def tone(seconds):
    samples = []
    for second in range(seconds):
        beep = 0.4 if second % 10 == 0 else 0.1
        for n in range(RATE):
            t = n / RATE
            value = 0
            if t < beep:
                # 660 Hz at a quarter of full scale with a 10 ms fade in and out.
                fade = min(1.0, t / 0.01, (beep - t) / 0.01)
                value = int(round(0.25 * 32767 * fade * math.sin(2 * math.pi * 660 * t)))
            samples.append(value)
    return struct.pack("<%dh" % len(samples), *samples)


FIXTURES = {
    "test-silence-1s.wav": lambda: silence(1),
    "test-tone-30s.wav": lambda: tone(30),
}


def wav_bytes(data):
    byte_rate = RATE * CHANNELS * BITS // 8
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, CHANNELS, RATE, byte_rate, CHANNELS * BITS // 8, BITS)
    header += b"data" + struct.pack("<I", len(data))
    return header + data


def main():
    ok = True
    for name, make in FIXTURES.items():
        content = wav_bytes(make())
        out = DIR / name
        if "--check" in sys.argv:
            same = out.exists() and out.read_bytes() == content
            print(name, "up to date" if same else "differs: run tools/content/make_hisn_audio_fixture.py")
            ok = ok and same
            continue
        DIR.mkdir(parents=True, exist_ok=True)
        out.write_bytes(content)
        print(out.relative_to(ROOT), len(content), "bytes, sha256", hashlib.sha256(content).hexdigest())
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
