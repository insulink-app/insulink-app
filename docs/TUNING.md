# Basal suggestion

A proposal for what the basal profile could look like, computed from data
already stored. `lib/src/profile/tuning/`.

It lives **inside the section it is about**, under Basal profile: a proposal
about a thing belongs next to the thing.

> A matching suggestion for the correction factor was built and then removed
> along with the whole by-hour correction profile. It could only measure insulin
> given WITHOUT food, and somebody who always boluses with a meal has no such
> dose, so for them it could never produce anything however long the window. A
> setting that cannot be filled from data is a setting filled by guessing, and
> the correction factor is now a single number again.

> Not a medical device, and this in particular is not a prescription. Read
> `docs/OMNIPOD.md` and `docs/LOOP.md` first.

## The one thing that makes this safe

**Nothing is attributed.** Glucose drift has several possible causes at once: too
little basal, a wrong carbohydrate ratio, a wrong correction factor, a snack
nobody logged. Software that attributes an unexplained rise to basal will raise
the basal, and **a basal raised because of a forgotten biscuit is a night-time
hypoglycaemia days later.**

So an hour is used only when every OTHER cause has been ruled out, and every hour
that cannot be cleared is thrown away. `CleanHourFinder` drops an hour when any
of these is true:

| Rule | Why |
|---|---|
| carbohydrates within 4 h before it, or during it | slow food is exactly what gets mistaken for a basal problem |
| a bolus within one insulin duration | insulin still working is not basal |
| the automation added anything above the schedule | that insulin says nothing about what the SCHEDULE should be |
| glucose outside 70 to 250 mg/dL | counter-regulation is doing something a rate cannot explain |
| a reading missing at either end of the hour | a guessed drift becomes a real basal change |

After an ordinary week that leaves quiet nights and little else. **That is the
output working, not failing.** Fewer hours, and the ones left mean what they
appear to mean.

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

Deliberately the plainest thing that works. If glucose drifted up by D mg/dL over
a clean hour, the insulin missing from that hour is `D / correctionFactor`, so
that hour's rate wants to be that much higher:

```
suggested = currentRate + medianDrift / correctionFactorAt(hour)
```

The correction factor is read per hour, so a user on a daily profile
(`CorrectionProfile`) gets night hours judged by their night factor.

Anything more elaborate would be modelling data this deliberately refuses to
collect.

## What holds the proposal down

| Guard | Value | Why |
|---|---|---|
| minimum clean hours | 3 per hour of day | three nights is the least that is worth a word |
| the MEDIAN drift, not the mean | | one bad night must not carry an hour |
| maximum change | 20 % of the current rate, at least 0.1 U/h | a week is thin evidence and the cost of being wrong is asymmetric |
| snapped to the pump grid | 0.05 U/h | |
| floored at zero | | |

An hour without enough clean data produces **no entry at all**. Silence is the
honest answer, not "unchanged".

## It is never applied

The result is written as **its own basal profile**, sitting beside the others and
INACTIVE (`ProfileBasalState.addInactiveProfile`). Picking it is a separate,
deliberate act in the basal section, exactly like switching between a weekday and
a weekend profile.

That is not an oversight to be tidied up later. A few quiet nights do not justify
software moving someone's overnight insulin on its own, and the whole point of
the analysis is to hand a person something they can judge, in a form they can
then edit and compare against what they were running.

## Generated on demand, over a window you choose

7, 30 or 90 days. The person asking has a reason to ask, and a proposal that
appears on a schedule by itself is one nobody reads. A longer window is also the
answer when a short one has too few clean hours, which after a busy week it
usually does.

The button just **makes a profile**. It lists nothing: the new entry appearing in
the picker directly above it is the answer, and repeating its contents underneath
would say the same thing twice, in a place where it cannot be edited or compared
with anything.

The only thing it does say is when NOTHING was made, either because there was too
little clean data or because the profile already fits. A button that silently does
nothing looks broken.

The profile is named with its window and the date it was made, because a list of
three profiles all called "Suggestion" is useless.

## Tests

`test/profile/basal_tuning_test.dart` pins both halves: that each confounder
drops the hours it touches (carbs, bolus, automation, implausible glucose, a gap
in the readings), and that the proposal is bounded (too few samples says nothing,
an outlier night does not move an hour, a wild drift is capped, no negative rate,
everything on the grid).

## Hours the automation record cannot clear

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
pod's. What makes it usable is `automationCoveredSince`, the moment it started
being kept. From then on an hour with no entry is an hour with no excess, so only
the hours that CARRIED excess have to be stored, and those are few. Hours before
that moment are **dropped**, not trusted: nothing can be said about them either
way.

The cost is that the feature is quiet on a fresh install and gets better the
longer the app runs. That is the correct direction for a suggestion about a
basal rate.
