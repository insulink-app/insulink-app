# UI performance

What made the app stutter, and the rules that keep it from coming back. All of
these were found by reading the build/paint path, not by profiling — if you have
a device, `flutter run --profile` with the performance overlay is still the way
to confirm a change.

## The archive is parsed from a string — never per build

`CgmStore` keeps the long-term glucose archive as one comma-separated
`minute:mgdl` chunk per day. `archiveRange` used to `_decodeIntMap` every day it
touched on **every call**, and the call sites are all inside `build`:

- the overview asked for `byTime` four times per build (the empty check, the
  chart, and each Y-axis bound),
- `OverviewTimeInRange` reads the last 24 h,
- each of the six analysis views reads `statsArchive` — seven day-chunks, up to
  1440 points each at the Libre's 1-minute cadence.

So a rebuild could re-parse tens of thousands of points. Two fixes:

- `CgmStore._histDays` memoizes the decoded chunk per day. It stays coherent
  because `_archiveAddAll` merges into the same map instance it re-encodes, and
  `reload()` — the existing point at which the isolate adopts another isolate's
  writes — clears it. `archivePrune` drops the day it removes.
- The overview reads `byTime` **once** per build and hands the map down.

Rule: treat `archiveRange`/`byTime`/`statsArchive` as an expensive read. One per
build, passed down — never called twice in the same widget tree.

## An animation inside a chart re-lays-out the whole chart

The latest-reading marker on the overview is an fl_chart *dot painter*, so
changing its ripple phase rebuilds the entire `LineChart` — axis label widgets
included. Driven straight off the `AnimationController` that was a full chart
relayout at the display's frame rate, permanently, on the app's home screen.

`OverviewChart` now samples the controller into a `ValueNotifier` in 32 steps
(`_pulseSteps`, ~15 Hz over the 2.2 s ripple). The ring grows ~0.7 px per step,
so it still reads as continuous. The detail-page chart does not pulse at all.

Rule: before animating anything that lives *inside* a chart, check what the
animation rebuilds. If it has to be perfectly smooth, draw it as an overlay
above a static chart instead.

## Scroll caching on the tab pages

The four tab pages are `ListView`s of a handful of large, expensive sections.
Flutter's default 250 px cache drops a section the moment it leaves the viewport
and rebuilds it on the way back — which is what made scrolling up and down
stutter. They now pass `scrollCacheExtent: ScrollCacheExtent.viewport(1.5)`, so
a section survives the length of a scroll gesture. Memory cost is negligible at
this section count; don't copy it onto a long `ListView.builder`.

## Opening a tab must not re-fetch every time

The shell rebuilds a tab body from scratch on every switch, so each body's
`initState` pull ran on **every visit** — six round trips for Sport plus a
Google-Health read. The answers land ~1 s later, get JSON-decoded, rewrite the
stores and `notifyListeners` the whole page. That is the "smooth for a second,
then a hitch, then smooth again" you feel shortly after switching tabs.

`PullThrottle` (`request/pull_throttle.dart`) gates those on-open pulls to once
per 5 min per key, keyed at module scope so the stamp survives the body being
destroyed. The stamp is taken *before* the pull, so two quick opens fire once.

Rules:

- On-open (`initState`) pulls go through `PullThrottle`.
- **Pull-to-refresh does NOT** — an explicit user pull always fetches.
- Cold start (`AccountSync` in `main.dart`) is throttled too — see below.
- A best-effort pull that fails still counts as a run; the page keeps what it
  had until the next window. That is the intended trade.

## A sync that changed nothing must not rebuild

The throttle lowers how *often* an on-open pull fires, but when one does fire it
still rewrote the stores, `notifyListeners`'d and rebuilt the page — and the
overwhelmingly common pull brings back **identical** data. Landing mid-scroll,
that pointless rebuild is the short hitch.

`SyncReload.ifChanged(keys, pull, reload)` (`request/sync_reload.dart`)
snapshots **only the keys the pull writes** around the pull and runs the reload
only if one of them changed. No change ⇒ no reload ⇒ no rebuild. Both tab bodies'
`_syncAccount` go through it, so this also covers pull-to-refresh (a refresh that
brings nothing new no longer flashes).

**Watch the caller's own keys, never `readAll()`** — the first cut used a
whole-store compare and *still* lagged, for two reasons:

1. `readAll()` decrypts every secure-storage entry, and the glucose archive
   (`g7.hist.*`, up to ~1440 points/day for weeks) lives in the same store.
   Decrypting all of it twice per sync was itself the hitch.
2. A glucose reading landing from the service isolate every ~5 min changes
   `g7.*`, so the whole-store compare reported "changed" almost every time and
   the reload ran anyway — the guard did nothing.

The watched sets are `SportStore.syncedKeys` and `NutritionSync.syncedKeys`
(assembled from the collection keys each pull rewrites, *excluding* the live
pedometer/route keys). Reading ~8 keys instead of the whole store sidesteps the
archive decrypt, and an unrelated glucose write can no longer force a reload.

### Reload only the state that changed

Even when the guard let a reload through, `_syncAccount` reloaded **all** of its
states (sport + training + cardio) and each `notifyListeners`'d — so one changed
collection rebuilt the whole page up to three times.

`ifChanged` now hands the reload callback the **subset of keys that actually
changed**, and each tab routes it: `SportStore` splits its keys into
`weightSyncedKeys` / `librarySyncedKeys` / `cardioSyncedKeys`, and the body
reloads only the state whose group changed. Nutrition routes the same way across
its three stores. The key→state map is exact (derived from what each `reload()`
reads), so nothing goes stale — a changed collection still reloads its state, and
only that one rebuilds.

That is the "scope each section to its own provider" lever, done at the reload
edge instead of by rewiring every widget's `watch`. If a single section's own
rebuild ever still janks, the remaining lever is genuine provider-per-section
scoping so a state notify touches only its section, not the whole page.

## The double hitch on cold start

`main.dart` renders from local storage, then `_pullAccount` syncs the account and
calls `_reload()` if storage changed — and `_reload()` rebuilds the **whole**
provider tree and app subtree (a generation bump). The account pull rewrites the
glucose history (`g7.hist.*`) on *every* launch, so the whole-store compare always
saw a change and fired that full rebuild a second time — the second hitch on open.

`_preferenceKeys` now drops the `g7.*` entries from the compare. Those are not
preferences — `CgmController`, which sits above the reload point, owns the glucose
data — so ignoring them leaves `_reload()` to fire only for a real settings change
(one made on another device or the panel). A normal launch now reloads once.

## The cold-start sync is the app-open jank — throttle it

A profile (release, performance overlay) put the open hitch on the **UI thread**
with no single red frame — a run of just-too-expensive Dart frames, not GPU. That
is `_pullAccount`: on **every** launch it runs the full `AccountSync` — two whole
`readAll()`s for the before/after diff, plus `GlucoseSync.pullHistory` doing a
`jsonDecode` of the entire server history and an `archiveAddAll` that re-decodes
and re-encodes the touched day-chunks — all synchronous on the UI thread, landing
right on top of the app it just rendered. None of the rebuild-side fixes above
touched it, which is why they didn't move the open hitch.

Two cuts, both narrow:

- **Throttle only the heavy branch, not the whole sync.** The account sync runs
  on **every** cold start (so a settings/panel change made elsewhere lands on the
  next open), but its one expensive branch — re-pulling and re-decoding the
  durable glucose/event history — is throttled to once per 30 min inside
  `AccountSync` (`account_sync.history_last`, stamped in secure storage so it
  survives process death). `AccountSync.historyDue()` decides; the cold-start
  caller passes the result as `pullAll`'s `withHistory`, and a fresh sign-in
  passes `true` (a returning device has no local history yet). The light branches
  (settings, sport, nutrition, inventory, health) are small JSON and run every
  time. An earlier version threw the *whole* sync behind a 30-min throttle, which
  also delayed cross-device settings by up to 30 min — splitting it keeps those
  instant while still skipping the archive decode/rewrite.
- **`CgmStore._set` skips a write whose value equals the cache.** The cache
  mirrors disk, so an equal value is already stored — the replace-all syncs
  re-offer the whole archive on every launch/refresh, and this drops the redundant
  keystore writes for unchanged day-chunks (the encode still runs; only the
  platform write is skipped).

Still open (the next lever if a sync that *does* run still hitches): move
`pullHistory`'s `jsonDecode` + readings-map build into a `compute()` isolate, so
the one heavy parse per window is off the UI thread entirely. Not built yet —
the throttle makes those runs rare, so measure before adding it.

## The chart is the heavy widget

The overview rebuilds on every `CgmController` notify, and on open the service
sends several pings in a row — each rebuilding the fl_chart line. Two cuts:

- **Downsample** (`GlucoseChartSeries._downsample`): a phone chart is a few
  hundred pixels wide, so the Libre 3's ~1440 points/24 h are thinned to ≤400 by
  min/max bucketing — every spike and dip and both endpoints survive, only flat
  runs lose redundant vertices. The G7's ~288 stay under the cap, untouched.
- **`RepaintBoundary`** around the `LineChart`, so the pulsing marker's frame-rate
  repaint doesn't dirty the whole scrolling page.

- **Gate the rebuild on a fingerprint.** The overview rebuilt the fl_chart on
  *every* controller notify, but on open the service fires a burst of pings —
  log lines, connection-state, prediction — that notify WITHOUT changing the
  plotted data, and each re-laid-out the chart (the single hitch ~1 s after open).
  `CgmController.chartRevision` is an O(1) fingerprint of what `byTime` plots
  (session-cache size + newest point + session start + live overlay), and the
  chart sits under a `Selector<CgmController, int>` on it — so a notify that
  didn't move the fingerprint reuses the built chart instead of rebuilding it.
  The fingerprint watches the session cache, not the archive `byTime` reads, so a
  rare archive-only change (a pre-session point from a sensor swap) shows on the
  next reading ping rather than instantly; widen it only if that is ever seen.

## The real cold-start hitch was the Health Connect import (measured)

After the sync throttle and the chart fingerprint, a brief cold-start hitch
remained. A per-frame timing capture (`addTimingsCallback`, release build on
device) pinned it down: the janky frames were **UI-thread bound** (`build`
8–15 ms, once 32 ms; `raster` only 3–5 ms) with two outright **freezes** of
177 ms and 86 ms — and they coincided exactly with a burst of `FLUTTER_HEALTH:
Getting data …` logs. The chart and time-in-range builds measured **under 1 ms**,
so neither was ever the cause.

`_AppLifecycle` fires `_refreshHealth()` from a post-first-frame callback (and on
every resume), which runs a full `GoogleHealthState.refreshIfConnected()` — a
30-day import of ~12 Health Connect metric types (resting HR, SpO₂, sleep stages,
weight…). The plugin deserializes that on the UI isolate, freezing it right after
the app appears. The Sport tab hit the same wall on open.

Fix: the import is **throttled and shared** inside `GoogleHealthState`
(`_autoImportThrottle`, 15 min, stamped in secure storage under
`google_health.last_import`). Every automatic entry point — overview cold
start/resume, Sport-tab open, the periodic metrics timer — goes through it, so
opening one screen doesn't re-import for the next, and a reopen within the window
does no import at all. The tiles render from the persisted archive meanwhile.
`refreshIfConnected` returns whether it actually imported, so callers skip their
follow-up steps import on a throttled no-op. A user **pull-to-refresh passes
`force: true`** and always fetches fresh.

Rule: a Health Connect (or any large platform-channel) read deserializes on the
UI isolate — treat it like the archive decrypt, never on every open. Throttle it,
share the stamp, and let an explicit user action force it.

## Known, not fixed

`AppPageState.build` renders `pageBodies[_selectedIndex].content(context)`, so
switching tabs destroys and rebuilds the whole page (hence the module-level
`_overviewScrollOffset` that the overview uses to restore its position). An
`IndexedStack` would make tab switches free, but it also keeps every body
mounted — `SportBodyContent.dispose` stopping the live Fitbit poll would then
never fire, and the overview's ripple would keep ticking off-screen. Worth doing
only alongside explicit visibility handling in those bodies.
