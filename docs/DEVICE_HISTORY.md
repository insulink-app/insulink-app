# Device history (sensors and pods)

The list of every CGM sensor and every pod the account has held, reached from the
history button in the sensor / pump page header
(`lib/src/connections/history/`).

## It is read, not recorded

Nothing new is stored on the phone for this. `SensorSync` and `PumpSync` already
register every device with the account, and discarding one only **stamps**
`discarded_at` rather than deleting the row, precisely so the row stays the
user's device log. The endpoints `/sensor/history/` and `/pump/history/` were
already there (the panel reads the same two).

The consequence worth knowing: the history is per ACCOUNT, so it survives a
reinstall and is the same list the panel shows, but a device paired while signed
out never reaches it.

## The two things a record does not say

`DeviceHistory.resolve()` exists for these; the rest is decoding.

**When the device started.** Not `registered_at` — the app POSTs the
registration once the identity is complete, and a restore re-registers a device
that has been running for hours. The blob's own `sensor_start` / `activated_at`
is the start; `registered_at` is only the fallback for a record too old to carry
one. `expires_at` is anchored on the start, so `expires_at - registered_at` is
not a lifetime.

**When it came off.** No record says so, and expiry alone is wrong: a sensor
pulled off on day three keeps its full ten-day expiry, so two devices would read
as active at once. A device ended at whichever came FIRST of:

- its expiry,
- the moment the user said it was gone (`discarded_at`),
- the start of the device that replaced it.

None of those and a future expiry means it is still running.

**One row per physical device.** A reinstall restores the running device and
registers it again, so the same hardware holds several rows. Deduped on the
device key, earliest registration kept: a sensor's `resolved_key`, and for a pod
its **activation moment** — a pod's `unique_id` is derived from the controller
and is therefore identical for every pod this app has ever activated, so it
identifies nothing.

## Kept in step with the panel

`insulink-panel/src/lib/sensor.ts` and `src/lib/pump.ts` implement the same three
rules over the same endpoints. They are deliberately duplicated rather than
shared (different languages, no shared runtime) — change one and change the
other, or the two screens will disagree about how long a sensor was worn.
