# Compression lows

Lying on the sensor squeezes the tissue around it. The reading drops, often
below 70 mg/dL, and comes back as soon as the sleeper turns over. These lows are
not in the blood, but they count in time below range, pull down the nightly
pattern and alarm at night.

The analysis page filters them out afterwards (`lib/src/analysis/compression/`).
**Live it cannot work**: what gives a compression away is the fast rise *after*
the low. So the filter never touches an alarm, the overview, the loop or the
event log. It only changes what the analysis views read.

## What counts

A run of readings under 70 whose lowest reading

1. lies in the night's **sleep**, read off the stored minute pulse
   (`NightSleepDetector`), and
2. is followed within **20 minutes** by a rise of at least **20 mg/dL** at
   **1.5 mg/dL a minute** or faster, and
3. has **no meal logged** from 30 minutes before the fall to the top of the
   rise (`CompressionLows`).

The readings between the top before the fall and the top after the rise are
left out. They are not replaced: the views treat that stretch as unmeasured.

Why the rise: a real low at night with nothing eaten recovers slowly, under
about 1 mg/dL a minute, since nothing but the liver and fading insulin lifts it.
On 30 days of one user who confirmed they ate nothing at night, sleep lows with
a rise of 1.5 a minute or more were 9 of 28, among them two of the three below
54. The slow ones stayed between 54 and 68.

The rule assumes **food is logged**. Glucose tablets taken at night and not
logged rise just as fast, and that low would be filtered as a compression. This
is why the filter can be switched off on the page, and why its count stands
next to the switch.

## Sleep from the pulse

The resting level is the 10th percentile of the pulse between midnight and
5:00. A minute is asleep when the 30-minute median around it is within 10 bpm
of that level. The sleep is the longest such stretch from 20:00 to 11:00,
bridging up to 20 minutes awake, and must last at least 3 hours. A night with
fewer than 120 minutes of pulse after midnight has no sleep, so without a band
nothing is ever filtered.

## On the page

`NightCompressionNote` sits under the window picker while the window holds any
compression lows: their count and a switch. On (the default, stored as
`analysis_hide_night_compression`), time in range, patterns, averages and the
history read the filtered archive. Off, they read the raw one. The forecast
check always reads the raw archive, since it measures the forecast against
what the sensor said.

`NightCompressionState` loads the pulse in the background and redraws the views
once the lows are known, so a freshly opened window shows the raw numbers for a
moment. A night's sleep is cached once it is two days old.

## Not built

- Marking the left-out stretch in the history chart. The chart averages per
  bucket, so a single dip is hardly visible there anyway.
- Leaving compression lows out of the basal and factor suggestions
  (`docs/TUNING.md`, `docs/FACTOR_TUNING.md`). They read the raw archive.
