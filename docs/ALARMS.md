# Alarms & notifications

`lib/src/g7/alarms.dart` (`G7AlarmManager`) raises the local notifications for
glucose alarms, the "connection lost" warning, and the "sensor expiring soon"
warning. It runs in the **foreground-service isolate** (alongside
`G7TaskHandler`), so alarms fire even when the app is closed.

`init()` must be called once per isolate before `check()` — same lifecycle
constraint as `RustLib.init()`.

## Why the tone is played manually, not by the channel

The alarm channels are created with `playSound: false`. The audible tone is
played by us through `audioplayers` on the **ALARM audio stream**
(`usageType: alarm`). Reasons:

- A notification channel's sound obeys the **notification-volume** slider, which
  can be 0 → an unheard low-glucose alarm. The ALARM stream obeys the
  alarm-volume slider and sounds through a silenced ringer, DnD, and screen-off,
  like Dexcom.
- A channel's sound/routing is **frozen at channel-creation time** and can't be
  changed afterwards.

`alarm_low.wav` / `alarm_high.wav` live in `assets/sounds/`. Audio is
best-effort: if it fails (or the user disabled the tone via
`ProfileAlarmSoundState`), the visual notification still fires.

## DnD bypass is order-sensitive (load-bearing)

The alarm channels set `channelBypassDnd: true`. Android **silently ignores**
that flag unless "Do Not Disturb access" was granted **before the channel is
created**. So `ensureDndAccess()` is called from the **UI isolate**
(`G7Controller.start()`), before the service isolate posts its first alarm — the
service isolate has no activity to launch the settings screen.

## Edge-triggered glucose alarms

`check()` maps a reading to a `G7AlarmLevel` (none / low|high × warning|urgent)
and only notifies when the **zone changes**. Re-evaluating the same zone every
5 min does not re-notify. The zone is tracked even while silent, so turning
silent mode off does not re-fire an alarm for a value still in-zone — only a
fresh crossing fires.

Thresholds, display unit, and the silent flag are read **fresh from storage on
every call** (`ProfileGlucoseState.loadThresholds()`, `ProfileSilentState.load()`)
so profile changes take effect without restarting the service isolate.

Urgent levels additionally set `fullScreenIntent` + `category: alarm`.

## Channel ids and notification ids

- Glucose alarm channels: `insulink_alarm_{low,high}_{warning,urgent}`, ids =
  `G7AlarmLevel.index` (0–4).
- Plain warning channel `insulink_alarm_warning` (default sound) for the
  non-glucose warnings.
- Connection-lost id `101` (cleared on the next reading via `onReading`).
- Expiry id `100`, one-shot, **persisted per-sensor** in `G7Store` so it fires
  once even across service/app restarts.

Channel ids, importance and flags are fixed; only the user-facing channel
name/description are localized. Android freezes a channel's displayed name at
creation, so a later locale change won't rename existing channels (acceptable —
not a regression).
