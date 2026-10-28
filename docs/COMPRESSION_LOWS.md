# Compression lows

Lying on the sensor squeezes the tissue around it. The reading drops, often
below 70 mg/dL, and comes back as soon as the sleeper turns over. These lows are
not in the blood, but they count in time below range, pull down the nightly
pattern and alarm at night.

Both glucose charts (the overview's and the full-screen one), the time in
range under the overview chart and the analysis page filter them out afterwards
(`lib/src/analysis/compression/`). **Live it cannot work**: what gives a
compression away is the fast rise *after* the low. So the filter never touches
an alarm, the loop or the event log.

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
is why the filter can be switched off.

## Sleep from the pulse

The resting level is the 10th percentile of the pulse between midnight and
5:00. A minute is asleep when the 30-minute median around it is within 10 bpm
of that level. The sleep is the longest such stretch from 20:00 to 11:00,
bridging up to 20 minutes awake, and must last at least 3 hours. A night with
fewer than 120 minutes of pulse after midnight has no sleep, so without a band
nothing is ever filtered.

## The switch

One stored switch (`analysis_hide_night_compression`, on by default), held by
one `NightCompressionState` above the page tree, so every place that filters
agrees. It is in two places: the bed in the full-screen chart's app bar, beside
the slope and the meals (filled while the lows are hidden), and the profile's
glucose page (`CompressionFilterToggle`), with a line on what it does.

On, time in range (overview and analysis), patterns, averages and the history
compute without those readings. The charts do not just drop them
(`CompressionChartView`): a dashed line in the glucose line's colour bridges
the reading before the fall and the one after the rise. A gap would read as a
sensor outage and a solid line as measured; the dashes read as filled in. The
background stays as it is. Off, everything shows the raw readings. The forecast check
always reads the raw archive, since it measures the forecast against what the
sensor said.

The state works per night, not per window. The chart asks for seven days and
the analysis for whatever its picker says; a result kept per window had each
request undo the other's. Each night is searched once from the archive itself
(`CgmController.archiveBetween`) and the stored pulse, in the background, and
the views redraw when it is known, so a night shows its raw readings for a
moment the first time. A night two days old is kept; a younger one is searched
again at most every five minutes, since its readings and pulse may still be
arriving.

## Not built

- Leaving compression lows out of the basal and factor suggestions
  (`docs/TUNING.md`, `docs/FACTOR_TUNING.md`). They read the raw archive.
