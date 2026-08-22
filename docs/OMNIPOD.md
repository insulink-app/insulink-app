# Omnipod DASH

Status of the DASH pump support, the byte-level protocol notes, and — most of
this file — the hazard analysis. Read the hazards section before touching
anything under `lib/src/pump/protocol/`.

> This is an interoperability/research project and **not a medical device**. The
> code here can command an insulin pump. Nothing in this document is a claim
> that doing so is safe.

## Status

The **driver is complete and verified offline**, up to but not including a live
pod. Every byte-level encoder and decoder is pinned by captured vectors, and the
pairing, session and activation SEQUENCES are exercised against a scripted pod
that computes its own side of the handshake. None of it has touched real
hardware yet.

There is deliberately **no global "allow delivery" switch**. One existed and was
removed: a toggle everyone has to turn on before the feature works protects
nothing — it only trains the user to click past warnings, and it is off precisely
when the pod most needs commanding. What actually constrains a delivery is
[`PodDeliveryGuard`](../lib/src/pump/protocol/pod_delivery_guard.dart), which
judges the DOSE against the pod's own freshly-read state, plus the biometric in
front of the cannula and the read-back that has to name the bolus before a unit
is recorded. Those hold on every path, every time, and none of them can be
switched off.

| Layer | State | Verified by |
|-------|-------|-------------|
| CRC-16 / CRC-32 / additive checksum | done | captured command trailers, IEEE reference |
| `MessagePacket` header + parse | done | captured encrypted frame, byte-exact both ways |
| BLE fragmentation / reassembly | done | round-trip every length 1–250, drop + corruption |
| Keyed payload envelope (`SP1=`, `S0.0=`) | done | round-trip + malformed input |
| X25519 (Rust) | done | RFC 7748 vector, low-order-point rejection |
| LTK pairing ladder (CMAC) | done | captured pairing; plus an independently computed pod side agreeing on the key |
| Milenage (EAP-AKA core) | done | 4 captured sessions incl. resynchronisation |
| EAP-AKA message + attributes | done | captured challenge, byte-exact round trip |
| AES-CCM session cipher | done | captured encrypt + decrypt, tamper rejection |
| Commands: status, version, set-id, deactivate, silence, stop, bolus | done | captured frames, byte-exact |
| Commands: alerts (4 configurations) | done | captured frames, byte-exact |
| Commands: basal (3 schedules), temp basal (4 rates) | done | captured frames, byte-exact |
| Responses: status, version, set-id, NAK + dispatch | done | 5 captured pod statuses, NAK, envelope validation |
| Message I/O (request-to-send / fragments / success) | done | scripted pod, incl. multi-fragment and silence |
| Pairing flow | done | scripted pod computing its own LTK |
| Session establishment flow | done | scripted pod computing its own challenge response |
| Encrypted command session + acknowledgement | done | real captured encrypted reply, decoded end to end |
| Activation sequence (two phases, resumable) | done | scripted pod; incl. resume not re-delivering insulin |
| Delivery guard (limits, staleness, reservoir) | done | unit tests |
| Pod state persistence | done | unit tests over an in-memory keystore |
| Backend mirror + restore (`/pump/register/`, `/pump/update/`, `/pump/current/`) | done | API controller tests; app side reviewed |
| Bolus delivery from the injection sheet | done | unit tests over a scripted pod |
| Alarm status page (0x02) + alarm classification | done | captured page, byte-exact; all 256 codes classified |
| Basal profile → pod schedule adapter | done | unit tests, incl. every rate the editor can produce |
| Activation wizard (two phases, resumable) | done | stage/resume unit tests; flow untested on hardware |
| Cannula insertion behind the device biometric | done | unit tests over a scripted pod |
| Pod life + reservoir on the overview | done | lifespan unit tests |
| Panel pod history (`/devices/pump`) | done | `src/lib/pump.check.ts` |
| Background pod watch + alarms | done | alarm-decision and tick-policy unit tests |
| Basal delivery into the forecasting model | done | app ledger tests + 12 predictor tests |
| Temp basal: command, sheet, and ledger accounting | done | rate-window and sheet-path unit tests |
| BLE link + scanner | written | **unverified — needs hardware** |
| Pump page: status, stop, deactivate, acknowledge alerts | done | builds and analyses; not exercised on a device |

Tests: `flutter test test/pump/` (326) and `cd rust && cargo test` (9). The
pairing and flow tests load the host Rust library, so `cargo build` has to have
run first.

> Note: `flutter build apk` currently fails in `camera_android_camerax` under
> Gradle 9.7.0. That failure predates this work and is unrelated to it —
> confirmed by building with these changes stashed. `flutter build bundle`
> (the Dart half) succeeds.

### Bolus delivery from the injection sheet

The injection sheet delivers through the pod when one is paired, and otherwise
behaves exactly as it did before — the user injects and the app records it. `BolusDelivery` (`lib/src/injection/bolus_delivery.dart`)
makes that choice; `PodDeliveryGuard` runs in front of the pod with the user's own
`ProfileBolusState.maxBolus` as its ceiling, so the limit the sheet already
enforces is the limit the pump enforces.

**What gets recorded is one-directional, and this is the load-bearing rule:**
insulin is written to the meal log only once the pod has confirmed it. A refused
dose, or one whose fate is unknown, records the meal with **zero** insulin and
says so on screen. Understating insulin is correctable by logging it afterwards;
overstating it silently suppresses the next dose through IOB, which is the worse
of the two mistakes. The carbs are always recorded, because the user did eat them.

A refusal or an unknown outcome does not close the confirm page. The message stays
next to a button that now reads "log without bolus", so the user cannot leave
believing a dose went in. `Meal.deliveredByPump` marks the pump-given doses, which
are the ones whose recorded amount is worth doubting if a pod later turns out to
have stopped mid-delivery.

### Surviving an app reset

A pod answers only to the controller that activated it, and that binding cannot be
redone. So losing the long-term key locally means losing the ability to STOP a pod
that is still on the body — the same hazard as the section below, arrived at by
accident instead of by design.

`PumpSync` (`lib/src/pump/pump_sync.dart`) therefore mirrors the pairing to the
user's account the moment it completes, and `PodRestoreCard` offers it back when
the app has no pod but the account does. It follows `SensorSync` exactly, including
the opaque blob: the server stores bytes it never interprets, which is required
here for the licensing reason above, not just for tidiness.

Two things worth knowing:

- **The counters lag.** The key is pushed immediately; the command and session
  counters are only refreshed opportunistically after each operation. A restored
  app may therefore be behind. That is recoverable — a stale command counter earns
  one refusal, a stale session counter one resynchronisation round, both already
  handled. Being keyless is what is not recoverable, which is why the key is not
  treated as lazily as the counters.
- **A restore is never offered while a pod is paired locally.** Adopting a second
  identity would replace the key to a pod that may still be delivering.
- The stored record carries the pod's own expiry, so it ages out with the pod it
  describes rather than lingering as a usable key.

### Pod life and reservoir on the overview

The overview shows a pod exactly the way it shows a sensor, because it is the same
widget: `DeviceLifespanBar` (was `SensorLifeBar`, moved to `base/` when the pod
started needing it) draws one segment per remaining day, switching to hours in the
final day.

That reuse works because a pod's 80 hours describe the same shape the sensor bar
already models: **three rated days plus an eight-hour grace window**, which is what
an Omnipod actually does. `DeviceLifespan` needed no changes at all — only the
title key became a parameter, since the remaining-time wording ("# days left") was
already device-neutral.

The reservoir is the one thing a sensor has no equivalent for, so it sits as a line
underneath. It is never shown as a number the pod did not give: above roughly 50 U
the pod reports a sentinel rather than a measurement, and that case is worded
instead. Ten units or less is called out in the warning colour, which still leaves
time to plan a pod change.

### The panel

`/devices/pump` lists every pod the account recorded, mirroring the sensor list
column for column, plus lot/serial and the reservoir.

Two things specific to the pod side:

- **`unique_id` cannot identify a pod.** It is derived from the controller id, so
  every pod this app has ever activated carries the same one. The panel therefore
  de-duplicates restored registrations by activation time — two pods are never
  activated in the same millisecond. (`uniqueSensors` keys off `resolved_key`,
  which has no pod equivalent.)
- **The reservoir is a snapshot, labelled as one.** The app mirrors a pod's state
  only when it happens to talk to it, so the panel shows "as of the last contact"
  and never implies a live reading. The live figure is in the app.

`src/lib/pump.ts` deliberately does not declare `long_term_key` in its blob type,
even though the blob carries it — it is the credential that authorises delivering
insulin, and nothing in the panel should be able to reach for it by accident.

### Basal into the forecasting model

Boluses already reached the model: the app logs every dose as a meal row, and the
predictor reads `nutrition_meals`. **Basal did not**, and on a pump it is often
about half a day's insulin — so insulin on board was being built from roughly half
the insulin.

The chain is app → `/insulin/basal/sync/` → `basal_entries` → the predictor's
`basal_u` channel. Four decisions hold it together:

**A temporary rate is billed at the temporary rate.** `PodBasalDelivery` splits the
window at the temp basal's start and end as well as at each hour boundary, so a
temp basal beginning mid-hour is billed correctly on both sides. A zero-rate temp —
the common "stop basal for sport" case — books the nothing it is; billing the
schedule there would tell the model about insulin the pod deliberately withheld. The
stored window is retired only once the ledger has billed PAST its end, so the window
straddling the end still splits at the right rate.

**It is booked from the programmed schedule, not from the pod's delivery counter.**
The pod reports a cumulative `totalPulsesDelivered` that includes boluses.
Differencing it and sending the result alongside the meal rows would count every
bolus twice — a far worse error than the metering difference this ignores.
`PodBasalDelivery` integrates the stored schedule over the window instead.

**Nothing is booked unless the pod says it was delivering.** A suspended or
alarming pod books a zero — which still closes the window, or the next poll would
bill the whole stretch as if the pod had run through it. Those are exactly the
stretches where the model would otherwise assume insulin that never arrived.

**The ledger cannot double-count or gap.** `PodStore.addBasalDelivery` records the
sample and advances the accounting mark in one step; samples are dropped locally
only once the account has accepted them, because the service polls whether or not
the phone has a connection and a lost sample is a hole nothing later can fill.

**In the predictor, basal gets its OWN raw channel and is summed into IOB — but
never into the bolus-edge features.** `insulin_u` drives `_bolus_flag` and
`time_since_bolus`; folding a continuous drip into it would make "a bolus happened"
true in every single bucket and destroy both. The two are summed only where summing
is correct — insulin on board and its rate of action — because basal and bolus are
the same molecule. `features.build._total_insulin` is that sum, and a test pins that
a basal drip never raises the bolus flag.

One thing this surfaced: the IOB feature used to be gated on `insulin_u` alone, so a
pump user **between** boluses would have had no IOB at all — precisely the stretch
where basal is the only insulin acting. It is now gated on either channel.

### The background watch

Pod warnings are raised from the service isolate, so they arrive with the app
closed. Four design points, in order of how easy each is to get wrong:

**1. It rides the existing service; it is not a second one.** The app has exactly
one foreground service (`CgmTaskHandler`), and `PodMonitor` is hosted in it the way
the Fitbit band is. That is not economy — **two things scanning for BLE around the
clock wedge Android's scanner**, the documented multi-hour "0 devices found" stall.
So the pod poll **never scans**: `PodConnection.openSession(allowScan: false)`
connects straight to the stored address, mirroring the band's known-only rule and
the G7's autoConnect lesson.

**2. The checks split into contact-free and polling halves, and that split is the
point.** Expiry and "no contact for 45 minutes" are computed from stored values, so
they keep working exactly when the link does not — and a link that is down is
itself one of the things worth warning about. Only the reservoir, the alarm reason
and the delivery state need the pod. A test pins this: an unreachable pod still
gets its expiry warning.

**3. The pod's own beeper is the primary alarm.** It sounds on occlusion, an empty
reservoir and expiry whether or not this app runs, and needs no radio. The
notifications are the supplement that reaches a phone in another room and that can
say WHY — the pod can only beep. That is what makes a 15-minute poll interval
acceptable rather than negligent.

**4. A deliberate suspend must not read as a fault.** `PodStore.suspendedByUs` is
set when the app sends a suspend and cleared when a status shows the pod delivering
again — the authoritative signal, since a resume can come from an activation, a
retry, or the pod itself. Without it, every user-requested stop would fire "your
pod stopped on its own", and a restarted service (whose edge tracker starts out
assuming delivery) would fire it too.

What each warning does:

| Warning | Needs the pod? | Gating |
|---------|----------------|--------|
| Expiry within the configured hours (default 4) | no | `NotificationSetting.podExpiry`, one-shot per pod |
| Expired | no | same |
| Reservoir below the configured units (default 10) | yes | `NotificationSetting.podInsulin`, one-shot per pod |
| Pod alarmed — occlusion, empty, infusion error, fault | yes | **none** |
| Delivery stopped without us asking | yes | **none** |
| No contact for 45 min | no | silent mode only |

The two ungated ones are deliberate: an alarming or stopped pod is **not delivering
insulin**, which is not something a user can opt out of being told. Both bypass Do
Not Disturb, for the same reason the glucose alarms do.

Two smaller things worth knowing:

- **One-shot flags are keyed by activation time, not by pod id.** The pod's id is
  derived from the controller address and is identical for every pod this app ever
  activates, so it cannot tell two apart; two pods are never activated in the same
  millisecond.
- **The pod store is reloaded at the poll cadence, not every tick.** A fresh
  `readAll()` decrypts the whole keystore, and 30-second ticks would do that 120
  times an hour for data that changes hourly. The cost is that a pod paired while
  the service runs is noticed within one poll interval — nothing against an 80-hour
  life.

### Activation

`PodActivationController` + `PodActivationPage` walk the user through it in two
phases, split at the point where the pod physically moves onto the body — the one
transition no state machine can observe.

The properties worth keeping:

- **The binding is stated before anything is sent.** The first screen says that
  activation ties the pod to this app for good, that the user's PDM will no longer
  reach it, and that Insulink then becomes the only thing that can stop it.
- **The basal profile is converted on the FIRST screen**, not when it is needed.
  `PodBasalAdapter` turns the app's 24 hourly rates into the pod's 48 half-hour
  slots (two identical slots per hour, no interpolation), and a profile the pod
  cannot hold disables the start button then and there. Discovering it later would
  mean throwing away a pod that had already been primed and bound.
- **A retry resumes, it does not restart.** Every protocol step is written to the
  store before the next runs, so the two steps that deliver insulin — priming and
  cannula insertion — are never repeated. `test/pump/pod_activation_test.dart`
  covers exactly that.
- **Failure offers both ways out**: retry the same pod, or discard it. A failed
  activation often means the pod is scrap, and pretending otherwise with a silent
  retry loop would be worse.

#### The cannula confirmation

Driving the cannula in is the only step of the activation that puts a needle under
the user's skin, so it is gated by the device biometric — the same `BiometricAuth`
that gates a bolus, and with the same setting: **biometric only, no PIN fallback**.

The gate sits in `PodActivation._insertCannula`, immediately before the command,
NOT on the button that normally precedes it. Every route into the insertion — a
first run, a retry, a resume — therefore passes through it. The callback is a
**required** constructor parameter, so a caller that forgot to wire a confirmation
does not compile rather than silently inserting unprompted.

Consequences that are deliberate:

- **Priming is not gated.** It delivers insulin, but into a pod that is still off
  the body. A second identical prompt in front of it would train the user to tap
  through both.
- **A resume past the insertion does not ask again.** The needle is already in;
  prompting would imply it is about to happen a second time.
- **A decline is not a failure.** `PodActivationCancelled` is its own exception,
  the step is not recorded, the pod is untouched, and the wizard says so in the
  warning tone rather than the error one.
- **A user with no enrolled biometric cannot finish an activation.** That is the
  cost of biometric-only, and it is a wasted pod rather than a hazard. If it proves
  too harsh, `BiometricAuth.confirm(allowDeviceCredential: true)` is the one-line
  change — but it weakens exactly the gate this exists to be.

## Why there is no read-only mode

The obvious safe-looking first step — "just read pod status, don't command
anything" — **does not exist for Omnipod**, and it is worth being explicit about
why, because it changes what this feature can ever be.

A pod's BLE link is exclusive and encrypted with a long-term key established at
activation. There is no passive read: to see any pod data at all, the pod has to
be activated *by us*, with our controller id. The `SET_UNIQUE_ID` command that
does this is **irreversible for the life of the pod** — afterwards the user's own
PDM can no longer command that pod.

The consequence is the single most important safety property of this feature:

> **Once Insulink activates a pod, Insulink is the only thing that can stop it.**
> A pod delivering basal that the controlling app cannot reach can only be
> stopped by physically tearing it off.

So "pair and read" is not a safer subset of "pair and control" — it is strictly
more dangerous, because it takes on the obligation to stop delivery without
building the means to. Any shipped version of this feature must be able to
suspend and deactivate a pod reliably, or it must not activate one at all.

## Hazards and what stands against each

| Hazard | Consequence | Mitigation in this code |
|--------|-------------|-------------------------|
| Unit→pulse conversion error | wrong dose, silently | `PodBolusAmount` never carries a double past construction; a dose off the 0.05 U grid is refused, not rounded |
| Encoder bug in the bolus frame | wrong dose, silently | `PodProgramBolusCommand.encoded` reads the pulse count back out of the finished bytes from all three places the frame repeats it, plus its own CRC, and throws instead of returning a frame that disagrees |
| Corrupted frame accepted as a command | arbitrary pod behaviour | CRC-16 per command, CRC-32 per reassembled payload, AES-CCM tag per message; all three refuse rather than pass through |
| Forged or replayed pod message | false status → wrong dosing decision | AES-CCM authenticates the 16-byte header as associated data; nonce counter carries a direction bit so the two sides never share a nonce |
| Man-in-the-middle during pairing | attacker-chosen key | pod confirmation value compared in constant time before pairing is accepted; low-order X25519 points rejected in Rust |
| Retried command delivered twice | double dose | 4-bit command sequence number — the pod recognises and ignores a repeat. **Never reuse a number for a different command and never skip one**. `PodRetry` only repeats failures that happened BEFORE a command was sent, and a failed attempt never persists the counter, so every retry sends the same number |
| Stale pod status | bolus stacked on a running one | `PodDeliveryGuard` refuses any bolus decided on a status older than 2 min |
| Repeat taps / retry loop | stacked doses | rolling one-hour ceiling in `PodDeliveryGuard`, on top of the per-bolus cap |
| Bolus larger than the reservoir | partial delivery, wrong IOB | refused when the pod reports a measurable reservoir |
| Pod in alarm or not running | command silently ignored | lifecycle checked before every bolus |
| Delivery command reaching a pod mid-activation | undefined | `PodLifecycleStatus.acceptsDelivery` gates it |
| Automation dosing on stale or impossible sensor data | wrong dose from a number that describes nothing | `LoopGlucose` refuses data over 12 min old, outside 30 to 500 mg/dL, moving faster than 8 mg/dL per min, or with too few points to measure a trend; no decision can be computed without one |
| Automation stacking its own corrections | escalating dose nobody chose | its own excess above the schedule counts as insulin on board (`PodLoopJournal.loopIobUnits`), so each cycle sees what the last one gave |
| Automation driving glucose into severe hypoglycaemia | the hazard the whole feature is bounded by | the insulin it may add is capped at what fits between glucose and the suspend threshold, measured over the WHOLE fuse rather than the cycle, so the guarded case is the loop dying immediately after programming. Swept in `loop_hypo_bound_test.dart` |
| Basal schedule programmed over a running temporary rate | pod faults and stops delivering, unattended | the temporary rate is ended first, in the same session, whenever a schedule is programmed (`PodController._endRunningTempBasal`). AndroidAPS opens its own profile change with the same step. This app skipped it and a real pod answered an edited profile, sent while the automation held 0.0 U/h, with alarm 0x31 and a stopped delivery |
| A program landing on a running temporary rate | pod faults and stops delivering, unattended | `PodController._programBasalDelivery` is the ONLY way a schedule or a rate is programmed, and it ends a running temporary rate first. `LoopPodCommands.programTempBasal` does the same for the automation. Both judge it from a status read FROM THE POD, never from the app's own record: the automation runs in the other isolate and can hold a rate this isolate's cache has never seen |
| The app holding a pod that has already stopped | the pump page is occupied by something that will never answer, with no way out | deactivation is judged on `PodLifecycleStatus.acceptsDelivery`, not on the delivery byte reading as a plain `suspended`, which a deactivated pod is not obliged to report. `forgetUnreachablePod` is the manual way out when the pod answers nothing at all |
| Two sessions on one pod from the same isolate | both hang up, looks like a pod that blocks under load | the service's watch and automation are chained on one tick AND that chain is gated (`CgmTaskHandler._tickPodChain`), so a 30 s watchdog cannot start a second one over a poll that is still connecting. They share a lease owner deliberately, so the lease cannot separate them and the gate has to |
| A lost link race answered by reconnecting | contention treated as its own cure | `PodLinkBusy` is on the `PodRetry` deny-list. The waiting policy belongs to `PodLinkLease` and only to it: the UI waits 12 s for a tap, the service waits nothing because its next tick is free. A retry on top overrode both |
| Automation left running by a phone that dies | unattended delivery with nothing able to stop it | every automated rate is a temp basal lasting one fuse; the POD returns to the stored schedule when it expires, with no app involved |
| Automation silently overriding a rate the user set | a temp basal set for sport undone without notice | `PodTemporaryBasal.automated` distinguishes them and the loop defers to the user's, except for a suspension |
| Automation dosing on top of a bolus nobody could confirm | stacked dose from insulin the loop cannot see | an unconfirmed bolus is recorded in `PodStore.unconfirmedBoluses` and counted as delivered BY THE LOOP only; the user's own calculator still counts it as not given, because the conservative assumption differs per reader |
| Automation stopping without the user noticing | delivery believed managed when it is not | every self-stop raises a notification, and the overview keeps showing it until the user acts |
| UI and background service on the pod at once | both sessions collapse; looks like a pod that blocks under load | `PodLinkLease` in secure storage, the only thing both isolates can see. One owner per isolate; the UI waits the service out, the service comes back next tick |

### Only one part of the app may hold the link

The pod's link is exclusive, and the app reaches for it from **two isolates**:
the UI when the user taps something, and the foreground service for the
background poll and the automation. Neither can see the other's state, so both
connect, and the symptom is not obvious:

```
pod link: connected to 64:00:9C:68:56:42      <- twice, interleaved
pod link: -> command 06 01 04 00 00 10 92     <- twice
pod poll failed:    ERROR_GATT_WRITE_REQUEST_BUSY
pod refresh failed: Expected success, got abort
```

`pod poll` is the service, `pod refresh` is the UI. Android answers the second
writer with `ERROR_GATT_WRITE_REQUEST_BUSY`, the pod gives up on both sessions,
and the whole thing **reads as a pod that blocks when it is sent too many
commands**. It is not; it is the app competing with itself.

`PodLinkLease` holds a lease in secure storage, which is the only state both
isolates share. Load-bearing details:

- **A lease, not a lock.** A holder that is killed never releases anything, so it
  expires by itself (90 s). One crash must not put the pod out of reach.
- **One owner per ISOLATE, not per feature.** The background watch and the
  automation run chained on the same tick, so a separate owner each would have
  them locking one another out. Both are `the background service`.
- **Taken by write-then-read-back**, not check-then-write. Two isolates can pass
  the check at the same instant; only one write lands last, and reading back is
  what tells the loser it lost.
- **The two sides have opposite patience.** A tap has to happen and a poll is
  seconds long, so the UI waits up to 12 s. The service's work is periodic, so it
  gives up at once and comes back on the next tick.
- `PodLinkBusy` is thrown before anything reaches the pod, so `PodRetry` repeats
  it like any other pre-command failure.

### The pump page opens on a cached status

`PodStatusCache` keeps the last status any isolate read, as the raw frame plus a
timestamp. Two jobs:

- **The page opens on something.** Without it every visit began blank, several
  seconds of a spinner before the page could say whether the pod was delivering.
- **The automation can decide while switched off**, from a status somebody else
  already paid for.

Both isolates write it, so the UI benefits from the background poll and the poll
benefits from the UI. Two freshness windows, deliberately different: two minutes
is how fresh a status must be to DOSE against (`PodController.statusFreshFor`,
matching `PodDeliveryGuard`), five is how old the shown one may get before opening
the page reads the pod again. Conflating them is what made every page open cost a
BLE session.

### Retrying a pod operation

The link is fragile: it drops, it refuses a session opened too soon after the
last one closed, and it goes quiet under repeated commands. Most of that happens
during the connect and the handshake, with **no command sent**, so reporting it
to the user as a failure when a second attempt would have worked is its own wrong
answer. `PodRetry` repeats those, with a doubling wait on top of the settle
window `PodConnection` already keeps.

The boundary it exists to hold is what may NOT be repeated, and it is a
deny-list rather than a list of retryable errors, so an unforeseen failure gets
another chance and only outcomes known to be unsafe are excluded:

| Outcome | Repeated | Why |
|---------|----------|-----|
| link never came up, handshake failed, session refused | yes | the pod was asked for nothing |
| anything unclassified | yes | it is far more likely to be a link problem than a delivered dose |
| `PodCommandOutcomeUnknown` | **never** | the command went out and was not answered. The pod may have run it, and repeating it is a second dose |
| `PodBolusRefused` | no | a guard declined against the pod's freshly read state; repeating changes nothing |
| `LoopCommandRefused` | no | the pod itself declined |

For a bolus this means the retry covers the session, the status read and the
guard, and stops at the command. **The `isBolusing` guard cannot be leaned on as
the backstop here**: a small dose can finish between two attempts and leave the
pod looking idle, so the rule has to be the outcome type, not the pod's state.

Two design rules that came out of this and should not be relaxed:

1. **Refuse, never clamp.** Every guard rejects and reports. Quietly delivering
   less than the user asked for is its own dosing error and is harder to notice
   than a refusal.
2. **The stop path carries no arithmetic.** `PodStopDeliveryCommand` contains no
   computed dose — only which streams to halt — so there is no number in it that
   can be wrong. It must never be placed behind a check that can fail closed.

The automated-delivery layer has its own hazard reasoning in `docs/LOOP.md`,
including why it clamps where the rest of this driver refuses.

## Protocol notes

Transport is BLE GATT, service `1a7e4024-e3ed-4464-8b7e-751e03d0dc5f`, with two
characteristics: CMD `1a7e2441-…` and DATA `1a7e2442-…`. Pods advertise service
`4024` and encode pod id, lot and sequence number across nine 16-bit service
UUIDs in the scan record.

Above that, four layers stack:

1. **Fragments** — 20-byte BLE writes, indexed, with a CRC-32 over the whole
   payload (`payload_fragments.dart`, `payload_reassembler.dart`).
2. **Messages** — 16-byte `TW`-prefixed header carrying source, destination,
   sequence and type (`message_packet.dart`).
3. **Security** — pairing (X25519 + AES-CMAC ladder → LTK), then per-session
   EAP-AKA/Milenage → CK, then AES-CCM on every message
   (`key_exchange.dart`, `milenage.dart`, `session_cipher.dart`).
4. **Commands** — the same opcodes the older Eros pods use, wrapped in a keyed
   envelope (`S0.0=` … `,G0.0`) (`pod_command.dart` and siblings).

Details worth not rediscovering:

- **The message length field is 11 bits split across two bytes** (`size >> 3`,
  `size << 5`), and for an encrypted message it counts the payload *without* the
  8-byte tag once the tag is attached — but *with* the plaintext length while the
  tag is being computed. That is what `toBytes(forEncryption:)` is for; getting
  it wrong breaks the CCM associated data, not the framing, so it fails as a tag
  mismatch rather than a parse error.
- **The CRC-16 is not a textbook CRC-16.** The table is the standard 0x8005
  MSB-first one, but the pod's update loop indexes it by the *low* byte of the
  running value. Generating the table and keeping the odd loop is verified
  against three captured command trailers.
- **A delivery command is always preceded by a 0x1a interlock** carrying the same
  pulse count plus an additive checksum of it. Both go in one frame.
- **`ProgramBolus` repeats the dose three times**: interlock pulse count,
  interlock program element, and tenths-of-a-pulse in the bolus body. This
  redundancy is the pod's, and the read-back check makes use of it.
- **Reservoir `0x3FF` means "more than it can measure"**, not 1023 pulses.
  `reservoirUnits` returns null there — never format it as a number.
- **NAK `illegalSecurityCode` (0x14)** is a sequence desync and carries a resync
  counter instead of a lifecycle. It must be resynced, never blindly retried.
- **The pod's id is NOT the controller's id.** The pod answers on the controller
  address with its low two bits replaced by `01`, so a controller on 4242 gives the
  pod 4241 — which is exactly what the captured commands address. Assigning the
  controller's own id instead makes every message's source and destination
  identical. Pinned by `test/pump/pod_ids_test.dart`.
- **That address does not change when the pod is given its id**, because the id it
  is assigned is the address it already answers on. So one session spans the whole
  activation, across `SET_UNIQUE_ID`.
- **A paired-but-unnamed pod still ADVERTISES the discovery address.** Only an
  interrupted activation is in that state, and a resume has to scan for
  `0xFFFFFFFE` rather than the pod's id — see
  `PodConnection.openSession(stillAdvertisingUnactivated:)`.
- **The alarm codes are not enumerated.** The pod has ~160, nearly all internal
  faults with one remedy between them. `PodAlarm` keeps the raw byte and derives
  the handful of categories that lead to different advice (occlusion, empty
  reservoir, expiry, infusion error, escalated alert, radio, internal fault).
- **There are THREE counters and mixing them up is the easiest way to break
  this.** The *pod command sequence* is a persisted 4-bit counter in the command
  header, incremented once per command, and it is what makes a retried command
  run once. The *message sequence* lives inside a session and also advances for
  acknowledgements, so it drifts away from the command counter immediately. The
  *EAP sequence* is a third persisted counter, one per session attempt, which the
  pod refuses to see twice. `PodController` keeps the command counter itself and
  persists it after every operation; it deliberately does NOT adopt the status
  reply's `lastProgrammingSequenceNumber`, which only moves for delivery programs
  and would therefore step the counter backwards onto a number already used.
- **The EAP counter is reserved before use, not after.** Losing a value to a
  crashed handshake costs nothing; reusing one costs a resynchronisation round.

## What still has to happen before this can touch a pod

1. **Hardware verification of everything above the vectors.** The captured
   vectors prove the encoders agree with a known-good implementation, and the
   scripted-pod tests prove the sequences are ordered correctly. Neither proves
   the driver behaves on a live BLE link — timing, reconnects, and the pod
   dropping the link mid-exchange are all untested.
2. The activation wizard UI, which has to walk the user through filling, priming
   off the body, attaching, and cannula insertion — and must state the
   single-controller consequence BEFORE `SET_UNIQUE_ID` is sent.
3. Nothing else. Everything the driver needs to run a pod end to end is written;
   what remains is the hardware verification above.

### Found in the pre-hardware review

A pass over the pairing path before the first hardware test, looking for what the
offline tests structurally cannot see. Four things, in order of how much they cost:

**1. The scan filtered on the wrong UUID — no pod would ever have been found.**
A pod advertises SHORT (16-bit) service ids, so a scan must filter on
`00004024-0000-1000-8000-00805f9b34fb`. Its GATT service, once connected, is the
vendor `1a7e4024-…`, which appears nowhere in the advertisement. The scanner used
the latter. No test could catch this — both are valid UUIDs and there is no radio in
a unit test — so `pod_uuid_test.dart` now pins the two apart by construction.

**2. A lost confirmation reply threw away a working key.** The pod may keep the
long-term key from the moment OUR confirmation reaches it, not from when its reply
reaches us. The key is now handed to `onKeyDerived` and stored BEFORE that message
goes out. Only `PodPairingMismatch` — which proves the two sides derived different
keys — discards it; a dropped link keeps it, because a possibly-good key is the
difference between a pod that can be picked up again and one that is scrap.

**3. A crash between pairing and the first recorded step would have re-paired.**
Deriving a second key for a pod that already holds one loses it. The activation now
resumes whenever a key is stored, whatever the recorded step says.

**4. The first scan had no permission prompt.** A user who never set up a CGM
sensor has never been asked for `BLUETOOTH_SCAN`/`CONNECT`, so the first pod scan
would have failed with an opaque platform error — at the moment a pod is filled and
waiting. `PodBlePermissions` now asks first, with a localized explanation.

**Second pass — five more, four of which would have broken a real activation:**

**5. Nothing reconnected after the long waits.** Priming takes close to a minute and
the pod hangs up on an idle link, so the status read that verifies priming would have
gone down a dead link — failing EVERY activation at that step. The reference driver
reconnects at exactly these two points, with the comment "connection can time out
while waiting". `PodActivation.reopenLink` now does, and only ever before an
idempotent status read: reconnecting and retrying a delivery command that may already
have run is how a dose gets given twice.

**6. The activation forgot its command counter.** The pod treats a repeated sequence
number as the command it already carried out. With the counter living only in memory,
the first command after an activation would have restarted at one — and a bolus would
have been quietly ignored while the app recorded it as delivered.

**7. The UI never re-read the store, whose cache is per isolate.** The background
watch advances the command counter every quarter hour; the UI kept the value it read
at app start. `PodController` now reloads before every session, the same discipline
`CgmController` already follows.

**8. A new pod inherited the previous pod's counters.** A fresh pod has never seen a
session, so `savePairing(resetSessionCounters: true)` starts it at one — while a
RESTORE deliberately preserves what it was given, since that pod is already running.

**9. A competing scan looked like an absent pod.** Only one BLE scan runs at a time
and the CGM service scans on its own schedule, stopping ours mid-flight. An empty
result is now retried once.

**Third pass — the resume path, and two counters:**

**10. A resumed activation re-sent the two commands that cannot be repeated.**
Reading the version is addressed to the DISCOVERY id, which the pod stops answering
on the moment it has an id of its own, and assigning that id is one-shot. Anything
picked up after `identitySet` — the app restarted, the wizard reopened — would have
sent both to a pod that never answers, and hung there. The reference driver gates
exactly these two on its stored progress; it can afford to, because it primes with
constants. We prime with the volumes the POD asked for, so those numbers are
persisted (`PodStore.activationFacts`) the moment they arrive, and a resume works
from the record. A resume with no record stops with a clear message rather than
guessing a dose.

**11. The message-packet counter was confused with the command counter.** Two
different counters: one numbers COMMANDS inside four bits, the other numbers the
PACKETS carrying them and is a byte wide. Only the first was stored, and the second
was seeded from it — so every session after the first started its packet numbering
at an arbitrary place. It is now `PodStore.messageSequence`, recorded when the link
closes (so no caller has to remember), mirrored to the backend, and started at zero
for a newly paired pod.

**12. Any well-formed status counted as "the bolus is running".** The pod answers a
command sequence number it has already run by re-sending the answer it gave the
first time — so a counter that drifted (the app and the background poll racing)
reads as a perfect status while no insulin moves, and the app would have logged a
dose the user never got. The reply now has to NAME the bolus — pulses remaining, or
the bolus delivery flag — or the outcome is reported as unknown and nothing is
recorded.

**13. A discarded pod answers to the same address as the one on the body.** Every
pod this app activates is given the SAME id, so the pod that was just replaced is a
second, equally valid answer to a reconnect scan until its battery dies. The stored
BLE address now settles it; an ambiguity it cannot settle is still refused rather
than guessed, since commanding the wrong pod is worse than failing.

**14. Reconnecting after a prime scanned for a pod already in hand.** The address is
known and this process has just used it, so the reconnect connects straight to it and
only falls back to a scan if that fails — closing the half-open link first, or the app
would hold two GATT clients to one pod (the same leak the CGM notes document).

**15. A running pod could be discarded — the one outcome everything else prevents.**
Bookkeeping AFTER the pod was already delivering (the basal ledger, the backend
mirror) ran inside the same `try` as the protocol, so a failed network call turned
the wizard to "Activation stopped" and offered "Discard pod" for a pod with a
cannula in the body. Discarding forgets the key, and a forgotten key cannot be
recovered: the pod would have kept delivering with nothing able to stop it. Two
changes — the wizard reaches `running` before any bookkeeping and a failure there is
reported without unwinding the stage, and `discardAttempt` outright REFUSES from
`insertingCannula` onwards, pointing at deactivation instead.

**16. The fingerprint requirement was only announced once the pod was on the body.**
Biometric-only, no PIN fallback, is deliberate — but a phone with no fingerprint
enrolled failed at the cannula step, with the pod primed, bound and attached. The
explanation screen now says so before priming, and the declined message names the
missing enrolment as a possible cause.

**17. The wizard could not be left while it was searching.** The back arrow was
hidden for the whole busy stage and there was no cancel, so a scan that found
nothing held the screen for up to a minute with no way out. The back arrow, the
system back gesture and a stop button now all work mid-operation, all through
`PodActivationExit`, which warns first and says the honest thing: what already
happened to the pod cannot be undone, but nothing is lost, because every step is
recorded before the next one runs and the wizard resumes from it. Stopping ends
the scan (`PodScanner.stop`) and drops the link rather than waiting out the
timeout, and `scanForSingle` skips its retry when the user has stopped.

**18. A plugin `Error` left the wizard spinning forever.** The activation caught
`on Exception`, and flutter_blue_plus throws an `Error` on a platform it does not
support. Anything of that shape escaped, the stage stayed on `priming`, and the
spinner never stopped — the one state the user could not get out of. Found by the
test written for finding #17. `PodActivationController`, `PodController` and
`PodMonitor` now catch everything on those paths. The controller also stops
notifying once disposed, since the user can now leave while a call is in flight.

Also hardened: a stale control word left over from a finished exchange is discarded
instead of aborting the next send (a pending request-to-send still stops it, since
the pod has something to say), out-of-order fragments are buffered rather than
re-requested, and closing a link the pod has already dropped no longer throws — which
is the normal state after a prime wait, right where the reconnect happens.

### What to check first with a real pod

In rough order of how likely each is to be wrong, and how much it matters:

1. **Pairing and session establishment end to end.** The crypto is pinned, but
   the control-word framing (`request-to-send` / `clear-to-send` / `success`) is
   only verified against my own scripted pod, which cannot disagree with my
   reading of it.
2. **The command sequence number across reconnects.** A wrong value gets a NAK
   with `illegalSecurityCode`; the resync path exists but has never run against
   a pod.
3. **`GET_STATUS` on a running pod**, compared against the PDM's own display —
   the cheapest way to confirm the status decoder against reality.
4. **Only then** anything that delivers, starting with the smallest bolus the
   pod accepts (0.05 U) and checking the reservoir count moves by exactly one
   pulse.

## Provenance and licence

The protocol layout, the magic constants and the test vectors come from
**AndroidAPS** (`pump/omnipod/common/bledriver`), which is **AGPL-3.0**. The app
was therefore relicensed from GPL-3.0 to **AGPL-3.0**; the Juggluco-derived CGM
files stay GPL-3.0, which both licences permit (GPL-3.0 §13 / AGPL-3.0 §13). Per
file: `NOTICE`.

**One constraint follows from this and is easy to violate by accident:** AGPL-3.0
§13 obliges anyone offering a modified version over a network to publish its
source. The app is not a network service, so it does not apply today — but
`insulink-api` is. Pod protocol logic must therefore stay in the app. The API may
store pump state as an opaque blob it never interprets; porting any of the driver
into it would turn the API into an AGPL network service.

Additional protocol background, from which no code was taken: the openomni wiki
(the Eros-level message layer that DASH reuses) and Loop's OmniBLE.
