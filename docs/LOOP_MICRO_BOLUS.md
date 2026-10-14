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
| micro-bolus insulin per hour (setting) | `microBolusHourly` |
| hypo headroom, the WHOLE dose, nothing spread over the fuse | `hypoHeadroom` |
| highest active insulin | `maxIob` |
| reservoir | `reservoir` |

Then the dose is snapped DOWN to the 0.05 U pulse grid, after adding 1e-9 so a
ceiling of exactly 0.30 U that arrives as 0.2999999 does not lose a pulse.

The hypo headroom is the one that matters. The rate may count on the next cycle
to undo it; a bolus may not. So the micro bolus must fit, whole, between glucose
now and the stop threshold, after the insulin already on board.

## Gates

No micro bolus at all when it is switched off, when the rate came out at zero,
below the user's glucose threshold, on a level or falling trend while "only while
rising" is set, or inside the user's minimum interval. The interval allows one
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
| micro boluses per hour at most | `loop_micro_bolus_max_per_hour` | 3 U | 1 to 10 U |

They sync with the account like the other loop limits. The single-dose ceiling is
stored in tenths so it keeps the integer editor; `NotificationThreshold.tenths`
shows it with one decimal.

## Not here

- **No carbohydrate-dependent gating** (AAPS's "SMB after carbs" and friends).
  Add it once the journal shows micro boluses where nobody wanted one.
- **Micro boluses are not synced to the account as insulin.** The rate's excess
  is not either; both live in the pod store and the automation record.
