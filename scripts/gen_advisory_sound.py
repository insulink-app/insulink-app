#!/usr/bin/env python3
"""Generate assets/sounds/alarm_advisory.wav — the predictive-advisory tone.

A deliberately distinct two-note rising chime (a "pay attention, not an
emergency" sound), clearly different from the low/high alarm tones. This is a
placeholder — replace the WAV with a designed sound whenever you like; the app
references it by name and playback is best-effort.

Pure stdlib (wave + math), no dependencies. Run from the repo root:
    python3 scripts/gen_advisory_sound.py
"""

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds" / "alarm_advisory.wav"

# (frequency Hz, duration s) — two rising beeps with a short gap between, played
# twice so it is unmistakable but short.
NOTES = [(784.0, 0.16), (0.0, 0.06), (1175.0, 0.20), (0.0, 0.18)] * 2


def envelope(index: int, total: int) -> float:
    """Short attack/release so each beep does not click."""
    edge = int(0.01 * SAMPLE_RATE)
    if index < edge:
        return index / edge
    if index > total - edge:
        return max(0.0, (total - index) / edge)
    return 1.0


def samples():
    for freq, duration in NOTES:
        count = int(duration * SAMPLE_RATE)
        for i in range(count):
            if freq <= 0.0:
                yield 0
                continue
            value = math.sin(2 * math.pi * freq * i / SAMPLE_RATE)
            yield int(0.6 * envelope(i, count) * value * 32767)


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(b"".join(struct.pack("<h", s) for s in samples()))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
