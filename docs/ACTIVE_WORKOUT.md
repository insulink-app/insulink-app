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

## Workouts without a routine, and exercises added mid-session

The snapshot carrying the routine by value is what makes both of these work at
all — a follower renders the driver's items, so it needs no copy of its own.

- **A free workout** carries the routine id `free` (app `freeRoutineId`, panel
  `FREE_ROUTINE_ID`) and no stored routine behind it. It starts with **no items**
  and both clients must survive that: nothing may index item 0 before the first
  exercise is picked, and the id is never resolved against the routine list —
  the places that name a workout show the free-training label instead. It also
  **never ends itself**: running out of planned sets rests on the same set rather
  than finishing, because there would otherwise be no way to add the next
  exercise. Only the user's "finish" ends it.
- **A free workout runs one set at a time.** A picked exercise gets exactly one
  set and a two-minute rest; that rest is where both clients ask which exercise
  comes next, and picking one starts it straight away. "Waiting for the next
  exercise" is DERIVED from the snapshot (a free workout resting with at least as
  many sets logged as planned), never carried — so a follower shows the same
  question without another field to keep in step.
- **An exercise added while a workout runs** is appended to the *runner's own*
  copy of the routine, never to the stored one — a spontaneous extra must not
  rewrite the plan for the next run. It reaches every other screen through the
  snapshot's `items` like any other change. The panel keeps the ones it added in
  a small local list and drops each as soon as the account's copy carries it, so
  a round trip cannot add the same item twice.
- **The predicted end is derived, not carried.** Both clients compute it from the
  same rule — this session's elapsed time per logged set, extrapolated over the
  sets still planned, with the routine's planned length standing in before the
  first set — so it stays out of the snapshot: it would change every second and
  each side already holds everything it needs. A free workout has no plan and
  therefore no prediction.

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
5. **The logbook is keyed by client id.** The id IS the session's start, so the
   same workout finished on two devices is ONE entry: `sync` keeps the last per
   id, and the app's `addSession` REPLACES an id it already holds instead of
   appending beside it. Two local rows sharing an id look like two workouts and
   are deleted as one — the logbook deletes by id.
6. **The account's confirmation is persisted, not just held in memory.** It is
   the only thing that lets "the account holds no workout" end a session
   (rule 4), so a device that forgets it on restart can never end one again: the
   app relaunches, the account answers "nothing runs", and without the
   confirmation that reads as "it has never heard of this one". A workout
   finished in the panel then ran on in the app for hours and was logged a second
   time when finished there too. `SportSync.restoreStamp()` reads it back before
   anything touches the running workout.
7. **A workout whose session is already logged is over, whatever the account
   says.** The `clear` can be lost — the panel navigates away regardless, and its
   retries can all fail — leaving a row nothing will ever remove. Both clients
   therefore refuse to resume a workout whose start is already in the logbook,
   and the app clears it on the account as well. This is the backstop behind
   rules 4 and 6, not a replacement for them: it only fires once the finished
   session has synced.
8. **One owner per device.** In the app that is
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
