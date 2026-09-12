#!/usr/bin/env python3
"""Generate the short alarm tones in assets/sounds/ (stdlib only).

Every tone encodes its alarm type in the motif itself, so the alarm can be told
apart by ear alone even when it only lasts half a second:

  direction  low = two notes falling, high = two notes rising
  count      warning = motif twice, urgent = motif three times, faster
  advisory   a single soft glide in the alarm's direction, no repetition

Styles differ only in timbre and length, never in that coding, so mixing styles
across slots stays unambiguous. Run: python3 tool/generate_alarm_tones.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"
LOW_NOTES = (988.0, 659.0)
HIGH_NOTES = (659.0, 988.0)
RAMP = 0.005


def note(frequency, seconds, gain, harmonics, decay):
  """One note: harmonic partials, click-free edges, optional bell decay."""
  samples = []
  total = int(seconds * RATE)
  for index in range(total):
    time = index / RATE
    value = sum(
      level * math.sin(2 * math.pi * frequency * partial * time)
      for partial, level in harmonics
    )
    envelope = math.exp(-time / decay) if decay else 1.0
    ramp_in = min(1.0, time / RAMP)
    ramp_out = min(1.0, (total - index) / RATE / RAMP)
    samples.append(value * gain * envelope * ramp_in * ramp_out)
  return samples


def silence(seconds):
  return [0.0] * int(seconds * RATE)


def glide(start, end, seconds, gain):
  """A single note sliding from start to end Hz: the advisory signature."""
  samples = []
  total = int(seconds * RATE)
  phase = 0.0
  for index in range(total):
    frequency = start + (end - start) * (index / total)
    phase += 2 * math.pi * frequency / RATE
    envelope = math.sin(math.pi * index / total) ** 0.6
    samples.append(math.sin(phase) * gain * envelope)
  return samples


def repeated(notes, style, urgent):
  """The direction motif, repeated as often as the urgency says."""
  length, gap, repeats = style["urgent"] if urgent else style["warning"]
  harmonics = style["harsh"] if urgent else style["soft"]
  gain = 0.85 if urgent else 0.65
  track = []
  for repeat in range(repeats):
    for frequency in notes:
      track += note(frequency, length, gain, harmonics, style["decay"])
      track += silence(style["inner_gap"])
    if repeat < repeats - 1:
      track += silence(gap)
  return track


def write(name, samples):
  path = OUT / f"{name}.wav"
  with wave.open(str(path), "wb") as target:
    target.setnchannels(1)
    target.setsampwidth(2)
    target.setframerate(RATE)
    target.writeframes(
      b"".join(
        struct.pack("<h", max(-32767, min(32767, int(sample * 32767))))
        for sample in samples
      )
    )
  print(f"{path.name}: {len(samples) / RATE:.2f}s")


STYLES = {
  # (note length, gap between motifs, repeats) per urgency, plus timbre.
  "short": {
    "warning": (0.13, 0.18, 2),
    "urgent": (0.11, 0.07, 3),
    "inner_gap": 0.02,
    "soft": ((1, 0.8), (3, 0.25)),
    "harsh": ((1, 0.7), (2, 0.4), (3, 0.3)),
    "decay": 0,
    "advisory": 0.55,
  },
  "ping": {
    "warning": (0.16, 0.12, 2),
    "urgent": (0.14, 0.05, 3),
    "inner_gap": 0.0,
    "soft": ((1, 0.8), (2, 0.3), (3, 0.12)),
    "harsh": ((1, 0.8), (2, 0.45), (3, 0.25)),
    "decay": 0.1,
    "advisory": 0.35,
  },
}


def main():
  for style_name, style in STYLES.items():
    for direction, notes in (("low", LOW_NOTES), ("high", HIGH_NOTES)):
      for urgency, urgent in (("warning", False), ("urgent", True)):
        write(f"{direction}_{urgency}_{style_name}", repeated(notes, style, urgent))
      start, end = notes
      write(
        f"advisory_{direction}_{style_name}",
        glide(start, end, style["advisory"], 0.35),
      )


if __name__ == "__main__":
  main()
