# Basal suggestion

A proposal for what the basal profile could look like, computed from data
already stored. `lib/src/profile/tuning/`.

It lives **inside the section it is about**, under Basal profile: a proposal
about a thing belongs next to the thing.

> There is a second suggestion beside it, about the three bolus settings:
> `docs/FACTOR_TUNING.md`. It lives under Bolus, for the same reason this one
> lives under Basal profile.

> Not a medical device, and this in particular is not a prescription. Read
> `docs/OMNIPOD.md` and `docs/LOOP.md` first.

## Measured, not thrown away

The danger is unchanged: glucose drift has several possible causes at once, and
software that attributes an unexplained rise to basal will raise the basal.
**A basal raised because of a forgotten biscuit is a night-time hypoglycaemia
days later.**

The first version answered that by refusing: an hour counted only if it had no
food within 4 h, no bolus within one insulin duration and no automation. That is
the safest possible rule, and it leaves most users with a handful of quiet nights
a month, which is not enough to be useful. So the other causes are now
**measured and subtracted** instead of disqualifying the hour (`TuningModel`):

```
unexplained = drift
            + insulinActing * correctionFactor       # this insulin was not basal
            - carbsAbsorbed * correctionFactor / carbFactor
```

`insulinActing` is the bolus and automation insulin that acted in that hour,
`carbsAbsorbed` the grams absorbed in it. Scheduled basal is in neither: it is
the thing being tuned. On a quiet hour both are zero and the arithmetic is
exactly what it always was.

**What that costs is real and worth stating.** Both terms come from a linear
model: insulin acts evenly over the configured duration, food absorbs evenly over
4 h. Real ones peak, so the model misplaces effect WITHIN an hour. A single
post-meal hour is therefore worth little; what makes a proposal out of them is
the median across days and the 20 % cap below.

`TuningHourFinder` now drops an hour only when the data is missing or unusable:

| Rule | Why |
|---|---|
| glucose outside 70 to 250 mg/dL | counter-regulation is doing something a rate cannot explain |
| a reading missing at either end of the hour | a guessed drift becomes a real basal change |

Plus one refusal in the suggestion itself: an hour where either model term
exceeds **100 mg/dL** is dropped, because the answer would then be arithmetic
about absorption timing rather than a reading.

## The daily amount is free to change

Each hour moves on its own evidence and the total is whatever the hours add up
to. **It is deliberately NOT held constant.** A profile that gave too little
insulin overnight needs more insulin, not the same amount shuffled around the
clock, and a suggestion that preserved the total could only ever move insulin
from an hour that was fine into an hour that was not.

A suggested profile carries **no peaks**. Those are an input to the editor's
curve generator, not a description of rates, and the ones on the profile this was
measured against describe a different day. The editor does not regenerate on
open, so the measured hours stand; asking it to generate there is asking for a
curve INSTEAD of the measurement, and gets an obviously flat one rather than a
plausible-looking wrong one.

## The arithmetic

Deliberately the plainest thing that works. Whatever an hour did that food and
insulin do not account for is basal that was missing:

```
suggested = currentRate + medianUnexplained / correctionFactorAt(hour)
```

The correction factor is read per hour, so a user on a daily profile
(`CorrectionProfile`) gets night hours judged by their night factor.

## What holds the proposal down

| Guard | Value | Why |
|---|---|---|
| minimum hours | 3 per hour of day | three days is the least that is worth a word |
| the MEDIAN, not the mean | | one bad day must not carry an hour, and it absorbs the model's timing error |
| model share per hour | at most 100 mg/dL from either term | beyond that the answer is mostly model |
| maximum change | 20 % of the current rate, at least 0.1 U/h | a week is thin evidence and the cost of being wrong is asymmetric |
| snapped to the pump grid | 0.05 U/h | |
| floored at zero | | |

An hour without enough usable data produces **no entry at all**. Silence is the
honest answer, not "unchanged".

## Pressing it twice must not move the basal twice

What this measures is glucose drifting **under the rates that were running at
the time**. So an hour from before the last change describes a schedule that no
longer exists, and adding its drift to rates that already carry the correction
counts it twice: adopt a proposal, press again, and the same historical drift
walks the basal further in the same direction, forever.

`ProfileBasalState.runningSince` is the fix. It is stamped whenever the ACTIVE
rates change (a switch, an edit, adopting a suggestion), and NOT when the list
around them changes, so a suggestion landing beside the others as an inactive
profile leaves the clock alone. The analysis starts its window there, and right
after a change there is nothing to say yet, which the card states
(`profile.tuning.since_change`) rather than repeating itself.

The cost is that a person who edits their basal weekly never accumulates enough
hours. That is the correct answer rather than a limitation: nobody can measure a
schedule that is never left running.

## It is never applied

The result is written as **its own basal profile**, sitting beside the others and
INACTIVE (`ProfileBasalState.addInactiveProfile`). Picking it is a separate,
deliberate act in the basal section, exactly like switching between a weekday and
a weekend profile.

That is not an oversight to be tidied up later. A few quiet nights do not justify
software moving someone's overnight insulin on its own, and the whole point of
the analysis is to hand a person something they can judge, in a form they can
then edit and compare against what they were running.

## Generated on demand, always over 30 days

The person asking has a reason to ask, and a proposal that appears on a schedule
by itself is one nobody reads. So it is a button.

The period is fixed at `TuningControls.windowDays`. There used to be a picker for
7, 30 or 90 days, and it was removed: it is a decision the user has no basis for
making, and the answer was the same one every time. A month is long enough to
average out a bad week and short enough to still describe the person you are
now.

The button just **makes a profile**. It lists nothing: the new entry appearing in
the picker directly above it is the answer, and repeating its contents underneath
would say the same thing twice, in a place where it cannot be edited or compared
with anything.

The only thing it does say is when NOTHING was made, either because there was too
little usable data or because the profile already fits. A button that silently does
nothing looks broken.

The profile is named with its period and the date it was made, because a list of
three profiles all called "Suggestion" is useless.

## Reading the archive

Both analyses ask for glucose at a moment: an hour boundary, a logged dose time.
The archive is keyed by the minute a reading ACTUALLY happened and a sensor
delivers every five minutes on its own phase, so an exact-minute lookup misses
four times out of five. That is not a rounding detail: it dropped nearly every
hour and every dose window for having no reading, and BOTH suggestions answered
"not enough data" whatever window was chosen.

`TuningGlucose` takes the nearest reading within six minutes, a little over one
cadence, so a normal gap is always covered while a genuine hole still reads as
missing. Every call site goes through it. `test/profile/tuning_glucose_test.dart`
pins the end to end shape: a week of five-minute readings yields all 168 hours,
and a week of logged meals yields all 21 dose windows.

## Tests

`test/profile/basal_tuning_test.dart` pins both halves: that each confounder is
MEASURED into its hours (carbs over the absorption time, a bolus and the
automation over the insulin duration) while unusable hours are still dropped
(implausible glucose, a gap in the readings, an unanswerable automation record),
and that the proposal is bounded (a rise the food explains asks for nothing, an
hour the model dominates is dropped, too few samples says nothing, an outlier
night does not move an hour, a wild drift is capped, no negative rate, everything
on the grid).

## The automation record does not clip the window

An hour only counts when what the automation delivered in it is known, and that
question is asked of a durable record of the hours it ran above the schedule
(`PodStore.automationExcessInHour`), kept alongside the pod's data but outside
it.

**Hours from before that record began are used, not dropped.** The record starts
the first time the automation is ever switched on (`PodLoopJournal.saveLoopMode`),
so before that moment nothing could have been running and there is nothing to
clear. Dropping them clipped every window to the age of the automation, which is
why a longer period changed nothing: somebody who turned the loop on last week
got last week whatever they asked for, and both suggestions said "not enough
data" forever.

What that leaves is an install whose record began late, where an hour the
automation drove reads as carrying less insulin than it did. Every result then
leans toward LESS insulin (a smaller basal, a weaker correction factor, a larger
carbohydrate ratio), which is the safe direction and the same one the record's
own pruning at 400 hours errs in.

## Why the record exists at all

An hour only counts when the automation was NOT adding insulin during it, and
that question has to be answerable. It is asked of a durable record of the hours
the automation delivered above the schedule (`PodStore.automationExcessInHour`),
kept alongside the pod's data but deliberately outside it.

Two earlier versions were both too short-sighted to be useful:

* The **loop journal** keeps 288 cycles and so reaches exactly one day back.
  Beyond that it answered "no automation" for every hour, whether or not any had
  run, and an hour the automation drove would then have counted as evidence about
  the SCHEDULE. Its glucose fell because of extra insulin, so it would have
  argued for lowering a basal rate that was never the reason.
* The **pod's hourly basal ledger** is cleared by `forgetPod`, and a pod lives
  eighty hours. The record reset at every pod change and was near-empty the
  morning after one, so nearly every hour became unanswerable and the analysis
  reported "not enough data" for a user who had weeks of it.

So the record now outlives the pod: it is the user's insulin history, not the
pod's. An hour with no entry is an hour with no excess, so only the hours that
CARRIED excess have to be stored, and those are few.
