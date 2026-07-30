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

Because we own the player, **swiping the notification away stops the tone**
(`_silenceWhenDismissed`): the tone is tied to its notification id and the shade
is polled every 400 ms while it plays — `flutter_local_notifications` has no
dismissal callback on Android, so `getActiveNotifications()` is the signal.
Tapping the notification (auto-cancel) silences it the same way.

## Two silent modes

`SilentMode` (`ProfileSilentState`) is a tri-state, not a flag:

| Mode | Notification | Vibration | Tone |
|------|--------------|-----------|------|
| `off` | ✓ | ✓ | ✓ |
| `tones` | ✓ | ✓ | — |
| `all` | — | — | — |

`mutesNotifications` gates every `show()` call; `mutesSound` gates the tone at
the two call sites (`check` / `checkAdvisory`) — **not** inside `_playAsset`, so
the settings-page test alarm keeps previewing the sound as it always did.

The non-glucose warnings (connection lost / expiry / halftime) carry the system
default sound on their channel, which we cannot switch off after the fact —
Android freezes a channel's sound at creation. So `_warningChannel()` posts to a
second, muted channel id (`insulink_alarm_warning_silent`) while tones are muted.

It is persisted as the **two original boolean keys** `silent_mode` + a new
`silent_tones`, not one enum string: the panel coerces `silent_mode` to a bool
and writes the whole settings blob back, so an enum string would return from a
panel save as `false` and silently unmute. `all` outranks `tones` on read.

### A mute can be time-limited

A mute carries an optional `ProfileModeWindow` (`lib/src/profile/profile_mode_window.dart`,
shared with the battery saver — see `docs/BATTERY.md`), persisted under
`silent_window_min` + `silent_until`. Those keys are new and untyped in the panel,
so they pass through its settings blob untouched.

Two properties matter here, and both are safety-relevant:

- **`ProfileSilentState.load()` resolves the window itself.** It returns
  `SilentMode.off` once the run has lapsed, so every alarm call site un-mutes with
  no extra code — `alarms.dart` was not touched for this. The end is a stored
  **timestamp**, so a limited mute also expires correctly while the app is closed.
- **An absent or unparseable window means "no limit", never "elapsed".** A mute
  set before this existed has no window keys at all and must stay muted rather
  than expire the moment the app updates.

The in-isolate `Timer` (`expiryTimer`) exists only so the overview banner
disappears on time while the app is open; nothing depends on it having fired.
Shortening or extending a mute that was already confirmed needs no new biometric
check — neither reduces what the app tells you.

## DnD bypass is order-sensitive (load-bearing)

The alarm channels set `channelBypassDnd: true`. Android **silently ignores**
that flag unless "Do Not Disturb access" was granted **before the channel is
created**. So `ensureDndAccess()` is called from the **UI isolate**
(`G7Controller.start()`), before the service isolate posts its first alarm — the
service isolate has no activity to launch the settings screen.

## Edge-triggered glucose alarms

`check()` maps a reading to a `G7AlarmLevel` (none / low|high × warning|urgent)
and only notifies when the zone gets **worse**. One excursion therefore raises
one alarm per zone it reaches. Three rules, all in `check()`:

1. **Staying in a zone is silent.** Re-evaluating the same zone every 5 min does
   not re-notify.
2. **A zone is only left once glucose clears its line by
   `_alarmRearmMarginMgdl` (10 mg/dL)** — `_sustainedLevel`. With a bare
   threshold comparison, sensor noise alone walks a value across the line
   (69 → 71 → 69, five minutes apart) and every re-entry was a fresh alarm for
   one and the same low, all night. Escalating skips the margin: dropping from a
   low into an urgent low alarms immediately.
3. **Easing off is not news** — `_worsened`. Climbing out of an urgent low back
   into a plain low used to fire a second alarm *on the way up*; together with
   rule 2 that made a single hypo notify four times. Severity ranking is
   `severityOf`, NOT the enum order (that is the notification id).

Entering a low straight from a high (or the reverse) always alarms — that is a
different direction, not a recovery.

The zone is tracked even while silent, so turning silent mode off does not
re-fire an alarm for a value still in-zone — only a fresh crossing fires.

The zone lives in memory in the service isolate, so a service restart (the
25-min no-data watchdog) forgets it and the next reading in-zone alarms again.
Left as is deliberately: after a gap that long, being told the low is still there
is worth one notification.

Thresholds, display unit, and the silent flag are read **fresh from storage on
every call** (`ProfileGlucoseState.loadThresholds()`, `ProfileSilentState.load()`)
so profile changes take effect without restarting the service isolate.

Urgent levels additionally set `fullScreenIntent` + `category: alarm`.

## Channel ids and notification ids

- Glucose alarm channels: `insulink_alarm_{low,high}_{warning,urgent}`, ids =
  `G7AlarmLevel.index` (0–4).
- Plain warning channel `insulink_alarm_warning` (default sound) for the
  non-glucose warnings, plus `insulink_alarm_warning_silent` (no sound) used
  instead while `SilentMode.tones` is on.
- Connection-lost id `101` (cleared on the next reading via `onReading`).
- Expiry id `100`, one-shot, **persisted per-sensor** in `G7Store` so it fires
  once even across service/app restarts.
- Training-detected id `102`, halftime id `103`.
- Advisory pre-warning id `104`, channel `insulink_alarm_advisory` (silent,
  DnD-bypassing like the glucose alarms, own tone `alarm_advisory.wav`).

## Predictive advisory pre-warning (`checkAdvisory`)

A pre-warning that fires *before* glucose reaches a low/high zone, with a
countermeasure. Runs in the service isolate next to `check`, gated by
`NotificationSetting.advisory` (default ON) and silent mode; edge-triggered on
its own `AdvisoryLevel` (`none/low/high`).

- **Forecast** (`advisoryLevelFor`, pure/testable): project the current value +
  trend `_advisoryHorizonMin` (20) min ahead. If predictions are enabled AND the
  cached `PredictionCache` curve is recent (`_predictionMaxAgeMin`), refine the
  low/high extreme with it — else fall back to the trend line. Only the UI
  isolate refreshes the cache, so with the app closed it goes stale and the trend
  line drives it (by design: value + trend are the primary signal).
- Suppressed while glucose is *already* out of range — the real low/high alarm
  owns that; the advisory only pre-warns from in-range.
- **Countermeasure** reuses `ProfileBolusState`: high → `suggestedBolus(carbs:0,…)`
  units; low → `suggestedRescueCarbs(…)` grams (÷ 6 g/tablet for the "Plättchen"
  count), correcting toward the target-range midpoint. The user's correction/carb
  factors are the calibration knob.

Channel ids, importance and flags are fixed; only the user-facing channel
name/description are localized. Android freezes a channel's displayed name at
creation, so a later locale change won't rename existing channels (acceptable —
not a regression).
