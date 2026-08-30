# Factor suggestion

A proposal for the three bolus settings, computed from the doses already logged:
the **correction factor**, the **carbohydrate factor** and the **insulin
duration**. `lib/src/profile/tuning/`, shown under Bolus, beside the settings it
is about.

It shares `TuningControls`, `TuningModel` and the whole safety idea with the
basal suggestion (`docs/TUNING.md`); read that first. The difference is only the
unit of evidence: an hour there, the window after a logged dose here.

> An earlier correction-factor suggestion was removed along with the by-hour
> correction profile, on the grounds that somebody who always boluses with food
> has no correction-only dose. Such a user still gets nothing for the correction
> factor and the insulin duration, since neither can be read off a meal, and does
> get a carbohydrate factor from their meals. Silence for a setting that cannot
> be measured is the same answer this feature gives everywhere else.

> Not a medical device, and not a prescription.

## What counts as evidence

A window is not required to be quiet, it is required to be **measured**. What
else acted in it — insulin still working from an earlier dose, the automation, a
second meal — is computed by `TuningModel` and goes into the arithmetic, exactly
as in the basal tuning. Only these remain as refusals:

| Rule | Why |
|---|---|
| glucose present, and inside 70 to 250 mg/dL, at both ends | outside that the body is doing something a dose cannot explain |
| a correction of at least 0.5 U, from at least 140 mg/dL | insulin at a normal glucose is not a correction, whatever it was logged as |
| at least 20 g absorbed across a meal window | below that the carbohydrate estimate is the biggest term in the arithmetic |
| at least 80 % of the correction window covered by readings | a hole can hide the true lowest point |
| **the lowest point falls strictly inside the correction window** | see below |
| **the correction did not end in a hypoglycaemia** | see below |

The window is **5 h** after a meal dose (long enough for a slow meal). A
correction is watched for up to **8 h** — the top of what anybody sets as an
insulin duration, so the measurement is not capped by the setting it informs —
and is cut short at the next logged carbohydrates, because food hides the fall
being measured. Cut shorter than 2 h there is nothing left to read and the window
is dropped.

Two refusals point the same way, and both are about the ONE direction a wrong
correction factor must not go, namely claiming insulin is weaker than it is:

* **A correction that ended below 70 mg/dL is dropped.** The body stops the fall
  itself down there, so the measured drop is smaller than the insulin caused.
* **A fall still going when the window ended is dropped.** The drop measured so
  far understates the dose for the same reason.

## The arithmetic

The bolus calculator's own arithmetic, read backwards.

```
correctionFactor = median( (start - lowest) / insulinActing )   # corrections
carbFactor       = median( carbsAbsorbed / (insulinActing + drift / ISF) )
insulinDuration  = median( time from the dose to its lowest point )
```

The duration is measured from **every** window whose fall could be followed to
its end, meal windows included, so it is the one setting of the three that a log
of nothing but meals answers directly. The end of a meal's fall is the same event as the
end of a correction's: the food is long absorbed by then, so where glucose stops
falling is where the insulin stopped working. Without that, somebody who always
boluses with food could never get an answer for the setting. The lowest point is
taken after the window's PEAK, so a meal's own rise is not mistaken for the start
of the fall.

Measured against a simulated fortnight of meals with the sensor's own jitter on
top (`test/profile/tuning_glucose_test.dart`), nearly every window is readable
and the median lands on the four hours the curve was built with. It runs about
ten per cent LONG, because on a flat tail the lowest single reading drifts later
the longer the tail is. That direction is the harmless one: a longer duration
means more insulin counted as still on board, so the calculator suggests less.

Smoothing the readings first was tried against exactly that bias and removed
from the code again: it moved the median by a few minutes and cost usable
windows, because an averaged curve more often has its lowest point at the very
edge, where the window is refused.

`insulinActing` is every unit that worked in that window, not just the logged
dose: an earlier bolus still tailing off and the automation's excess are in
there, which is what lets a busy window be used at all. A window that landed back
where it started had its carbohydrates covered exactly by that insulin; one that
ended `drift` higher needed `drift / correctionFactor` more, and is measured
against that larger amount. The correction factor used there is the one currently
set, exactly as the basal suggestion uses it.

The same caveat as the basal tuning applies, for the same reason: `insulinActing`
and `carbsAbsorbed` come from a linear model, so a single window says little and
only the median of many says anything.

## The correction factor without a correction dose

One meal window cannot say what a unit does: its movement is the sum of the food
and the insulin, one equation with two unknowns, and any correction factor fits
it if the carbohydrate factor moves to match. A dose with no food of its own is
the only window that separates them, which is why it is preferred wherever there
is one.

**Many meal windows together are a different question.** Across them,

```
drift = base + perGram * carbsAbsorbed - perUnit * insulinActing
```

is three unknowns and one equation per window, so `CorrectionFactorFit` solves it
by least squares and `perUnit` is the correction factor. What makes that work on
real data is that a meal bolus is not a pure function of the carbohydrates: it
carries a correction for wherever glucose was at the time, it is rounded to the
pump's step, and the food is counted imperfectly. That variation is what pulls
the two columns apart.

Where the variation is genuinely absent it is refused, not guessed. Somebody who
always doses exactly `carbs / carbFactor` hands the fit two columns that are
multiples of each other, and **collinear columns inflate the standard error of
`perUnit`**, so one guard covers both "too few windows" and "these windows cannot
tell the two apart":

| Guard | Value |
|---|---|
| minimum meal windows | 20, against the 5 a median needs |
| standard error of `perUnit` | at most a quarter of `perUnit` itself |
| the result must be positive | insulin lowers glucose |

A suggestion that came out of the fit is **marked as inferred** in the card
(`samples_inferred`, "aus # Mahlzeiten erschlossen"), because a number read off a
correction dose and one solved across a month of meals are not equally strong
evidence, and the person tapping "adopt" is the one who should weigh that. When
neither route works, the card names the data that is missing
(`profile.tuning.factors.missing.*`) rather than leaving the user to wonder why
only one row appeared.

`test/profile/factor_regression_test.dart` pins it on windows built from a known
truth: it recovers the factor they were made with, and it refuses a log where the
insulin only ever follows the carbohydrates, one whose scatter swamps the answer,
and a handful of meals.

## What holds the proposal down

| Guard | Value |
|---|---|
| minimum windows per setting | 5 |
| the MEDIAN, not the mean | one unusual window cannot carry a setting, and it absorbs the model's timing error |
| snapped to the setting's own step, clamped to its own range | 5 mg/dL, 1 g, 1 h |
| nothing is adopted without a person reading both numbers and tapping | |

Every one of those is about the EVIDENCE rather than the size of the move, which
is the difference between a guard and friction.

A setting with too few windows produces **no row at all**, and a proposal landing
on the value in use is not shown either: the setting above already says that.

## One press, one answer

**The three settings are solved together, not one round at a time.** They move
each other: the carbohydrate factor is measured against the correction factor,
and the insulin duration decides what counts as insulin acting in a window, which
changes both factors and even which windows are usable. So one round of the
arithmetic is a step toward the answer rather than the answer, and adopting three
numbers used to leave a second round waiting for the next press.

`SettledFactors` runs the rounds instead: each one recomputes the suggestions
with the previous round's answers in place (rebuilding the windows when the
duration moved), until a round changes nothing, capped at `maxRounds`. What the
card offers is that fixed point, which is where somebody pressing the button
repeatedly would have ended up. Every row is still stated against the setting the
USER runs, not against the working value the last round used.

There is also **no per-run cap here**, unlike the basal tuning. There was one, a fifth
of the value in use, and it held nothing back: pressing the button three times
walked to the same number anyway, one step per press. A guard that three taps
bypass is not a guard, it is friction, and it made the analysis look like it kept
changing its mind. A proposal is now the measurement itself, and the press after
adopting it has nothing left to change.

That is safe to do here and would not be on the basal, because none of these
three settings feeds back into its own measurement: the correction factor is read
off the glucose and the insulin that moved it, and adopting it does not move that
reading. The basal suggestion is the one where a proposal changes what the next
measurement is compared against, which is why it keeps both its cap and its
`runningSince` gate (`docs/TUNING.md`).

## It is never applied

Each proposal appears as a row under the settings, showing the value in use and
the proposed one in the same words the setting itself uses, with an **Adopt**
button. Nothing changes until that is tapped, and an adopted row disappears
because the setting now IS that number.

Unlike the basal suggestion, there is no new profile to write: these are three
single numbers, so the row itself is the whole proposal.

## Tests

`test/profile/factor_tuning_test.dart` pins both halves: that each neighbour is
MEASURED into the window (an earlier bolus, the automation) or shortens it (food
after a correction) while unusable windows are still dropped (an unanswerable
automation record, a hypo, a fall still going at the end, a correction from a
normal glucose, a gap in the readings), and that the output is bounded (too few
windows say nothing, an outlier does not move a setting, a far-off measurement is
offered in full, a meal window measures the duration, everything stays inside the
setting's own range). `test/profile/settled_factors_test.dart` pins the fixed
point: the answer reproduces itself, and it is not where a single round lands.
