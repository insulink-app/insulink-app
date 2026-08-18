# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A from-scratch **CGM BLE reader** (Flutter + Rust) for two sensors: the **Dexcom
G7** (fully working) and the **FreeStyle Libre 3** (in progress — see
`docs/LIBRE3.md`). It reimplements each sensor's proprietary pairing/auth and
reads live + historical glucose without the official apps. It also drives the
**Omnipod DASH** pump (`lib/src/pump/`, `docs/OMNIPOD.md`).
**AGPL-3.0** — the pump driver derives from AndroidAPS (AGPL-3.0); the CGM
handshake code derives from [Juggluco](https://github.com/j-kaltes/Juggluco) and
stays GPL-3.0. See `NOTICE` for which file is which, and keep pod protocol code
OUT of `insulink-api` (AGPL §13 would make the API a network service that must
publish its source). Interoperability/research project — not a medical device.

The two sensors share everything above the wire layer via a `CgmConnection`
strategy (`lib/src/cgm/cgm_connection.dart`): both decoders emit a `CgmReading`,
and the controller/store/service/chart/stats/alarms are sensor-agnostic. The
active sensor is `CgmStore.sensorType`; the service isolate builds the matching
`CgmConnection` (`G7Connection` today, `Libre3Connection` once the Libre BLE
handshake lands). Per-sensor watchdog cadence is `CgmTiming`. The Libre 3 wire
code lives in `lib/src/libre3/` (NFC activation + glucose decode done; BLE
security handshake is vendor-blob-gated — `docs/LIBRE3.md`).

## Commands

```bash
# Rust crypto core — fast iteration + validation (byte-exact KATs vs Juggluco)
cd rust && cargo test && cd ..          # run all jpake tests
cd rust && cargo test --lib jpake -- --nocapture
cd rust && cargo build && cd ..         # host build (no Android needed)

# Regenerate the Dart<->Rust bridge AFTER editing rust/src/api/*
flutter_rust_bridge_codegen generate    # rewrites lib/src/rust/ + rust/src/frb_generated.rs

# Build / run the app (Android-first; arm64 single-ABI is fastest)
flutter build apk --debug --target-platform android-arm64
flutter run

flutter analyze                          # lint
```

The Rust core is **pure Rust** (RustCrypto `p256`) — no cmake/ninja/NDK env
vars needed anymore. `flutter build` runs `pub get` automatically.

**flutter_rust_bridge version must be IDENTICAL in three places**, or
`RustLib.init()` fails its version check at runtime — and because that init runs
in the foreground-**service** isolate before `connect()`, the whole app looks
dead (no `scanning for DXCM…`, no updates) while the UI still launches. The three:
`pubspec.yaml` (`flutter_rust_bridge:`), `rust/Cargo.toml` (`flutter_rust_bridge = "=…"`),
and the generated code (`rust/src/frb_generated.rs` `FLUTTER_RUST_BRIDGE_CODEGEN_VERSION`).
To bump: change both manifests, install the matching codegen CLI
(`cargo install flutter_rust_bridge_codegen --version X`), rerun `generate`,
then `cargo test` to confirm the KATs still pass. Never bump pubspec alone.

Note: on-device build/install/run is typically driven by the developer (watch
`adb logcat | grep -i flutter`); the in-app log pane mirrors each handshake step
and is copyable via the "Kopieren" button. **Test on-device with profile/release,
not debug** — a debug build (JIT + Dart VM service) often hangs on the splash
screen when run standalone/unplugged; release/profile (AOT) run fine.

## Code style (follow these — they override default habits)

- **Object-oriented.** Model behaviour as classes with state + instance methods.
- **Avoid static functions** — they work against OO. Prefer an instance on the
  object that owns the data. Legitimate exceptions kept on purpose: `static const`
  values, `@pragma('vm:entry-point')` top-level callbacks (`startCallback`), and
  async **factory readers** that construct the object they return
  (`ProfileGlucoseState.load()`/`.loadThresholds()`, `ProfileSilentState.load()`)
  — these are the documented cross-isolate bridge for `ChangeNotifier` state the
  service isolate can't observe.
- **No one-line `if`s.** Always use braces, even for a single statement.
- **No comments inside function bodies.** Keep functions short enough that they
  read on their own; put the explanation in a doc comment ABOVE the function.
- **All code comments in English.** Every comment and doc comment (`//`, `///`)
  is written in English — no German (or other languages). Only user-facing
  strings are localized (see below); the code itself, including its comments, is
  English. If you touch a file with a German comment, translate it while you're
  there.
- **Short functions and classes.** Split them when they grow; one job each.
  Rule of thumb: **no Dart file over 150 lines**, and methods ideally **5–10
  lines** (split anything longer). Treat these as hard smells, not hard limits.
- **Descriptive, unique names** for classes and functions — no generic or
  duplicated names. **No one-letter variable names** (loop counters included);
  the name says what it holds.
- **Avoid boilerplate.** No scaffolding "for later", no repeated patterns that a
  shared helper/widget removes — extract the repetition instead of copying it.
- **2-space indentation.**
- **Localize everything.** No hard-coded user-facing strings — every displayed
  string goes through the localization layer (`assets/locales/*.json`).
- **JSON uses `snake_case` keys.** The locale files are **nested objects** per
  section (`{"profile": {"glucose": {"target": …}}}`); both loaders flatten them
  on load to the dot-separated keys the app looks up (`profile.glucose.target`)
  — so call sites are unchanged (`LocaleText('profile.glucose.target')`). A node
  that is BOTH a label and a prefix carries its own value under a `_` key (e.g.
  `profile.glucose._` = "Glucose" alongside `profile.glucose.target`).
- **Package by feature, NOT by layer.** Group folders by what the code is ABOUT
  (the feature/domain), never by technical type. Each feature folder holds its
  state, widgets and logic TOGETHER (e.g. `profile/glucose/` has the glucose
  state class AND its editor widgets). **Do NOT create type-layer folders** like
  `state/`, `widgets/`, `models/`, `services/` or `controllers/`. The top level
  is already feature-based (`overview/`, `sensor/`, `statistics/`, `profile/`,
  `injection/`, `hba1c/` = the lab-value history, `cgm/` = the shared CGM read
  pipeline + the Dexcom G7 wire code
  under `cgm/protocol/`, `libre3/` = the FreeStyle Libre 3 wire code); cross-cutting
  shared code lives in `base/` (shared widgets/primitives — including
  `measurement_chart`/`measurement_row`/`measurement_entry_sheet`, the
  dated-decimal history UI that weight and HbA1c both render), `localization/`,
  `theme/`. Within a large feature, subfolders are themselves features/sub-domains
  (e.g. `cgm/protocol/`, `profile/notifications/`), never technical layers.
- **Document accumulated knowledge as individual markdown files under `docs/`** —
  one focused topic per file, rather than letting it pile up only in code.

## Architecture

Two layers, bridged by flutter_rust_bridge (FRB):

- **Dart** owns BLE, the handshake state machine, parsing, persistence, and UI.
- **Rust** (`rust/src/api/jpake.rs`) owns only the crypto that can't be done in
  Dart: EC-JPAKE (secp256r1 + SHA-256) and the ECDSA proof-of-possession. It is
  a faithful port of Juggluco's `ecJPake.cpp` — **the G7 uses a custom raw-point
  wire framing (64+64+32 bytes), NOT mbedTLS's TLS encoding**, so the framing,
  party labels, hardcoded round-3 exponent, and `SHA256(X)[0:16]` key derivation
  must match Juggluco byte-for-byte. The `#[cfg(test)]` KATs verify exactly this
  against vectors captured from Juggluco's compiled reference; treat them as the
  contract — if you touch `jpake.rs`, keep them green.

The `lib/src/cgm/` module is grouped into subfolders by concern:
`protocol/` (the wire/codec/handshake/pipeline core — `uuids`, `opcodes`,
`display_certs`, `ble_transport`, `auth_session`, `device_info`, `glucose`,
`connection`), `service/` (the background foreground-service host + alarms —
`cgm_service`, `alarms`), and at the root the persistence (`cgm_store.dart`), the
UI controller (`cgm_controller.dart`) and the sensor-agnostic contract
(`cgm_connection.dart` — `CgmConnection`/`CgmReading`/`CgmTiming`/`SensorType`).
The `protocol/` files hold the **Dexcom G7** wire code and are the fragile,
byte-exact core — relocate them if needed, but don't restructure their logic. The
**FreeStyle Libre 3** wire code is the sibling `lib/src/libre3/` folder.

### The handshake (`lib/src/cgm/protocol/auth_session.dart`)

GATT (service `f8083532-…`): control `…3534`, auth `…3535`, backfill `…3536`,
J-PAKE/cert bulk `…3538` (see `uuids.dart`). Two paths:

- **Fresh pair**: EC-JPAKE rounds 0/1/2 (`0x0A`, index byte on `3535`, 160-byte
  payloads on `3538`) → AES key-confirmation (`0x02→0x03→0x04→0x05`) →
  display-certificate exchange (`0x0B`, certs in `display_certs.dart`) →
  ECDSA proof-of-possession (`0x0C`, signed by the embedded key in `jpake.rs`)
  → OS bond → glucose. `statusReply 05 01 02` = fresh pair.
- **Reconnect** (`runReconnect`): with a stored session key, skip everything
  except the AES key-confirmation. `statusReply 05 01 01` = reconnect.

Two BLE subtleties that are load-bearing (don't regress them):
1. **Order in each J-PAKE round**: write `{0x0A,n}`, the SENSOR sends its
   160 bytes FIRST, then we send ours. Sending early → the sensor disconnects.
2. **Stream races**: the sensor replies instantly. `3538` is read via a
   continuously-filled buffer (`BleTransport.takeJpake`), and auth-stream
   `_awaitAuth` futures are attached BEFORE the triggering write. Broadcast
   streams don't replay, so listen-after-write loses the reply.

Handshake gotchas (learned the hard way):
3. **`key-confirmation mismatch` is a downstream symptom, not the bug.** It means
   the derived session key is wrong → the AES key-confirmation fails. The real
   cause is almost always **connecting to the WRONG sensor** (a neighbour's G7,
   or an old one, that advertised first) — the stored key / pairing code don't
   match it. Fixed by **device pinning**: `CgmStore.deviceId(serial)` stores the
   paired sensor's BLE remoteId and `scanForSensor(wantedId:)` matches ONLY that
   device. (A corrupted/misaligned J-PAKE round can cause it too — hence
   `clearJpakeBuffer()` before each `run()`.) `G7HandshakeException` marks it as
   transient/retryable.
4. **The round ZKP routinely does NOT verify** under our raw-point wire framing,
   yet the handshake still completes — so `setSensorRound1/2` returning false is
   logged and IGNORED, exactly as Juggluco does. Do NOT turn it into a hard
   error: aborting drops the link before we send our payload, and the G7 then
   rejects the immediate reconnect.

### Background operation (foreground service)

Reading must continue while the app is backgrounded OR fully closed (swiped from
recents). On Android the activity's Dart isolate — and the BLE link it owns —
dies when the activity is destroyed, so the whole read pipeline runs in a
**second Dart isolate hosted by an Android foreground service** via
`flutter_foreground_task` (9.x).

- `connection.dart` (`G7Connection`) is the UI-free read pipeline: find device →
  connect → `runReconnect`/`run` → stream live EGV + backfill → parse →
  persist. **Steady-state reconnects use `autoConnect`** (connect straight to the
  cached `BluetoothDevice.fromId(deviceId)`, no scan) — see "Reconnect path" in
  gotcha #4 below; scanning is only for first pairing, the first connect of each
  process, and the fallback. It only depends on the already widget-free layers (`BleTransport`,
  `G7AuthSession`, codecs, `CgmStore`) and reports out via callbacks
  (`onLog`/`onReading`/`onUpdate`/`onConnectionState`). It used to live inline
  in `_ReaderPageState`.
- `cgm_service.dart`: the `@pragma('vm:entry-point') startCallback` +
  `CgmTaskHandler` that runs `G7Connection` inside the service isolate. It
  **must `await RustLib.init()` again** (fresh isolate ⇒ fresh Rust core),
  also re-inits the alarm manager + store (fresh isolate), updates the
  notification text with the latest value, pushes updates to the UI with
  `sendDataToMain`, fires glucose/expiry/connection-lost alarms, and drives
  every recovery path from `onRepeatEvent` (a 30 s watchdog). `_ensureReady()`
  is idempotent so the watchdog can rebuild a startup that *threw* (otherwise a
  single `onStart` failure left a dead service with a null `_conn` that nothing
  revived). The watchdog escalation ladder: not-connected → reconnect (the
  normal resting state); `isConnecting` past `_connectStuckAfter` (7 min — an
  armed autoConnect legitimately waits up to one G7 cycle for the sensor to
  advertise) → force-reset; connected-but-silent past `_staleAfter` (12 min) → drop the
  half-open link; no data at all past `_restartAfter` (25 min) → restart the
  whole service (fresh isolate + Rust core + BLE stack). Health is measured by
  **time-since-last-reading, not BLE connection state** (which is normally
  "disconnected" between the G7's 5-min deliveries).
- The UI layer is in `cgm_controller.dart` (`CgmController`), not `main.dart`
  — see "App / UI layer" below. `flutter_blue_plus` works in the service
  isolate because FFT registers plugins on its background engine.

Load-bearing background gotchas (don't regress):
1. **FGS type `connectedDevice` requires a held Bluetooth runtime permission**
   on Android 14+ (target SDK 34+). The scan now runs in the background isolate
   which can't show dialogs, so `main.dart` requests `BLUETOOTH_SCAN/CONNECT`
   (via `permission_handler`) and aborts BEFORE `startService` if denied —
   otherwise native `startForeground` throws `SecurityException` and the service
   sticky-restarts in a loop.
2. **Cross-isolate store cache**: `CgmStore` is backed by `flutter_secure_storage`
   but serves synchronous getters from an in-memory cache loaded via `readAll()`.
   That cache is per-isolate, so the UI must `CgmStore.reload()` (a fresh
   `readAll()`) to see the service's writes (done on the `update` ping and on
   resume).
3. Manifest needs `FOREGROUND_SERVICE_CONNECTED_DEVICE` + `POST_NOTIFICATIONS` +
   the `connectedDevice`-typed `com.pravera.flutter_foreground_task…ForegroundService`.
4. **Reconnect path = `autoConnect`, NOT scanning (the fix for the dropping link
   + the manual-Bluetooth-restart symptom).** The old design scanned on EVERY
   reconnect; the G7 drops its link after each ~5-min delivery, so that scanned
   24/7 and **wedged the native Android-13+ BLE scanner** — `startScan` then
   silently returns 0 results and only a manual Bluetooth toggle recovered it.
   Mirroring Juggluco, steady-state reconnects now skip the scan: connect
   directly to the cached `BluetoothDevice.fromId(deviceId)` with
   `autoConnect: true` (`connectGatt(autoconnect=true, TRANSPORT_LE)`), re-armed
   explicitly by the watchdog on each disconnect. This removed the connect
   timeouts and the scanner wedge. Load-bearing details:
   - **autoConnect to a COLD `fromId` only fires once the OS has SEEN the device
     in THIS process** — otherwise it silently never connects (the "an app update
     / service restart killed autoConnect" failure: a fresh isolate that never
     scanned). So `connection.dart` gates autoConnect on `_scannedThisProcess`:
     the FIRST connect of every process scans (teaching the OS the address), and
     only then do in-process reconnects autoConnect. Verified instinct of the user.
   - **The scan path then autoConnects too — it does NOT direct-connect.** The
     scan only teaches the OS the address; the connect that follows is armed with
     `autoConnect: true` like every other. A direct connect's hard 35 s timeout
     loses against the G7's ~1 s advertising window: the window is already closed
     by the time the scan result is delivered and the bond checked, so it fails
     with **147 GATT_CONNECTION_TIMEOUT** and the cycle repeats forever.
   - **FBP's autoConnect auto-rearm is broken (#528)** — never rely on it; the
     watchdog re-issues `connect()` per disconnect (Juggluco's pattern).
   - **No short timeout in autoConnect mode** — `connect(autoConnect:true)` returns
     immediately and legitimately waits until the sensor next advertises (up to
     ~one cycle); a 35 s timeout would abort every cycle. `_armAutoConnect`
     (`ble_transport.dart`) passes `mtu: null` (FBP requires it with autoConnect),
     awaits the `connected` state, then `requestMtu(512)` manually (else EGV frames
     split across 20-byte notifications and parse to nothing).
   - **The reconnect backoff applies to BOTH paths.** autoConnect finds the device
     via the OS's internal background scan, which is subject to the SAME Android
     "scanning too frequently" throttle — so re-arming back-to-back can stall it.
   - **Scan fallback**: after `_maxAutoConnectFailures` (2) cycles that armed but
     never streamed, scan once to re-discover the address (the remoteId may have
     changed), then resume autoConnect. Reset to 0 the moment a cycle streams.
   - *Scanning* (first pair / first connect / fallback) can still be throttled
     while the screen is off (FBP issue #924), so a cold reconnect may complete
     only on the next screen-on; an already-open or autoConnect-armed link keeps
     streaming. Android delivers **no results for an UNfiltered scan while the
     screen is off** — `scanForSensor` passes the stored remoteId as a native
     `withRemoteIds` filter so background results come through.
5. **The G7 connect→deliver→disconnect is NORMAL.** It connects briefly (~every
   5 min), pushes the current EGV + backfill, then drops the link itself — so
   `link dropped` right after `connected — streaming` is expected, and the 30 s
   watchdog reconnecting is correct, not a bug.
6. **The G7 rejects rapid in-process reconnects** (`REMOTE_USER_TERMINATED`
   status 19 / `GATT_CONNECTION_TIMEOUT` 147). Do exactly ONE clean attempt per
   `connect()` and let the watchdog retry on the sensor's own advertising
   schedule — do NOT tight-loop retry within a single connect.
7. **The SERVICE owns the live band while it runs; the UI defers — no handoff
   message.** The `FitbitHeartRateMonitor` (0x180D live bpm) is hosted in the
   service isolate for the whole life of the service (`CgmTaskHandler.onStart` →
   `_startBackgroundHr`, `knownOnly: true` so it connects only to the bonded band
   and NEVER scans — a scan would fight the G7's scanner). So bpm keeps streaming
   while the app is backgrounded OR fully closed, with no dependence on the dying
   UI isolate to hand anything over (the earlier `hrOwner` lifecycle-message
   design was removed — it never fired on a swipe-close). The UI `_bleMonitor`
   (`GoogleHealthState`) runs ONLY when no service is up, and stands down the
   moment a service `t:'hr'` push arrives — so the two isolates never hold the one
   GATT link at once. Detection/workout services now also add the
   `connectedDevice` FGS type when Bluetooth is permitted (Android 14+ needs it to
   hold the band). **The monitor stands itself down after a failed connect and the
   watchdog tick is its ONLY retry driver** — `_startBackgroundHr` therefore
   re-runs `start()` every tick, not just when it creates the monitor. Guarding
   that call on `_hrMonitor != null` meant one bad attempt at service start (band
   out of range, still held by Google Health) killed live pulse for the whole life
   of the service. The monitor's own `_retryCooldown` is what keeps the re-runs
   from becoming a 20 s connect attempt per tick. The Health-Connect poll (`_maybePollHeartRate`) is the fallback
   and self-suppresses while the band streams. Background HR still requires SOME
   service to be running (a CGM sensor or a workout) — a Fitbit-only user with no
   sensor and no workout would need a dedicated pulse service (a persistent
   notification), deliberately not built.
8. **An in-flight connect owns a real BLE link — publish it BEFORE the awaits, not
   after them.** Both connections used to assign `_transport` only once the
   handshake had succeeded, so for the whole scan (up to 120 s) and the connect +
   handshake, `_teardown` had nothing to disconnect. A watchdog force-reset, a
   `restartService()` or a stop in that window left a live GATT client behind: the
   app then held TWO sensor links and closing the tracked one wasn't enough (the
   user-visible "have to stop several times"). Both now publish the transport at
   creation, and a `_generation` counter (bumped by every teardown) makes an
   abandoned attempt close its own link instead of adopting it.
   - **This hit the Libre 3 hardest**, for two compounding reasons: its link is
     CONTINUOUS, so an abandoned one never drops by itself (a leaked G7 link dies
     within a second when the sensor closes it), and its `connectStuckAfter` was
     3 min — *shorter than its own worst-case connect*. The scan (120 s) plus the
     two handshake attempts (`_handshake` retries the full cert exchange when the
     cached kAuth is rejected: 2 × [35 s connect + 30 s discovery + 40 s
     handshake]) is ~5.5 min, so the watchdog reset healthy attempts on the
     fallback path and — with a zero `reconnectBackoff` — started a new one on the
     very next tick. Raised to 7 min. **Any change to those transport timeouts
     has to be re-checked against `connectStuckAfter`.**

### App / UI layer

The UI is a multi-page app (overview, sensor, statistics, profile, plus
injection/pump stubs) under `base/navigator.dart`, NOT the old single reader
page. `main.dart` is a thin shell: it sets up `MultiProvider` (theme, locale,
glucose/bolus/silent profile state, and `CgmController`) and `MaterialApp`
(`home: AppPage`).

- **`cgm_controller.dart` (`CgmController`)** is the UI isolate's viewer + remote
  control for the read pipeline — a `ChangeNotifier` provided above the page
  tree so overview/sensor/statistics all observe the same data. It owns the
  pairing-code field, the live/cached reading, the current-session chart data
  (`byTime`), device info, the log, and service start/stop. The BLE work itself
  runs in the service isolate (`cgm_service.dart`); this class just mirrors it.
  - **Stale-recovery on launch/resume** (`_recoverIfStale`): `isRunningService`
    can read "running" while the hosting isolate is frozen, so the real signal
    is time-since-last-data. No fresh data within `_staleAfter` (12 min) ⇒
    `restartService()`. Gated by `_restartCooldown` (3 min): a fresh service
    needs up to ~2 min to scan+connect, and restarting back-to-back aborts the
    in-flight scan and trips **Android's "scanning too frequently" throttle**
    (which then returns NO scan results for ~30 min — the multi-hour "0 devices
    found" stall).
  - The DnD-access request (`G7AlarmManager.ensureDndAccess`) and BLE/notification
    permission requests happen HERE in `start()`, before `startService` — the
    service isolate has no activity to show dialogs (see Alarms below).

- **Profile settings** follow one pattern: each setting is a tiny
  `ProfileXState` class (static `load()`/`save()` straight to
  `flutter_secure_storage`) paired with a `ProfileXToggle`/`ProfileXSelection`
  widget. The `profile/` folder is **packaged by feature** — one subfolder per
  setting (`language/`, `theme/`, `glucose/`, `bolus/`, `notifications/`,
  `silent/`, `developer/`), each holding that setting's state AND its widgets
  together; `profile_page.dart` + the shared `profile_toggle_row.dart` sit at the
  root. **The service isolate reads these with `load()` fresh on each check**
  (it can't observe a `ChangeNotifier` across isolates), so a toggle takes
  effect WITHOUT restarting the service. Safety-relevant settings default ON
  (alarm sound, connection-lost). `ProfileSilentState` is a tri-state
  `SilentMode` — mute nothing, only the alarm tones (notification + vibration
  stay), or everything (`docs/ALARMS.md`). Both it and `ProfileBatteryState`
  carry an optional `ProfileModeWindow` (2 h / 8 h / until switched off), so
  their `load()` resolves a lapsed run to "off" and every reader un-mutes /
  un-saves without extra code (`docs/BATTERY.md`);
  `ProfileGlucoseState` holds the unit + the four thresholds
  (urgentLow/low/high/urgentHigh) used by both alarms and formatting.

- **Localization** (`localization/`): `assets/locales/{de,en}.json`, selected
  via `locales.dart`. UI uses the `flutter_localization` widgets, but the
  service isolate / controller has **no `BuildContext`** (and a fresh isolate has
  no `Locales` state), so notification text is resolved via `ServiceStrings`
  (`service_strings.dart`): it reads the persisted `language` key from secure
  storage and loads that locale's JSON from the bundle. The JSON is nested by
  section; `locales.dart` flattens it to dotted keys, while `ServiceStrings`
  walks the path directly (both honour the `_` self-value convention). Keys are
  `snake_case` (`alarm.low.title`), `#` is the placeholder. Details in
  `docs/LOCALIZATION.md`.

- **Statistics** (`statistics/`) read the long-term archive, not the current
  session — see `archiveSince` / `archiveRange` under Data + persistence. Default
  window is 14 d (`CgmController.statsWindow`, clinical AGP).

### Theme & design system (`lib/src/theme/`)

`app_theme.dart` holds both `ThemeData`s; `accent_colors.dart` and
`glucose_colors.dart` are `ThemeExtension`s. **No widget invents a colour** —
needed a value the scheme has no role for? Add the role here, don't hard-code it
at the call site. Full rationale + the measured contrast values: `docs/DESIGN.md`.

The load-bearing parts (regressing any of these is a visible bug):

- **An unset `ColorScheme` role does not fall back sensibly — it aliases to
  another role, wrongly.** `surfaceContainer*` → `surface` (badges become the
  exact colour of the card they sit in ⇒ invisible), `outline` → `onBackground`
  (**white**/black rims on every `OutlinedButton`), `onSurfaceVariant` →
  `onSurface`. So **a role set in one theme MUST be set in the other** — both
  schemes set the same nine; keep that list symmetric (`docs/DESIGN.md` has a
  one-liner to check it).
- **Material's component defaults pick surprising roles**: `TextButton` /
  `OutlinedButton` draw their label in `colorScheme.primary` (the *fill* colour,
  ~4:1 as a label on dark), `IconButton` in `onSurfaceVariant` (the *decoration*
  tone). Both are corrected per theme in `app_theme.dart`.
- **Two accents, same hue, because one colour can't do both jobs on dark**:
  `colorScheme.primary` (`#5A73F2`) is a **fill** only — a button with white text
  on top. `AccentColors.onSurface`, read as `context.accent`, (`#93A6FF` dark) is
  the accent **drawn on** a surface. `primary` as a foreground only reaches ~4:1.
  On light both are the same indigo. Don't "simplify" them back into one, and
  don't lighten `primary` into the M3 light-primary/dark-onPrimary pattern — that
  was tried and reverted (it recolours every filled button).
- **Three foreground tones**: `onSurface` = text + **bare controls** (`IconButton`,
  `TextButton` — no container of their own, so no tint); `context.accent` =
  affordances that carry the brand and have a shape to carry it (outlined-button
  labels, chevrons, tappable banners, summary-tile glyphs); `onSurfaceVariant` =
  anything that only informs. **Never give decoration the accent** — that split is
  what makes a control distinguishable from a glyph.
- **Shape says affordance**: a neutral filled circle is a row's *identity* badge
  and is never pressable; a bare glyph is information (or a tile that is itself
  the control); a filled rounded-rect with a label is the button. Tinted square
  faces on `IconButton`s, and badges inside `SportSummaryTile`, were both tried
  and rejected — don't reintroduce them.
- **The light ladder steps DOWN** (the page is the brightest thing), the dark one
  steps up — so "raised" is *darker* than its box in light. Dark neutrals take
  their hue from the website's palette but lifted a rung and much less saturated.
  Every slot (`scaffold`/`appBar`/`bottomNav`/input fill/`divider`) pulls the SAME
  named rung in both themes — keep it that way, and never inline a hex or a
  `Colors.white` there.
- **No hard-coded semantic colour.** `StatusColors` (`context.danger` /
  `context.warning` / `context.positive`) carries what `ColorScheme` has no role
  for: error TEXT (`error` itself is a fill and only makes ~4:1 as a label on
  dark), amber, and green. Same fill-vs-foreground rule as the accent. Reds and
  green come from the family `GlucoseColors` already speaks, so the app has ONE
  red — but they stay separate tokens: glucose is its own language and must not
  move when a delete button does.
- **`BrandTints`** (`scheme.tintPanel` 0.08 / `tintSelected` 0.14 / `tintLine`
  0.20) replaces the nine hand-guessed alphas that used to tint panels. A **scale**
  (progress fill, disabled dimming) is not a tint — its alpha carries information.
- `dividerColor` doubles as the box border (`OverviewSection`), so it must stay
  close to `surface` or every card gets a hard ring.
- **A local `styleFrom` silently beats the theme.** Pass only genuinely local
  values (size, shape) — this is why one page's `OutlinedButton` ignored a global
  fix for a whole round.
- **No `SnackBar`s** — all were removed and none come back. They cover content,
  time out whether or not they were read, and appear away from what the user
  touched. Pick per site: a **standing condition** (denied permission) goes into
  the state and is rendered by the UI that shows state (`connectFailure`); a
  **dead end that must be answered** gets the app's `Alert` (`alert/alert.dart`);
  a plain **confirmation** goes ON the control that was pressed (icon/label →
  checkmark for ~2 s, `Timer` cancelled in `dispose`). A success often needs no
  message — the page behind it already changed. Safety-relevant failures (bolus)
  are **sticky, never timed**. Details + all five replacements: `docs/DESIGN.md`.
- **`isScrollControlled: true` ALWAYS goes with `useSafeArea: true`.** The first
  removes Flutter's 9/16-height cap so the sheet grows with its content; without
  the second there is no `SafeArea` at all, so a tall sheet slides under the
  status bar / notch (reported on the injection sheet). All 18 scroll-controlled
  sheets carry both — keep the pair together when adding one. Sheets without
  `isScrollControlled` are capped at 9/16 and need nothing.

### Alarms & notifications (`cgm/service/alarms.dart`)

`G7AlarmManager` runs in the **service isolate** (alongside `CgmTaskHandler`) so
alarms fire with the app closed. `init()` must be called once per isolate
(mirrors `RustLib.init()`).

- **Glucose alarms are edge-triggered**: `check()` maps the reading to a
  `G7AlarmLevel` (none/low|high × warning|urgent) and only notifies when the
  zone gets WORSE — one excursion, one alarm per zone it reaches. A zone is only
  left once glucose clears its line by a 10 mg/dL margin (or a value resting on
  the threshold re-alarms with every wobble), and easing off (urgent low → low)
  says nothing; escalating always fires at once. The zone is tracked even while
  silent, so turning silent mode off doesn't re-fire an alarm for a value still
  in-zone — only a fresh crossing fires. Thresholds + unit are re-read each call
  (no restart needed). Details: `docs/ALARMS.md`.
- **The alarm TONE is NOT played by the notification channel** — the channels
  are `playSound: false`. The sound is played manually via `audioplayers` on the
  **ALARM audio stream** (`usageType: alarm`) so it obeys the alarm-volume
  slider (not the notification slider, which can be 0) and sounds through a
  silenced ringer / DnD / screen-off, like Dexcom. Distinct
  `alarm_low.wav`/`alarm_high.wav` (`assets/sounds/`). Audio is best-effort; the
  visual notification fires regardless.
- **DnD bypass is load-bearing and order-sensitive**: the channels set
  `channelBypassDnd: true`, but that's silently ignored unless "Do Not Disturb
  access" was granted **BEFORE the channels are created**. So `ensureDndAccess()`
  runs from the UI isolate in `CgmController.start()`, before the service isolate
  posts its first alarm.
- Urgent levels add `fullScreenIntent` + `category: alarm`. Non-glucose warnings
  (connection-lost after 15 min, sensor-expiry within final 24 h) use a plain
  default-sound channel; expiry is one-shot **persisted per-sensor** in the store
  so it fires once even across restarts.
- The ongoing FGS notification shows the current value + trend arrow
  (`trendArrow`, same 5 buckets as the overview readout), gated by
  `ProfileLiveNotificationState`.
- Full design (audio stream, DnD ordering, channel/notification ids) in
  `docs/ALARMS.md`.

### Data + persistence

- `glucose.dart`: EGV (`0x4E`) and backfill (`dexbackfill`) decoders. Packed
  little-endian; `mgdL` is a 12-bit field. Glucose/backfill are **plaintext**.
- `device_info.dart`: parses `0x4A`/`0x52`/`0x22` (firmware, software #, serial,
  session/warmup length, hardware/algorithm version, battery) + `0x32`
  calibrationBounds (read-only: permitted?, last cal BG/time) + algorithm-state
  labels. Requested right after auth in `connection.dart`. These metadata replies
  are **best-effort** in the brief reconnect window — version is static so it's
  only re-requested while unknown, to leave room for battery/cal.
- **Backfill** (`requestBackfill`, control `0x59`): requested once per connect
  after the first EGV. Gap-based — full last 24 h until ~a continuous day is
  cached, then only the gap since the newest stored point. Request it
  **immediately** (the link drops within ~1 s; deferring loses it).
- **Calibration is read-only.** The `0x32` status is parsed/shown; the `0x34`
  calibrate WRITE is NOT implemented — its payload isn't verified in any open
  source (opcode confirmed via DiaBLE; the G6 frame is `34 ‖ glucose(LE16) ‖
  dexTime(LE32) ‖ CRC16`, unverified for G7). The G7 is factory-calibrated and
  works fully without it; a verified BLE-HCI capture is needed before sending it.
- **Two glucose stores, different time bases.** The per-sensor `loadReadings`
  history (`CgmController.byTime`) is keyed by **seconds-since-session-start**,
  capped, and reset on a new sensor — it's the current-session overview chart.
  Separately, `archiveAddAll`/`archiveRange` keep a **long-term archive keyed by
  absolute epoch-minute** (`millisecondsSinceEpoch ~/ 60000`, bucketed per day)
  that spans sensor swaps, stops and reconnects — the basis for the statistics
  page (`archiveSince(window)`). Writes are serialized through `_archiveGate`.
  `forgetSensor` clears the current session but KEEPS the archive, so statistics
  survive a sensor change.
- `cgm_store.dart` (flutter_secure_storage, synchronous getters served from an
  in-memory cache loaded via `readAll()` on `open()`/`reload()`): per-**serial**
  keys for session key,
  glucose history, device info, sensor start, the expiry-notified flag, and the
  latest EGV
  (`saveLatest`/`loadLatest` — value+trend+state, so the headline number is
  restored on launch, not just the last history point). The serial is NOT used
  by the protocol (the pairing code is the only auth secret) — it is purely the
  persistence key enabling reconnect, cached chart/info, and auto-connect.
  **There is no serial input field** (removed): the only user input is the
  pairing code. `G7Connection` resolves the key to the sensor's BLE id
  (`device.remoteId.str`) once a device is found and stores it as `resolvedKey`;
  the pipeline persists under `_persistKey`, the UI reads cache under
  `resolvedKey`, and pinning falls back to `deviceId(resolvedKey)`. Writes happen
  in the **service isolate**; the UI loads the cache on launch and `reload()`s it
  to observe later writes (see Background operation).

  **iOS caveat (for if/when iOS is supported — see also Background operation, which
  is currently Android-only):** keying the cache by `device.remoteId.str` is safe
  on Android because there `remoteId` is the stable Bluetooth MAC (the pinning code
  already relied on this). On iOS, Core Bluetooth does not expose the MAC —
  `remoteId` is a per-(device,peripheral) CBPeripheral UUID that is stable across
  app launches but **can change on app reinstall**. If it changes, the resolved key
  changes → the app treats it as a new sensor → orphaned cache (history +
  session key) and a forced re-pair (re-enter pairing code; chart rebuilds from
  backfill). No corruption, just inconvenience + minor storage bloat from the
  orphaned bucket. The robust cross-platform fix is to key by the **real Dexcom
  serial** the sensor reports in `device_info` (`0x4A`), but that only arrives
  AFTER auth, so it needs a re-keying step (pair under the BLE id, then migrate the
  bucket to the real serial once known). Not worth it for Android-only.

## Gotchas (already fixed — keep them)

- `rust_builder/cargokit/gradle/plugin.gradle` is patched to use injected
  `ExecOperations` instead of `Project.exec()` (removed in Gradle 9).
- `compileSdk = 36` / `minSdk = 26` in BOTH `android/app/build.gradle.kts` AND
  `rust_builder/android/build.gradle` (the two must match). `minSdk` is **26**
  because the `health` plugin (Health Connect, used by the Sport tab's Google
  Health import) floors it there; flutter_blue_plus 2.x needs ≥23. `flutter
  build`'s one-time "Upgrading build.gradle.kts" migration may revert `minSdk`
  (back to `flutter.minSdkVersion`) — reset it to 26.
- `flutter_blue_plus` 2.x: `device.connect(license: License.nonprofit)` is required.
- Auth char uses **indications**; control/backfill are subscribed only AFTER
  auth (subscribing them early makes the sensor drop the connection).
- **QR/DataMatrix scan (mobile_scanner) needs R8 keep rules** in
  `android/app/proguard-rules.pro` (wired via `proguardFiles` in the release
  buildType). Flutter enables R8 for release; mobile_scanner's bundled keep
  rules use a single-star wildcard that misses the
  `com.google.android.gms.internal.mlkit_*` impl packages, so R8 strips the
  MLKit barcode pipeline and the scanner NPEs (`null object reference`, obfuscated
  names) the moment the camera opens — **release only**, debug is fine.

## Reference

`docs/` holds the per-topic knowledge files (one focused subject each):
- `docs/PROTOCOL.md` — full byte-level **Dexcom G7** protocol spec + source
  citations (Juggluco, DiaBLE, G7SensorKit, xDrip).
- `docs/LIBRE3.md` — **FreeStyle Libre 3** protocol (NFC activation, BLE GATT,
  security handshake), the vendor-blob bridge design + legal caveat, and the
  implementation status (what's done vs. hardware-gated).
- `docs/OMNIPOD.md` — **Omnipod DASH** pump: implementation status, the four
  protocol layers (fragments/messages/security/commands), and the hazard
  analysis — including why there is no read-only mode and what each guard in
  `lib/src/pump/protocol/` defends against.
- `docs/ALARMS.md` — alarm/notification design (audio stream, DnD ordering, ids).
- `docs/LOCALIZATION.md` — locale files, key naming, and `ServiceStrings`.
- `docs/DESIGN.md` — the theme/colour-role system: the two accents, the three
  foreground tones, the affordance shapes, both surface ladders, Flutter's
  silent `ColorScheme` fallbacks, and the measured contrast values.
- `docs/PERFORMANCE.md` — what made the UI stutter: the per-build archive parse,
  animating inside a chart, and the tab pages' scroll cache.
- `docs/ACTIVE_WORKOUT.md` — the running workout shared with the panel: who
  drives, who follows, and the server stamp that stops a finished workout being
  written back to life.
- `docs/BATTERY.md` — the two-level battery saver: what each level pauses, why the
  gate sits in `BackgroundLocationSampler.tick()`, and why a manual cardio
  recording must force the detection service up.

`lib/src/rust/` is generated — never hand-edit; change `rust/src/api/` and rerun
codegen.
