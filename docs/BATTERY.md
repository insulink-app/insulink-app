# Battery saver

Two-level, optionally time-limited switch that scales back the app's background
work. State: `lib/src/profile/battery/profile_battery_state.dart`
(`BatteryMode` + `ProfileBatteryState`).

**The glucose pipeline is never touched.** CGM BLE, the watchdog, the alarms and
the ongoing notification run identically at every level, and a **manually
started** training keeps recording its dense GPS route. A saver that mutes an
alarm or truncates a recording would be a bug, not a feature.

## What each level does

| Consumer | `off` | `saving` | `extreme` |
|---|---|---|---|
| Cardio auto-detection: GPS tick, activity-recognition stream, detection scan | on | **off** | **off** |
| Detection-only service started by opening the Sport tab | starts | **stays down** | **stays down** |
| Health Connect HR poll (`CgmTaskHandler._hrPollEvery`) | 60 s | **5 min** | **5 min** |
| Hosted Fitbit band BLE link (~1 Hz) | on | on | **off** |
| Per-reading forecast fetch (`_refreshPrediction`) | on | on | **off** |
| Background pulse flush (`_flushBackgroundPulse`) | 1 / 5 min | 1 / 5 min | **always 5 min** |

`saving` targets the by far biggest drain: `BackgroundLocationSampler` holds a
continuous high-accuracy `Geolocator.getPositionStream` open whenever motion is
detected (10 s / 15 m, tightening to 5 s / 8 m after 3 min of movement), and
polls a one-shot fix every 55 s at rest — all of it for auto-detection the user
never asked for directly.

## Turning it on takes a fingerprint

`ProfileBatterySelection` requires `BiometricAuth().confirm(...,
allowDeviceCredential: true)` (PIN/pattern fallback, so a user with no enrolled
biometric is not locked out) before switching a level ON. It quietly stops
background work the user may be relying on, so it must be a deliberate,
owner-only action. Switching it **off** — including the one-tap overview banner —
and changing the duration of a level that was already confirmed are direct:
neither reduces what the app does. Unlike the hard mute there is no risk `Alert`
first; the saver never touches alarms.

## How the mode reaches the work

Three keys in secure storage, mirrored into the account settings blob by
`ProfileSettings.collect()`:

- `battery_saver_mode` — the enum `name`. A **string**, unlike silent mode's two
  booleans: no client coerces this key, so there is no `silent_mode`-style
  round-trip trap.
- `battery_saver_window_min` — the picked window (`0` = permanent). Stored
  separately because the end timestamp alone can't say which duration was picked
  once time has passed, and so re-arming the same duration is one tap.
- `battery_saver_until` — epoch ms the window ends at (`0` = permanent).

The window itself is `ProfileModeWindow` in
`lib/src/profile/profile_mode_window.dart`, **shared with silent mode** — both are
modes you switch on for a while and want back off by themselves, and both render
the same `ProfileDurationRow`. The **end is a timestamp, not a countdown**, so a
temporary saver expires correctly across an app close: `loadRaw()` normalises a
lapsed window to `off`, and `activeMode` compares against the clock. The
in-isolate `Timer` exists only so the overview banner disappears on time while the
app is open.

The gated work runs in the **foreground-service isolate**, which cannot observe a
`ChangeNotifier`. `CgmTaskHandler._applyBatteryMode()` therefore re-reads
`loadActive()` once per 30 s watchdog tick, caches it in `_batteryMode`, and
brings the two long-lived subscriptions in line (activity-recognition stream,
hosted band). Everything else reads the cached value — notably
`BackgroundLocationSampler`, which takes it as an injected
`isDetectionPaused` callback exactly like the existing `isStill`, so the 10 s GPS
tick gains no secure-storage read. Consequence: **toggling the saver takes effect
within one tick, without restarting the service.**

## Two things that look optional and are not

1. **`CgmController.ensureDetectionService({force})`.** Opening the Sport tab
   starts a sensorless location-typed FGS; under a saver that service would only
   hold the wake + Wi-Fi lock, so it stays down. But a manual cardio recording
   depended on that same call — `CardioTrainingState.startTraining` starts no
   service of its own. Hence `force: true` from
   `cardio_recording_page.dart`, which skips only the saver check, never the
   permission checks.
2. **The guard sits in `BackgroundLocationSampler.tick()`, after `recording` is
   known.** That one place covers both the detect stream and the idle poll while
   leaving `GpsTier.recording` alone; `LocationSync` falls silent by itself
   because no fixes are produced.

## Deliberately not done

- **`allowWakeLock` / `allowWifiLock` stay on.** Both live in
  `ForegroundTaskOptions` and can only be set at service start, so changing them
  would mean a restart — and the Wi-Fi lock exists precisely so the glucose POST
  survives Doze (see the comment in `cgm_controller.dart`).
- **UI-isolate timers untouched** (`GoogleHealthState`, `PulseSync`'s 1 s live
  relay, the `repeat()` animations): they only run with the app open and the
  screen on, where the display dominates. Note the consequence for `extreme`:
  once the service stops hosting the band, `GoogleHealthState._bleMonitor` may
  pick it up while the app is foregrounded (it only stands down on a service `hr`
  push). So `extreme` drops the band in the background — the case that matters —
  not with the app open in front of you.
- **No per-consumer switches.** Two levels are the decision; an eight-checkbox
  tree is the setting nobody configures correctly.
- **No auto-activation at low battery.** A mode that turns itself on and quietly
  stops training detection would surprise.
