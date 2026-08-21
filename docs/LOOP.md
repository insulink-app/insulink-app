# Automated delivery

The pod delivering basal insulin on its own, from sensor readings, with no tap
per dose. `lib/src/pump/loop/`.

> This is an interoperability/research project and **not a medical device**.
> Nothing here is a claim that letting software dose insulin is safe. Read
> `docs/OMNIPOD.md` first; the hazard analysis there applies to everything below.

## The one structural decision

**The automation only ever sets a temporary basal rate. It never gives a bolus.**

Everything else follows from that, and it is the reason the feature can bound its
own worst case at all:

- **A temporary rate can be taken back.** Five minutes of a wrong rate is a
  fraction of a unit, and the next cycle undoes it. A bolus is in the body the
  moment it is given and no later decision retrieves it.
- **A temporary rate expires by itself.** Every cycle programs a rate lasting
  `LoopLimits.fuse` (30 minutes, the shortest the pod accepts). If the loop stops
  for any reason at all, that rate runs out and **the pod returns to the user's
  stored basal schedule with no app involved.**

That last point is what meets "fall back to basal when the pump cannot be
reached". It is not code that has to still be running in order to run; it is the
pod's own timer. An app that has been killed, a phone that is off, a Bluetooth
stack that has wedged: all of them end the same way, with the pod back on the
user's schedule within half an hour.

The user's basal schedule stays on the pod untouched the whole time. It is not
what runs while the loop is engaged, because every cycle overrides it, but it is
what the pod falls back TO. It is the net, not a second thing to keep in step.

### Renewing a rate does not stack it

The obvious worry: twelve cycles an hour, each programming thirty minutes of
insulin, is twelve half-hours of insulin in one hour. It is not, on either level.

**The pod** holds one temporary rate at a time. Programming a new one replaces
it, and each cycle cancels a running one first anyway (mirroring the reference
driver), so the pod is never asked to hold two. It delivers whatever rate is
current, and nothing else. A rate is a speed, not a quantity: programming
3 U/h for thirty minutes does not hand the pod 1.5 U to get through, it tells it
how fast to run until told otherwise.

**The ledger** bills each rate for the stretch it actually ran, which is the five
minutes until the next cycle replaced it, not the thirty it was programmed with.
That is why the accounting window is closed BEFORE the rate is replaced, and why
a cycle stores its rate rather than a unit count.

At a steady 3 U/h the numbers are: 3.00 U actually delivered in the hour;
18.00 U if the programs stacked; 1.50 U the most the last rate can still deliver
after the loop stops. `loop_runner_test.dart` runs thirteen cycles and checks
that what the ledger books equals the integral of the rates that ran.

The thirty minutes is not a dose. It is how long the pod keeps going if nobody
tells it anything else, and the only insulin it can ever add on its own is the
tail of the last rate, bounded by the hypo headroom that rate was granted.

## Two positions, and OFF is not idle

`PodLoopMode`, in `loop/loop_journal.dart`:

| Mode | Decides | Programs | Radio |
|------|---------|----------|-------|
| `off` | every cycle, written to the journal | **no** | **none** |
| `engaged` | every cycle | yes | one session per cycle |

An earlier version had a third "observing" setting between them. It turned out to
be what OFF should always have meant: the question anyone asks about an
automation they have not switched on is what it WOULD have done, and answering it
costs nothing. So the way to check the automation against a real day is simply to
leave it off and read the journal.

**Deciding while off uses no radio at all.** It reasons from the status the
background watch already read (`PodStatusCache`), not from a session opened to
ask again — a hypothetical is not worth waking the pod for. A cached status older
than 30 minutes produces no entry rather than a decision describing a pod nobody
has looked at.

Engaging asks twice: a warning that has to be read, then the device biometric.
Turning it off is one tap, because only one direction of this switch can hurt
anyone, and a check in front of the direction that STOPS insulin is a check that
can fail closed.

## One cycle

`PodLoopRunner.tick()`, every five minutes, from the CGM foreground service, so
it runs with the app closed. It shares that service rather than getting its own,
for the same reason the pod watch does: a second thing scanning wedges Android's
BLE scanner. The loop **never scans** and connects only to the address it knows.

1. **Mode and pacing.** Off, or a cycle already run inside the interval, stops here.
2. **Pod and limits.** No activated pod, or limits that contradict each other,
   stops the automation rather than guessing.
3. **Read the sensor** into a `LoopGlucose`. This is a trust boundary; see below.
4. **Open a session, read the pod's status.**
5. **Close the accounting window** (`PodBasalBooking`) BEFORE the rate is replaced.
   The store holds one temporary rate at a time, so a window still open when the
   rate is replaced would be billed at the new rate. This is what keeps the
   automated log honest.
6. **Decide**: `LoopAlgorithm` asks, `LoopSafety` permits.
7. **Apply**: program it, or revert the pod to its schedule, or stand aside.
8. **Record** the cycle in the journal, whatever happened.

The pod's link is exclusive, so the loop tick is CHAINED after the pod watch tick
rather than run beside it.

## The trust boundary

`LoopGlucose` is the only way sensor data reaches the arithmetic, and an instance
only exists when the data passed all of:

| Check | Refused when |
|-------|--------------|
| freshness | the newest reading is over 12 minutes old |
| clock | the reading is stamped more than 2 minutes ahead of the phone |
| plausibility | outside 30 to 500 mg/dL |
| history | fewer than 3 points in the 20-minute window |
| trend plausibility | over 8 mg/dL per minute, which is 40 mg/dL in five minutes |

The trend is **measured here**, not taken from the sensor's trend field: the G7
and the Libre encode that differently, and a trend computed from the same points
as the value cannot disagree with the value.

It uses **Theil-Sen** (the median of every pairwise slope), not least squares.
Least squares was tried and is not good enough: it gives an outlier the most
leverage exactly where a sensor most often produces one, at the edge of the
window. One point 40 mg/dL out of line bends a real -1.0 mg/dL/min into -2.6,
close to the -3.0 that reading only the two endpoints would give. The pairwise
median returns -1.0 on that same data. The number drives the hypo prediction, so
this matters.

## Algorithm and safety are separate files, on purpose

`LoopAlgorithm` produces what the maths alone would ask for. It knows nothing
about the pod, the reservoir, or any ceiling. `LoopSafety` is the only thing that
turns a wanted rate into a rate that gets programmed. Splitting them means a
change to the dosing model cannot remove a guard by accident.

The model is linear and has exactly one glucose-lowering constant, the correction
factor the user already tunes for the bolus calculator, so there is no second set
of numbers to get wrong:

```
eventual = glucose + trend × 30 min − iob × correctionFactor
wanted   = scheduledRate + (eventual − target) / correctionFactor / 0.5 h
```

The trend and the insulin-on-board term overlap, because a falling trend is
partly that same insulin already working. Subtracting both counts some of it
twice and predicts a lower glucose than is likely. **That bias is deliberate.**
Every uncertainty in the arithmetic resolves towards asking for less.

### Refuse versus clamp

The rest of the pump code refuses rather than trimming: delivering less than a
person asked for is its own dosing error (`docs/OMNIPOD.md`). `LoopSafety`
inverts that, and the reason is that **nobody asked for this rate**. Trimming an
automated suggestion is exactly right, and refusing outright would leave a high
glucose untreated. Every limit is applied as a minimum, so a limit that fails to
bind still leaves all the others in the way.

Suspending is free and delivering is not, so a zero rate is reachable from every
branch and every uncertainty resolves towards it.

## The layers

| Layer | What it does | Where |
|-------|--------------|-------|
| mechanism | temp basal only, never a bolus; every rate expires in 30 min | `loop_runner.dart`, `loop_pod_commands.dart` |
| input | stale, implausible or too-sparse sensor data never reaches the maths | `loop_glucose.dart` |
| hard floor | at or under the suspend threshold, rate 0. No arithmetic, no exceptions | `LoopSafety._suspensionFor` |
| predicted floor | trend reaching under the threshold within the fuse, rate 0 | `LoopSafety._suspensionFor` |
| hypo headroom | the added insulin cannot close the gap to the threshold | `LoopSafety._hypoHeadroom` |
| insulin on board | includes the loop's OWN excess, not only the user's boluses | `PodLoopJournal.loopIobUnits` |
| rate ceiling | configured U/h, never above the pod's own 30 U/h | `LoopSafety._ceilings` |
| hourly ceiling | rolling one-hour total of automated excess | `LoopSafety._ceilings` |
| reservoir | a full fuse at this rate has to fit in what is left | `LoopSafety._ceilings` |
| pod state | not alarming, running, not mid-bolus | `LoopSafety._podCanDeliver` |
| grid | snapped DOWN to 0.05 U/h, so snapping cannot lift a clamped rate | `LoopSafety.snapToPodGrid` |
| stand-down | pod out of reach past the fuse, pod finished, no pod, bad limits | `loop_runner.dart` |
| audit | every cycle recorded with its inputs, delivered or not | `loop_journal.dart` |

### The hypo headroom, which is the central one

The worst thing a single decision can do is have its rate run unattended for the
whole fuse, which is exactly what happens if the phone dies right after
programming. So the allowance is computed over the fuse, not over the cycle:

```
reference = min(glucose now, glucose + trend × fuse)
affordable = (reference − suspendThreshold) / correctionFactor
maxExtra   = affordable − insulinOnBoard
rate      ≤ scheduledRate + maxExtra / 0.5 h
```

which rearranges to the property the feature is built to hold:

```
reference − (iob + extra) × correctionFactor  ≥  suspendThreshold
```

Scheduled basal is excluded from that budget on purpose. It is the user's own
maintenance rate offsetting the glucose their liver releases; it runs whether the
loop does or not, and charging it against the hypo allowance would have the
automation withhold background insulin and let the user run high for the sake of
a hypo the schedule alone does not cause.

`test/pump/loop_hypo_bound_test.dart` checks the property by sweep rather than by
example: five correction factors × three thresholds × the glucose range × seven
trends × five insulin-on-board levels × four schedules, asserting the inequality
on every decision that delivered anything. It also asserts that enough of them
DID deliver, so a loop that never dosed could not pass it vacuously.

### Insulin on board has three parts

The number the hypo headroom is computed from decides how much insulin the loop
may add, so anything missing from it becomes insulin the loop is willing to
stack on top of.

**The user's own boluses**, which reach the loop as logged meals, exactly as the
overview's active-insulin readout sees them.

**The automation's own excess above the schedule.** Without it every cycle would
see only the meals and correct on top of corrections it had already given, which
is how an automated system stacks a dose nobody chose.

A cycle stores its RATE above schedule, not the units it committed to. What it
actually delivered is that rate times how long it ran before the next cycle
replaced it, which is only known once the next cycle exists; a stored unit count
would have to claim the full fuse and would overstate every cycle roughly
sixfold. Billing is capped at the fuse, so a cycle nothing replaced stops
counting at the point the pod stopped honouring it.

Only positive excess counts. A rate below schedule withholds background insulin,
which is not negative insulin in the body, and counting it as such would enlarge
the next cycle's allowance on the strength of a dose nobody gave.

**Boluses whose outcome nobody could confirm.** A bolus the pod never answered
for is deliberately recorded in neither the meal log nor the pod's delivery log
(`docs/OMNIPOD.md`): understating insulin for the USER is recoverable, because
they can look at the pod and log it, while overstating it would suppress a
correction they need.

The automation needs the opposite assumption and cannot ask anyone, so
`PodStore.unconfirmedBoluses` keeps the possibility and the loop counts it as
delivered. **The two readers disagreeing is the design**, not an inconsistency:
each assumes whatever is conservative for what it does next.

## Standing down

| Cause | What happens |
|-------|--------------|
| pod unreachable past the fuse | mode to `off`, `PodLoopStop.podUnreachable` |
| pod alarming or no longer running | mode to `off`, `podNotDelivering` |
| no activated pod | mode to `off`, `noPod` |
| limits contradict each other | mode to `off`, `limitsInvalid` |
| sensor data unusable | **mode stays on.** The pod is reverted to its schedule and the loop waits for the next reading |
| clock moved backwards | **mode stays on.** Same treatment, see below |

The last row is the distinction that matters: losing the sensor is ordinary and
short, and losing the pod is not. A sensor gap must not cost the user their
automation, and a pod that cannot be reached must.

Unreachability is measured from **when the pod was last actually seen**, not from
a count of failed attempts, so a phone that slept through several missed cycles
reaches the same conclusion as one that tried and failed every five minutes.

Every self-stop raises a notification (`PodAlarmManager.loopStopped`), once, on
the warning channel. An automated system that stops without saying so is worse
than one that was never started, because the user goes on believing their
delivery is being managed. It is a warning and not an alarm: nothing dangerous
has happened, the pod has gone back to the schedule the user programmed. The
notification reuses the strings the pump page shows for the same cause, so the
two cannot come to say different things. Switching off by hand raises nothing,
because the person who did it is holding the phone.

Switching off by hand writes the mode FIRST and only then reaches for the pod, so
a cancel that fails still leaves an app that has stopped automating. The pod is
not left running the last rate either way; reaching it now only makes the
schedule resume sooner.

### A clock that moved backwards

Daylight saving ending, a manual change, a network time correction, or flying
west all leave the recent journal entries dated in the future. Every window from
a cycle to now then measures negative, the automation's own insulin bills as
nothing, and the insulin-on-board it decides from is understated by whatever it
has just given.

That is the one direction of accounting error that lets the next cycle add MORE,
so it is treated as a reason to decide nothing rather than something to correct
for. The pod goes back to the user's schedule and the loop waits. It costs at
most the hour or the timezone that was skipped.

### A pod that refuses

The pod answers a command it will not run with a NAK, which arrives as an
ordinary response and not an exception. `LoopPodCommands` turns one into
`LoopCommandRefused` rather than letting the automation record a refusal as
delivered.

The direction that looks harmless is the one that matters. A refused rate ABOVE
the schedule only leaves the store overstating insulin, which makes the next
cycle ask for less. **A refused SUSPENSION would leave the app believing delivery
had stopped while the pod carried on down its schedule**, which is the one belief
this feature may not hold wrongly.

A refusal rolls the stored stretch back, because the pod is still on whatever it
was running. An outcome that is merely UNKNOWN is left standing instead: the pod
may well be running it, and that is the reading to keep. The cycle is written to
the journal either way, because a journal holding only the cycles that worked
cannot explain a stretch where none did.

## Where the state is visible

| Where | What |
|-------|------|
| overview, under the pod box | the mode, and the rate if one is running. Also shows an automation that stopped ITSELF, which is the state a user is most likely to be wrong about |
| pump page | the three-way switch, why it stopped, the last decision |
| automation journal | every cycle with the glucose, trend, insulin on board and schedule it was computed from |
| delivery log | the insulin itself, per hour of basal, which includes what the automation delivered |
| notification | each self-stop, once |

## A rate the user set is an instruction

If the user sets a temporary basal by hand, say before going running, the
automation leaves it alone until it expires. Replacing it five minutes later
would undo a decision they made, without ever saying so.

The exception is a suspension, and it has to be: standing aside there would mean
watching glucose fall through the threshold because of a rate set an hour ago for
a run that has finished. **Intent wins over the automation; it does not win over
hypoglycaemia.** `PodTemporaryBasal.automated` is what tells the two apart, and it
defaults to false so a rate stored before that field existed reads as the user's.

## Settings

Three numbers are the automation's own; everything else it needs is already tuned
elsewhere (correction factor and insulin duration on the bolus profile, target on
the glucose profile).

| Setting | Default | Range |
|---------|---------|-------|
| stop delivery below | 85 mg/dL | 70 to 100 |
| highest basal rate | 3 U/h | 1 to 10 |
| highest active insulin | 5 U | 1 to 15 |

Whole units, because these are ceilings and not doses. They sync to the account
like every other setting; **the mode does not**, because a pod belongs to the
device that activated it, so which device is automating is not an account-wide
fact.

## What is deliberately not here

- **No automated bolus, and no SMB.** See the top of this file. This costs
  post-meal responsiveness, which is the intended trade.
- **No carbohydrate entry into the loop.** A meal is announced by dosing a bolus,
  which the loop sees as insulin on board. Meal announcement would be the next
  thing to add and needs its own decisions about how far ahead to look.
- **No exponential insulin curve.** Linear, matching `ActiveInsulin`, so the two
  cannot disagree. Upgrade path if it proves too coarse: one curve shared by
  both, never two.
- **No autotune of basal, correction factor or carb ratio.** Those are the user's
  numbers.

## Tests

| File | What it pins |
|------|--------------|
| `loop_glucose_test.dart` | every rejection path; the trend, including the outlier case that ruled out least squares |
| `loop_safety_test.dart` | each ceiling binds and says so; suspension outranks everything; grid snapping rounds down |
| `loop_hypo_bound_test.dart` | the hypo property by sweep; nothing delivered under the threshold; a stuck-high sensor cannot stack insulin |
| `loop_journal_test.dart` | billing a cycle for the time it ran, the fuse cap, the loop's own insulin on board |
| `loop_runner_test.dart` | mode behaviour, cancel-before-program, booking before replacing, standing down and announcing it, deferring to a user rate, re-reading the mode before acting |
| `loop_switch_test.dart` | what blocks engaging, and that switching off leaves the automation off even when the pod cannot be reached |
| `loop_locale_keys_test.dart` | every key built from an enum at runtime exists in both languages |
