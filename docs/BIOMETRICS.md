# The fingerprint gates

Eight actions can ask for the device biometric. Which of them do is the owner's
setting (`profile.security`, `ProfileSecurityState`), stored in secure storage
under `guard_<action>` (snake_case, e.g. `guard_app_entry`; the old camelCase
`guard_appEntry` is still read as a fallback) and read fresh at the gate, so a
switch takes effect on the next action with no restart.

The switches ride in the account settings (`ProfileSettings`), so a new phone
signing in starts with the same gates. That makes one case possible that a
per-device setting never had: the app lock arriving on a phone with neither a
fingerprint nor a screen lock, which could never be unlocked. `locksApp()`
therefore only locks when the device can authenticate at all
(`BiometricAuth.canAuthenticate`); a plugin error counts as "cannot", because a
prompt that cannot be shown is one nobody can pass.

| `GuardedAction` | Where | Default | PIN fallback |
|---|---|---|---|
| `appEntry` | `BiometricLock`, above the whole app | off | yes |
| `bolus` | `InjectionConfirmPage` | on | no |
| `cannula` | `CannulaConfirmation` (pod activation) | on | no |
| `loop` | `LoopModeCard` | on | yes |
| `pump` | deactivate / forget a pod | on | yes |
| `sensor` | forget a sensor | on | yes |
| `silent` | mute everything | on | yes |
| `battery` | battery saver on | on | yes |

The two that reach the body keep the PIN fallback off: driving a needle or
pushing insulin is not something a pocket tap should be able to do. Everything
else allows it so a user with no fingerprint enrolled is not locked out of their
own settings.

`appEntry` is off by default because it guards the data on screen rather than an
action, and an update must not lock somebody out of their own app unasked.

## A cancelled prompt is not a refusal

Reported: the fingerprint went green, the phone was locked in the belief that the
bolus was on its way, and minutes later the screen said "authentication failed".

Android tears the prompt down when the screen goes off and reports that as an
ordinary rejection (`ERROR_CANCELED`). `local_auth` only swallows it when its own
`onActivityPaused` has already run, and that cancel can arrive first, so its
sticky retry misses and an accepted finger comes back as a plain `false`.

`BiometricAuth.confirm` therefore treats a rejection that the app leaving the
foreground explains as no answer at all: it waits for the user to come back and
asks once more. Only a "no" given with the app in front of the user counts as one,
and the retry is bounded at one so nothing can prompt in a loop. A pull of the
notification shade (`inactive`) is deliberately NOT an interruption: the app is
still on screen, so the refusal was real.

Nothing was ever delivered in that window. There is no notification for a bolus on
its way, by design: the only signals are in the app (`SendingBolusCard`, the
running-bolus card, the sticky refusal notice), plus the pod's own beeper.

## Prompts queue

The platform shows one sheet at a time and answers a second call with "already in
progress", which arrives as the same plain rejection. The app lock and a gate can
both be woken by one unlock, so `BiometricAuth` serialises prompts process-wide
and the second one waits instead of losing.

## The app lock

`BiometricLock` wraps `AppPage` inside `AuthGate`, so it applies only once past
sign-in. It arms on the way out (`onHide`) rather than on the way in, so the lock
is already in place while the app is away and the task switcher shows the lock
screen instead of the last glucose reading. Both edges re-read the setting rather
than caching it.

A paused app renders no frames, so the lock arming is only visible on the way back
in. That is what `test/auth/biometric_lock_test.dart` asserts: come back, get
asked; refuse, stay out.
