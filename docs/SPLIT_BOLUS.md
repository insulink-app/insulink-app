# Split bolus

> Not a medical device. How much goes in now and over how long the rest is spread
> is a therapy decision and belongs to the user.

For drinks and meals that are absorbed slowly, the bolus calculator offers
**"Verzögert abgeben"**: a share goes out at once (0/25/50/75 %), the rest is
spread over 30 to 120 minutes. Only with a pod paired and only while the
background service runs, because the service gives the later parts.

## Why not the pod's own extended bolus

The DASH bolus command (`0x17`) has fields for an extended part, and the `0x1a`
interlock would need extra half-hour segments in its table. That encoding is not
documented for DASH in any open source, and AndroidAPS and Loop do not offer it.
A wrong byte there is a wrong dose, so `PodProgramBolusCommand` keeps those
fields zero. Adding it needs a BLE HCI capture of the original PDM giving an
extended bolus, turned into known-answer tests like the J-PAKE ones.

So the rest goes out as **ordinary boluses every 15 minutes**
(`SplitBolusPlan.partEvery`), in whole pulses, through the same verified
`BolusDelivery` path every other bolus takes, with the same ceilings.

## Where things live

| Piece | File |
|---|---|
| Plan + parts, low guard | `lib/src/pump/split_bolus.dart` |
| Stored in the pod store (`pod.split_bolus`, cleared on `forgetPod`) | `lib/src/pump/pod_split_bolus.dart` |
| Controls + how a dose divides | `lib/src/injection/injection_split_bolus.dart`, `split_bolus_choice.dart` |
| Gives the parts | `lib/src/cgm/service/split_bolus_runner.dart` |
| Overview card with "Abbrechen" | `lib/src/overview/split_bolus_card.dart` |

## Load-bearing rules (each one was a bug first)

- **Parts run inside the pod chain** (`CgmTaskHandler._tickPodChain`, between
  the watch and the automation). They hold the service's lease owner, which the
  poll and the loop share on purpose, so beside the chain a part could open a
  second session on the pod.
- **A part is marked as sending before it goes out.** A fresh process finding
  the mark never sends that part again: it may have gone in. The mark is
  compared in milliseconds (`markedAt`), because the stored copy keeps no
  microseconds and `DateTime.now()` has them. Comparing with `==` never
  matched and silently dropped parts.
- **After the send the plan is settled against the store as it is now.** A
  cancel, or a new plan started meanwhile, is left alone; a dose that went in
  is logged either way.
- **The app does not resolve the service's in-flight part as stranded**
  (`BolusDispatcher.resolveStranded`): while the plan carries the send mark, the
  pending bolus record is the service's own.
- **"Not now" is retried, everything else ends the plan and says so.** The pod
  bolusing, a micro bolus queue that is too long, or the link held by the app
  (`pump.bolus.link_busy`) wait for the next tick. A refusal, an unknown
  outcome, no pod, or a part more than 15 min overdue drop the rest with a
  notification. A failed first part (the "now" share) drops the rest too.
- **Low guard.** No part goes out when glucose is at the user's low line or its
  trend reaches it within 30 min (`SplitBolusLowGuard`); the rest is dropped
  with a notification. The loop lowers basal on a low, but these are boluses.
  Without usable sensor data the part still goes, as a pump's extended bolus
  would.
- **The plan check per tick is one key read** (`containsKey`); opening the pod
  store decrypts the whole keystore.

## Insulin on board and carb cover

- The rest still planned counts as insulin on board **in full**
  (`InsulinOnBoardParts.planned`), for the calculator, the high-alarm correction
  and the loop. Parts past their lateness window stop counting, so a plan no
  service worked off cannot hold back corrections for good. The active-insulin
  page shows it as "noch geplant", not as delivered (`pumpGiven`).
- Each part is logged as its own carb-free, pump-delivered meal entry at the
  time it went in, so its insulin decays from the right moment. Booking it onto
  the meal would date it back and understate insulin on board.
- Each part carries **`split_of`** (the meal's `logKey`), and the plan its
  `mealKey`. The loop's carb cover caps a meal at the insulin dosed for it;
  `CarbsOnBoard.coverUnits` counts the meal's parts and the rest still planned
  for it. Without that, a split read as correction insulin and the loop withheld
  basal while the carbs came in.
- The API stores `split_of` and `delivered_by_pump` and hands them back only
  when set (insulink-api#116). The app merges a pull by JSON content, so a field
  the API drops doubles the meal and its insulin.
- A part logs the glucose read for it, or 0 without a reading: the forecast
  model folds a dose's glucose into its glucose channel, so the meal's own value
  an hour later would be a false reading.

## Known limits

- Moving a meal's time afterwards breaks the link; its parts then read as
  correction again (the loop gives less, never more).
- The per-hour limit is the max bolus. Another bolus during a split can reach
  it, which refuses the next part and ends the plan with a notification.
- A part is written to the meal log by the service; a meal saved in the app at
  the same moment from a stale list can overwrite it (the pre-warning's
  countermeasures share this).
