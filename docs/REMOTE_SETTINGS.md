# Settings from the account

`ProfileSettings.pull` adopts the account's settings blob on every cold start
and at sign-in. That blob can be written from outside this phone: the web
panel, another phone, or anyone holding a stolen session. It lands in the same
secure storage that holds the pod key, the session tokens and the live
automation mode, so it is not trusted as it comes.

## Only known keys

`ProfileSettings.adopt` takes a key only when `collect` would push it
(plus `language` and `theme`, which `collect` leaves out until picked). Any
other key in the blob is ignored, so the blob can no longer write `pod.ltk`,
`authentication_token`, `pod.loop_mode` or anything else outside the settings.

## Held for confirmation

A key `RemoteSettingsReview` lists is not written when its value differs from
the one in use; it is held under `settings.pending_remote` instead:

| Group | Keys |
|---|---|
| Bolus and basal | correction and carb factor, maximum bolus, insulin duration, basal profiles |
| Target range | `glucose_target_low`, `glucose_target_high` (the automation aims at their middle) |
| Automation | the three `LoopSettings` limits, the activity-mode settings, `loop_mode_backup` |
| Alarms | the glucose alarm thresholds, `notifications`, `alarm_sound`, `connection_lost_alert`, silent mode, battery saver |
| Fingerprint prompts | every `guard_*` switch |

`RemoteSettingsCard` (top of the overview) names the groups and asks. Taking
them over needs the fingerprint or device PIN where the phone has one,
regardless of the guard switches, which are among the held settings. Turning
them down pushes this phone's settings back, so the same change is not offered
again on the next start. A held change is wiped by sign-out.

A first sign-in on a new phone therefore asks once: the account's values
differ from the defaults.

## Bounds on read

Whatever was stored, the loaders hold values to their editor's bounds:
`ProfileBolusState.load`, `ProfileGlucoseState.load` (target range),
`LoopLimits.load` (through `LoopSettings`), `BasalProfile.fromJson` (0 to
5 U/h). A confirmed change cannot reach past them either.
