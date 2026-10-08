#!/usr/bin/env python3
"""Writes the TEST_ONLY Hisn audio fixture used by HisnAudioTests.

One second of digital silence (8 kHz, mono, 16-bit WAV), generated here so no recording
from any source is committed. It is not a recitation and never ships in the app: it lives
in the test target's resources, and the app's repository rejects TEST_ONLY assets.
Deterministic: running it again gives the same bytes and checksum.
"""
import hashlib
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Packages/IslamicCore/Tests/HisnAudioTests/Fixtures/HisnAudio/test-silence-1s.wav"

RATE, SECONDS, CHANNELS, BITS = 8000, 1, 1, 16


def wav_bytes():
    frames = RATE * SECONDS
    data = b"\x00\x00" * frames * CHANNELS
    byte_rate = RATE * CHANNELS * BITS // 8
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, CHANNELS, RATE, byte_rate, CHANNELS * BITS // 8, BITS)
    header += b"data" + struct.pack("<I", len(data))
    return header + data


def main():
    content = wav_bytes()
    if "--check" in sys.argv:
        ok = OUT.exists() and OUT.read_bytes() == content
        print("fixture up to date" if ok else "fixture differs: run tools/content/make_hisn_audio_fixture.py")
        sys.exit(0 if ok else 1)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(content)
    print(OUT.relative_to(ROOT), len(content), "bytes, sha256", hashlib.sha256(content).hexdigest())


if __name__ == "__main__":
    main()
