# Offline and without an account

The app reads sensors, raises alarms and drives the pod over Bluetooth only, so
it keeps working for days without a network. What needed care is what happens
to the data in the meantime, and getting it to the account afterwards.

## Guest mode (no account)

"Continue without an account" on the sign-in page sets `guest_mode`
(`auth/guest_mode.dart`) and `AuthGate` lets the app open. Everything is
recorded locally as usual. `Request.send` does not even attempt an endpoint that
needs a session (anything but `/signin/`, `/signup/`, `/refresh/`): its 403 would
clear the session and throw the guest back to the sign-in page.

The profile shows `ProfileGuestBox` instead of the account card, with "Sign in
or sign up". Signing in from there runs `OfflineHandover` around the usual
sign-in pull:

1. `prepare` marks every replace-all collection unconfirmed in the
   `SyncLedger`, so the pull MERGES the account's copy with the local one and
   pushes the union, instead of replacing what was recorded offline.
2. `AccountSync.pullAll` runs as on any sign-in.
3. `finish` pushes what merges on pull but has no ledger (settings, HbA1c,
   Google Health days, pulse, events) and ends guest mode.

Glucose needs nothing here: the backlog below uploads the whole archive. The
pod and sensor mirror themselves on the next resume or reading; the basal
queue is persisted already.

## Changes that never reached the account (`SyncLedger`)

The nutrition, sport and inventory pulls replace a collection with the
account's copy. Each sync only guarded a push still in flight, in memory, so a
push that failed (offline, or no account) was forgotten and the next pull
reverted the change. Every collection push now marks `sync_dirty.<collection>`
on disk and clears it only when the account answers `success`. A pull of a
marked collection merges (local wins on the same key) and pushes the union.

Known cost: an item deleted while offline comes back once on that merge.

## Glucose uploads (`GlucoseBacklog`)

`GlucoseSync.queue` holds unsent readings in memory and caps them at 5000, so a
long outage plus a service restart lost them for the account (the device kept
them). The backlog keeps `glucose_sync.uploaded_through`, the newest epoch minute
the account accepted, and every 15 min (from the service watchdog) sends the
archive past it oldest first in chunks of 500, moving the mark per accepted
chunk. Without a mark it starts at the archive's 90 day retention.

## Still needs a network

The forecast line, barcode lookups (OpenFoodFacts), map tiles behind a route,
and the data backup's account part.
