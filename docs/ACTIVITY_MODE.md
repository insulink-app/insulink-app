# Activity mode

How exercise changes what the automation doses. `lib/src/activity_mode/`.

> Not a medical device. The mode moves two inputs of the loop's arithmetic and
> nothing else. Read `docs/LOOP.md` first: every limit there still applies.

## The three modes

| Mode | Target | Basal anchor | Why |
|---|---|---|---|
| Normal | the user's own | 100 % | no exercise |
| Endurance | 150 mg/dL (raises only) | 50 % | muscle takes up glucose without insulin, glucose falls |
| Strength | the user's own | 120 % | stress hormones push glucose up during the set |
| Recovery | 130 mg/dL (raises only) | 80 % | after endurance, muscle refills glycogen and stays insulin sensitive for hours |

All three numbers are settings (`ActivityModeSettings`, profile → Sportmodus)
and ride the account blob. So does the switch that turns the whole feature off
(`activity_mode_enabled`, on by default): switched off, `ActivityModeStore.current`
always answers normal, whatever was chosen, recorded or detected. The **live**
mode does not ride the blob, like `pod.loop_mode`.

## What it changes, and what it cannot

`PodLoopRunner._decide` asks `ActivityModeAdjustment` for two things:

- `limits(base)`: the target the arithmetic corrects towards. The endurance
  target only ever **raises** the user's own. A user whose everyday target is
  already 160 is never dosed harder for going on a walk.
- `anchor(schedule)`: the scheduled rate `LoopAlgorithm` builds the wanted rate
  on, scaled by the mode's percentage.

`LoopSafety` is still handed the **real** schedule. So:

- basal that strength adds above the schedule counts as excess, as a dose,
  exactly like a correction: it lands in insulin on board, the hourly ceiling
  and the hypo headroom;
- the suspend threshold, the rate ceiling and every other limit are untouched;
- a rate below the schedule in endurance is logged as `easingOff`.

With the automation **off**, the mode changes only what the journal says the
loop would have done. It never programs a temporary rate on its own. A manual
temporary rate (pump page) still works and still wins over the loop.

Each journal cycle records the mode (`PodLoopCycle.activity`, omitted when
normal), and the pump page's last-cycle line names it.

## Where the mode comes from

`ActivityModeStore.current(now)`, read from storage so the service isolate and
the UI agree without a message:

1. **Manual choice** (Normal, Ausdauer, Kraft on the selector) wins, for
   2 hours (`manualFor`). No choice may hold forever: a forgotten strength mode
   keeps adding basal. "Auto" deletes it.
2. **A routine workout runs** (`sport.active_workout`) → strength. A snapshot
   older than 4 hours counts as abandoned.
3. **A cardio recording runs** (`sport.active_training`) → endurance.
4. **The training detection sees an ongoing training** → endurance.
5. **The band's pulse held at or above the activity threshold** (110 bpm, a
   setting) for 10 minutes → endurance (`ActivityPulseDetector`, service
   isolate). Catches what GPS cannot: a gym, housework, a dance floor. A dip
   just under the line does not restart the clock, one 10 bpm below does.
   Each sample above renews the sighting, which counts for `detectedFor`.
6. **An endurance bout of at least 20 minutes ended less than 6 hours ago**
   (a setting, 0 switches it off) → recovery (`ActivityBout`). Every endurance
   reading, whatever its source, is booked into a bout; readings under 15
   minutes apart belong to the same one. The recovery runs from the end of the
   latest bout that **reached** 20 minutes, not from the latest bout: it used
   to follow only the last one, so a 9-minute walk at 18:44 wiped out the
   recovery of a 53-minute walk that afternoon, and dinner was dosed as on a
   quiet day. Not offered as a manual choice (the toggle stays at four
   segments); Normal by hand ends it early.
7. Otherwise normal.

### "Ongoing" from the training detection

`CardioDetectionRunner.selectDetections` already held back segments whose last
moving point is less than 5 minutes old, so a ride is recorded whole once it
ends. Such a held-back segment is the ongoing training: it already passed the
detector (≥ 8 min, ≥ 500 m, human powered, not a vehicle). The runner reports
it as `ongoing`; the service writes the sighting time
(`activity_mode_detected_at`) on every detection run (every 2 min).

A sighting counts for 10 minutes (`detectedFor`). That bridges two runs and
ends the mode by itself when detection stops running: battery saver, a dead
service. So endurance starts about **8 minutes into** a walk or ride, and ends
5 to 7 minutes after the last movement.

## The smaller meal bolus in the recovery

The recovery's lower basal has almost nothing to take away in the evening and
at night, where a schedule is often close to zero. The insulin behind the lows
after an active day is the dinner bolus, and the loop cannot take that back.
So the bolus calculator (`InjectionPage`) cuts its suggestion by a percentage
(`RecoveryBolus`, setting `activity_recovery_bolus_percent`):

- **Off by default (0 %).** It changes a dose the user gives by hand, so it is
  never switched on for them.
- **Only after a long bout**: at least 30 minutes (setting
  `activity_recovery_bolus_minutes`, 20 to 120), against the 20 of the loop's
  recovery. A ride to work or a walk to the shop leaves the next meal alone. A
  bout is continuous endurance with gaps under 15 minutes; detection starts
  about 8 minutes in and ends 5 to 7 after, so the measured length is close to
  the real one. Several short walks do not add up to a long one.
- **For the recovery hours** after that bout ends (`activity_recovery_hours`).
- **Said on the sheet**: a line under the bolus field names the cut, and the
  field stays editable.
- The whole suggestion is cut, meal and correction alike. The high alarm's
  correction button is not: it is a correction alone, and the loop's own
  recovery already holds back there.

## The settings page

The numbers sit under four headings, by when they apply (`ActivityModeSection.groups`):
**Ausdauer** (target, basal, the pulse that counts as endurance), **Kraftsport**
(basal), **Erholung nach Ausdauer** (duration, target, basal) and **Bolusrechner
in der Erholung** (bout length, reduction). Each heading carries its explanation
behind an ⓘ, and the labels under it are short ("Zielwert", "Basal") because the
heading already names the mode. A test keeps every setting in exactly one group.

## The selector

`ActivityModeSelector`: Auto / Normal / Ausdauer / Kraft, with one line under it
saying which mode is in force and why. Only in the profile's activity section
(`ActivityModeSection`), under the switch and only while it is on: a mode that
changes how insulin is dosed is a setting to reach for, not a control on the
overview or the pump page to brush past. The pump page's last-cycle line still
names the mode a cycle ran under. A second switch there, "show the choice on the
overview" (`activity_mode_on_overview`, off by default), puts the same selector
back under the automation row on the overview for someone who switches modes
often (`ActivityModeOverviewSelector`). Both switches live in
`ActivityModeSwitchState`, a provider above the page tree: the overview is not
rebuilt when the user comes back from the profile, so it has to be told. The selector re-reads storage every 30 s,
since the detection runs in the other isolate.

## Not built

- Recovery after strength: lifting tends to raise glucose, the evidence for
  late lows after it is weaker. Add it when the journal shows them.
- A higher suspend threshold during endurance: the falling trend already
  suspends through `suspendedFalling`.
- Setting a temporary rate when the automation is off.
