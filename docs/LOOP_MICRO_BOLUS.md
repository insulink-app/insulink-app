# Micro boluses

> Not a medical device. Every setting below makes the automation faster or slower
> to act; choosing them is a therapy decision and belongs to the user.

The loop's rate is slow by construction: the default ceiling of 3 U/h delivers at
most 0.25 U per five-minute cycle, so a steep rise gets about 0.75 U in the first
15 minutes. Rapid-acting insulin needs 15 to 20 minutes before it works, so
insulin that arrives late works late.

A single large bolus is not the answer. The sensor lags and can be wrong, a rise
can turn, and a bolus cannot be taken back. The micro bolus (SMB, as in
oref1/AAPS/Trio) is the middle ground: **each cycle gives a capped share of the
missing insulin at once, and five minutes later decides again on a fresher
reading and the updated insulin on board.**

## How a cycle uses it

1. `LoopAlgorithm.correctionUnits` works out the missing insulin, the same figure
   the rate is built from.
2. `LoopSafety.decide` decides the rate exactly as before. Suspensions, a busy pod
   and unusable input all end the cycle there, so they also rule out a micro bolus.
3. `LoopMicroBolusSafety.apply` adds the micro bolus, if any, and then caps the
   rate at the schedule. **The micro bolus IS the correction**; a rate above
   schedule next to it would give the same insulin twice.
4. The runner programs the rate first, then the micro bolus. If the link drops
   between the two, the half that landed is the one that can only lower insulin.

## Ceilings

Each one only lowers the dose, never refuses outright, like the rate's:

| Ceiling | Bound recorded as |
|---------|-------------------|
| share of the missing insulin (setting) | (the request itself) |
| largest single micro bolus (setting) | `maxMicroBolus` |
| automated insulin per hour (setting): the rate's excess AND micro boluses within the hour, so the two paths cannot each fill an hour of their own | `microBolusHourly` |
| hypo headroom, the WHOLE dose, nothing spread over the fuse | `hypoHeadroom` |
| highest active insulin | `maxIob` |
| reservoir | `reservoir` |

Then the dose is snapped DOWN to the 0.05 U pulse grid, after adding 1e-9 so a
ceiling of exactly 0.30 U that arrives as 0.2999999 does not lose a pulse.

The hypo headroom is the one that matters. The rate may count on the next cycle
to undo it; a bolus may not. So the micro bolus must fit, whole, between glucose
now and the stop threshold, after the insulin already on board.

## Gates

No micro bolus at all when it is switched off, when the rate came out at zero
(every suspension), below the user's glucose threshold, on a level or falling
trend while "only while rising" is set, inside the user's minimum interval, or
**within the pause after a low**: any reading at or below 70 mg/dL in the
last 90 minutes (setting). It used to be the stop threshold, but that sits as
high as 100 to 120 for some users, and an ordinary value before a meal then
blocked micro boluses for the whole rise after it. The rise after treating a low is sugar eaten on
purpose; read as a trend it would be corrected straight back into the next low.
Readings under 30 that the trend ignores still count as a low here. For this the
service hands `LoopGlucose` three hours of history (`LoopGlucose.lookback`), and
the trend still uses only the last 20 minutes of it. The interval allows one
minute of slack, because a micro bolus is booked a few seconds into its cycle and
an interval of five minutes would otherwise skip every second cycle.

## Accounting

A micro bolus is booked in its own ledger (`LoopMicroBolusLedger`, key
`pod.loop_micro_boluses`) BEFORE the command goes out, the same direction of
failure as the rate: a confirmation that never arrives leaves it counted, so the
next cycle asks for less. Only a refusal from the pod takes it back out.

Not the delivery log: one entry every five minutes would push the user's own
boluses out of it within a day.

The ledger feeds `loopIobUnits` (so the automation, the bolus calculator and the
hourly ceiling all see it) and the automation record the basal analysis reads.
The journal cycle carries the units and the bound for display only.

## Settings

| Setting | Key | Default | Range |
|---------|-----|---------|-------|
| allow micro boluses | `loop_micro_bolus_enabled` | off | |
| only while glucose is rising | `loop_micro_bolus_only_rising` | on | |
| largest single micro bolus | `loop_micro_bolus_max_tenths` | 0.5 U | 0.1 to 3.0 U |
| share of the missing insulin | `loop_micro_bolus_share_percent` | 50 % | 10 to 100 % |
| micro boluses from | `loop_micro_bolus_from_mgdl` | 140 mg/dL | 100 to 250 |
| at most every | `loop_micro_bolus_every_minutes` | 5 min | 5 to 60 |
| pause after a low | `loop_micro_bolus_pause_after_low_minutes` | 90 min | 30 to 180 |
| automated insulin per hour at most | `loop_micro_bolus_max_per_hour` | 2 U | 1 to 10 U |
| hold a manual bolus for at most | `loop_micro_bolus_queue_seconds` | 60 s | 15 to 180 |

They sync with the account like the other loop limits. The single-dose ceiling is
stored in tenths so it keeps the integer editor; `NotificationThreshold.tenths`
shows it with one decimal.

## A manual bolus while a micro bolus runs

The pod runs one bolus at a time, about 2 s per 0.05 U, and refuses a second.
So a micro bolus is also written as the pod's running bolus (`automated: true`),
and a manual bolus queues behind it (`MicroBolusQueue`, called first thing in
`BolusDelivery.deliver`):

- The store is re-read, since the micro bolus was written by the service isolate.
- Time left within the limit (setting, default 60 s): the dose waits that long
  plus 3 s, then goes out as usual. The overview shows the micro bolus with
  "your bolus follows" under it.
- Time left past the limit: refused at once, telling the user how many seconds
  are left, rather than leaving them unsure whether the dose went out.
- A MANUAL bolus still running is never queued behind: that is a second tap, and
  the guard refuses it as before, now in the user's language.

The wait happens before the dose is marked pending, so an app killed while
waiting leaves no trace of a dose that was never sent. If the pod is still busy
after all (a micro bolus that started after the queue looked), the guard on the
same link refuses it, so nothing is ever sent twice.

Stopping a micro bolus from the overview corrects its ledger entry to what went
in, and raises no "meal not corrected" notice, since no meal carries it.

## Where a micro bolus shows

- **Pod delivery log** ("Abgegebenes Insulin"): one row per micro bolus of the
  last day, in a lighter bolus colour, and its own figure in the pod total. The
  rows come from the ledger (24 h); the total is a running sum per pod
  (`loopMicroBolusTotal`), because a pod outlives the ledger.
- **Active insulin page**: the graph stacks the rate's excess, the micro boluses
  and the user's boluses (`InsulinOnBoardCurve`). Each part is sampled as it was
  at that moment, and ahead of now only what is already in decays.
- **Automation journal**: the cycle with the units and the ceiling that held it.

## What happens around a low

A micro bolus cannot be taken back. Once given, the only lever left is the rate:
suspending the schedule withholds about 0.5 U per half hour. So everything that
protects against a low has to act BEFORE the dose:

1. At or under the stop threshold, or heading under it within 30 minutes: rate
   zero, and a zero rate rules out a micro bolus.
2. Under "micro boluses from" (default 140 mg/dL): rate only.
3. Within the pause after a low: rate only.
4. Otherwise the whole micro bolus plus the insulin on board has to fit between
   glucose now and the stop threshold, at the user's correction factor.

What is left is a correction factor that is wrong, or a sensor that reads high.
Neither is visible to the loop, and the micro bolus reaches the same ceiling
faster than the rate did.

## Measured

A scratch simulation drove the real decision code (`LoopAlgorithm`,
`LoopSafety`, `LoopMicroBolusSafety`, the journal and the ledger) against a
simple body: oref0 exponential insulin action (peak 75 min, 5 h) while the loop
assumes its linear 3 h, carbohydrates absorbed on a gamma curve, correction
factor 35, carb factor 15 g/U, schedule 1 U/h, rate ceiling 3 U/h. Six hours per
run. A model, not a patient: absolute numbers are not clinical, the differences
between rows are the point.

| Scenario | temp only | micro, 2 U/h (default) | micro, 3 U/h |
|----------|-----------|------------------------|--------------|
| 80 g unannounced: peak / time > 180 | 252 / 190 min | 243 / 168 min | 238 / 152 min |
| 80 g, bolus for 50 g: peak / > 180 | 216 / 135 min | 213 / 121 min | 213 / 121 min |
| 80 g, full bolus | 190 / 84 min | 190 / 84 min | 190 / 84 min |
| 50 g unannounced: peak / > 180 | 182 / 34 min | 176 / 0 min | 175 / 0 min |
| 80 g, insulin 50 % stronger than set: lowest after 1 h | 123 | 125 | 125 |
| low at 65, overtreated with 40 g: lowest after 1 h | 114 | 114 | 114 (121 and +0.7 U without the pause) |
| sensor 60 too high for 90 min: lowest / time < 70 | 73 / 0 | 76 / 0 | 67 / 66 min |

Read: the gain is on large rises without a full bolus, roughly a tenth to a
fifth less time above 180 and 10 to 15 mg/dL off the peak. With a correct bolus
there is nothing to gain. A short spike only moves the same insulin earlier and
takes it back as a suspended schedule later. The cost is a sensor reading high,
and the hourly setting is what decides it: at 3 U/h the low is deeper than with
the rate alone, at 2 U/h it is not.

## Not here

- **No carbohydrate-dependent gating** (AAPS's "SMB after carbs" and friends).
  Add it once the journal shows micro boluses where nobody wanted one.
- **Micro boluses are not synced to the account as insulin.** The rate's excess
  reaches it through the basal booking; a micro bolus does not, so the panel
  and the predictor do not see it yet.
- **No confirmation dialog** when switching it on, unlike the loop itself.
