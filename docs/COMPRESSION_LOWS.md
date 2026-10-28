# Compression lows

Lying on the sensor squeezes the tissue around it. The reading drops, often
below 70 mg/dL, and comes back as soon as the sleeper turns over. These lows are
not in the blood, but they count in time below range, pull down the nightly
pattern and alarm at night.

The full-screen chart and the analysis page filter them out afterwards
(`lib/src/analysis/compression/`). **Live it cannot work**: what gives a
compression away is the fast rise *after* the low. So the filter never touches
an alarm, the overview's own small chart, the loop or the event log.

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

One switch, in the full-screen chart's app bar beside the slope and the meals
(a bed: filled while the lows are hidden). It is stored
(`analysis_hide_night_compression`, on by default) and held by one
`NightCompressionState` above the page tree, so the chart and the analysis page
always agree. On, the chart draws without those readings (a dip shorter than
the chart's 20-minute gap is bridged, a longer one leaves a gap), and time in
range, patterns, averages and the history compute without them. Off, both show
the raw readings. The forecast check always reads the raw archive, since it
measures the forecast against what the sensor said.

The state works per night, not per window. The chart asks for seven days and
the analysis for whatever its picker says; a result kept per window had each
request undo the other's. Each night is searched once from the archive itself
(`CgmController.archiveBetween`) and the stored pulse, in the background, and
the views redraw when it is known, so a night shows its raw readings for a
moment the first time. A night two days old is kept; a younger one is searched
again at most every five minutes, since its readings and pulse may still be
arriving.

## Not built

- Marking the left-out stretch in the chart. Switched off, the raw dip is
  there to see; switched on, it is simply not drawn.
- Leaving compression lows out of the basal and factor suggestions
  (`docs/TUNING.md`, `docs/FACTOR_TUNING.md`). They read the raw archive.
