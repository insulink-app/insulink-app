# The running workout across devices

One workout, one row (`sport_active_workouts`, one per user), any number of
screens on it: the app's runner page, the web panel's runner. Whoever the user
touches moves it on; everyone else follows. This file is the contract the three
modules keep — app (`sport/workout/`, `sport/training_state.dart`), api
(`ActiveWorkoutController`), panel (`routine-runner/use-workout-sync.ts`).

## The shape

- The row holds the app's `WorkoutSnapshot` JSON verbatim. The api never reads
  into it; the clients agree on it (the panel's `ActiveWorkout` type mirrors it).
- The snapshot carries the driver's own copy of the routine items, so a follower
  renders the exercise/set/target the driver is on rather than indexing its own,
  possibly different, copy.
- Every time is an absolute epoch, so elapsed/rest recompute correctly whatever
  happened in between — including `pausedAt`, the moment the workout was paused
  (null while it runs). Both clients read it as their "now", so a pause freezes
  both screens at the same instant. It carries `pausedTotal` as well: that is
  what the resuming device adds to, and what keeps the elapsed time honest.
- `updated` is the server's own stamp on the row. It is the only ordering there
  is; the devices' clocks are never compared.

## The rules

1. **Having the runner open does not make a device the driver.** It adopts every
   snapshot the account gained since it last wrote or read one (`updated` higher
   than the one it knows) and rebuilds its runner from it. Ignoring them is how
   a phone sat showing "+24 min rest" while the panel was three sets further on.
   The open runner decides by comparing the shared state's snapshot with the one
   it published, by IDENTITY — anything else came from another device. Not by
   counting adoptions: such a signal is consumed whether or not it was applied,
   and one dropped tick is a screen that never catches up again.
2. **A device only publishes what the user did on it.** Resuming, adopting or
   merely opening a workout pushes nothing — the snapshot came from the account
   in the first place.
3. **Every push carries the `updated` it last saw**, `0` meaning "I am starting a
   fresh workout". The api refuses a non-zero stamp when the row is gone: that
   push is carrying on a workout somebody has already finished. **A stamp belongs
   to one workout** (`SportSync.stampFor`, keyed on the snapshot's start) — sent
   for a different one it claims to continue a workout this device never saw, and
   the refusal that follows is silent and lasts the whole session: the phone
   works out alone and nothing reaches the panel. Without this
   fence a push still in flight when the workout ends writes the row back, and
   the resulting zombie is offered for resume on every device and logged a second
   time under the same id (the client id is the session start, so both rows look
   identical). `clear` resets the stamp to `0` on the device that sent it.
4. **A failed poll is not an ended workout, and neither is one the account never
   knew.** The app answers "the account could not be asked" separately from "no
   workout runs". Even the latter only ends the session when the account had
   confirmed THIS workout first — its start matches
   `SportSync.confirmedActiveWorkoutStart`, set by a push it accepted or a poll
   that answered with it. A workout started on this device goes up only after the
   debounce, and the runner polls the moment it opens: that poll legitimately
   answers "nothing runs". Treating it as an ending wipes the workout from the
   shared state the second it begins, and then nothing syncs for the rest of the
   session — the failure looked exactly like "starting on the phone breaks
   sync entirely". Ending is also the one write the panel retries rather than
   drops: it navigates away regardless, and a lost `clear` leaves the workout
   running on every other device.
5. **The logbook is keyed by client id.** `sync` keeps the last entry per id, so
   a list that carries one twice cannot become two rows.
6. **One owner per device.** In the app that is
   `TrainingState.watchActiveWorkout` — nothing else may fetch the workout.
   `SportSync.pull` (sign-in, cold start, every entry to the sport tab) used to
   fetch it too, and only into the store, which `TrainingState.reload`
   deliberately never re-reads: the snapshot sat in storage where no screen
   looked at it, and the stamp it consumed made the watcher treat the account as
   unchanged. The phone stayed one launch behind the panel and opened the runner
   only on the second start. A second reader is not a redundant read here, it is
   a silent one.

## Cadence

Snapshots are debounced 400 ms on both clients and keyed on the snapshot's
CONTENT, never on the objects around it — the panel's per-render/per-poll object
identity used to re-arm the mirror every few seconds, which is what kept a push
permanently in flight and made rule 3 necessary in practice.

Followers poll every 5 s, and **every 2 s while a runner is open on either side**
(`TrainingState._watchEveryWithRunner`, the panel's `refetchInterval`) — that is
when someone is working out on one screen and watching the other, and a set
arriving five seconds late reads as no sync at all. The app polls only while it
is in the foreground; `driveActiveWorkout` re-arms the timer when the runner
opens or closes. Worst case end to end: ~2.4 s.
