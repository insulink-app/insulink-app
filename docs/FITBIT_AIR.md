# Fitbit Air: vibration and battery

The band's private features go through the third-party
[`fitbit_air`](https://pub.dev/packages/fitbit_air) plugin (Apache-2.0,
unverified publisher, reviewed by the maintainer before adoption). It ships its
own Golden Gate transport (`libgg.so`/`libxp.so`, reproducibly built from
public source, `tool/native/build.py --check` in its repo) and talks to the
band over the tracker channel Google Health uses. The Air must be paired in the
Google Health app; nothing here pairs or unpairs it. Live pulse is separate and
stays on the standard 0x180D service (`FitbitHeartRateMonitor`).

Code: `lib/src/google_health/band/`.

## Vibration on alarms

Every glucose alarm and both pre-warnings buzz the band (`BandHaptics.play`),
unawaited, so the buzz never delays the notification or the tone. Edge-triggered
like the alarm itself; silent mode "everything" suppresses it with the
notification, "tones only" keeps it.

Each alarm has its own pattern, coded like the alarm tones
(`BandVibrationPattern`):

| Alarm | Pattern |
|-------|---------|
| pre-warning low | 2 |
| low warning | 2 · 2 |
| urgent low | 2 · 2 · 2 |
| pre-warning high | 1 |
| high warning | 1 · 1 |
| urgent high | 1 · 1 · 1 |

A double pulse is the plugin's `vibrate()`, a single one `tap()`; those are the
only two primitives, and each is a secure session of a few seconds, so the
groups arrive several seconds apart. `test/google_health/band_vibration_pattern_test.dart`
fails if two alarms ever share a pattern.

- Temporary failures (`BUSY`, Google Health holding the channel, a timeout) are
  retried twice, 10 s apart, per group.
- One switch per alarm (`band_vibration_<slot>`, default ON), each with a
  preview button that plays the pattern, under Notifications, Fitbit Air.
- The glucose range's "Test alarm" buzzes too; the device page has a plain
  reachability test.

## Night mode

`profile/night/`. Off, on, or automatic. While active, warnings and
pre-warnings only buzz the band and the phone stays quiet
(`G7AlarmManager._alert`). Two rules keep it from ever swallowing an alarm:

- Urgent alarms always ring.
- A warning whose buzz did not reach the band (that alarm's vibration off, band
  away, Bluetooth off, three failed tries) rings after all, just later.

Automatic (`NightModeDetector`, fed from the hosted band's live pulse in the
service isolate): night once every sample for 20 minutes stayed below the
user's threshold (default 55 bpm), awake at the first sample 10 bpm above it,
and awake when no pulse arrived for 10 minutes. Losing the pulse ends night
mode on purpose: nothing then says the wearer still sleeps, and the safe
direction is a ringing phone. The verdict is stored (`night_mode_detected`) so
the alarm code and the settings page read it; the first tick after a service
restart overwrites a stale one. Pulse only, no clock window yet.

## Battery

- The service watchdog reads it hourly (`BandBatteryWatch`), skipped while the
  battery saver pauses the band. Each read opens a short secure session next to
  Google Health's, so it is deliberately rare.
- At or below 20 % and not charging: one warning per discharge (id 106,
  warning channel). The "already warned" flag is persisted; charging or rising
  above 20 % re-arms it. Silent mode holds it back without marking it given.
  Toggle: `NotificationSetting.bandBatteryLow` (default ON).
- The device page shows the stored reading at once and reads a fresh one when
  opened. The section only appears when an Air is paired.

## Known limits

- Every command briefly competes with Google Health for the band's single
  channel (the plugin hands it back afterwards). Bursts of alarms are rare
  because alarms are edge-triggered.
- The UI isolate (test button, page open) and the service isolate (alarms,
  hourly read) can collide; the plugin answers the second one with `BUSY`,
  which the alarm path retries.
- Verified by the plugin author on Pixel 7 Pro / firmware 67.20001.253.2 only.
