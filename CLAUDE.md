# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A from-scratch **Dexcom G7 BLE reader** (Flutter + Rust). It reimplements the
G7's proprietary pairing/authentication and reads live + historical glucose,
without the official app. GPL-3.0; derivative of [Juggluco](https://github.com/j-kaltes/Juggluco).
Interoperability/research project — not a medical device.

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

### The handshake (`lib/src/g7/auth_session.dart`)

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
   match it. Fixed by **device pinning**: `G7Store.deviceId(serial)` stores the
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

- `connection.dart` (`G7Connection`) is the UI-free read pipeline: scan →
  connect → `runReconnect`/`run` → stream live EGV + backfill → parse →
  persist. It only depends on the already widget-free layers (`BleTransport`,
  `G7AuthSession`, codecs, `G7Store`) and reports out via callbacks
  (`onLog`/`onReading`/`onUpdate`/`onConnectionState`). It used to live inline
  in `_ReaderPageState`.
- `ble_service.dart`: the `@pragma('vm:entry-point') startCallback` +
  `G7TaskHandler` that runs `G7Connection` inside the service isolate. It
  **must `await RustLib.init()` again** (fresh isolate ⇒ fresh Rust core),
  updates the notification text with the latest mg/dL, pushes updates to the UI
  with `sendDataToMain`, and reconnects from `onRepeatEvent` (a 30 s watchdog).
- `main.dart` is now a thin viewer: `initCommunicationPort()` in `main()`,
  start/stop the service (not the connection) from the Connect/Disconnect
  buttons, receive live pushes via `addTaskDataCallback`, and re-`reload()` the
  store on `AppLifecycleState.resumed` to catch up on what the service captured
  while away. `flutter_blue_plus` works in the service isolate because FFT
  registers plugins on its background engine.

Load-bearing background gotchas (don't regress):
1. **FGS type `connectedDevice` requires a held Bluetooth runtime permission**
   on Android 14+ (target SDK 34+). The scan now runs in the background isolate
   which can't show dialogs, so `main.dart` requests `BLUETOOTH_SCAN/CONNECT`
   (via `permission_handler`) and aborts BEFORE `startService` if denied —
   otherwise native `startForeground` throws `SecurityException` and the service
   sticky-restarts in a loop.
2. **Cross-isolate store cache**: `G7Store` is backed by `flutter_secure_storage`
   but serves synchronous getters from an in-memory cache loaded via `readAll()`.
   That cache is per-isolate, so the UI must `G7Store.reload()` (a fresh
   `readAll()`) to see the service's writes (done on the `update` ping and on
   resume).
3. Manifest needs `FOREGROUND_SERVICE_CONNECTED_DEVICE` + `POST_NOTIFICATIONS` +
   the `connectedDevice`-typed `com.pravera.flutter_foreground_task…ForegroundService`.
4. *Scanning* (not maintaining a link) can be throttled while the screen is off
   (FBP issue #924), so a cold reconnect may complete only on the next
   screen-on; an already-open connection keeps streaming.
   - Android delivers **no results for an UNfiltered scan while the screen is
     off** — `scanForSensor` passes the stored remoteId as a native
     `withRemoteIds` filter so background results come through. Even so,
     screen-off scanning stays unreliable on some devices (open issue: scenario
     where the watchdog fires + scans but never reconnects until screen-on).
   - **`autoConnect` (connect by `BluetoothDevice.fromId` + `autoConnect: true`)
     did NOT work here** — it broke connecting entirely (likely the G7 reconnect
     path doesn't reliably OS-bond). Reverted; the scan path is the known-good one.
5. **The G7 connect→deliver→disconnect is NORMAL.** It connects briefly (~every
   5 min), pushes the current EGV + backfill, then drops the link itself — so
   `link dropped` right after `connected — streaming` is expected, and the 30 s
   watchdog reconnecting is correct, not a bug.
6. **The G7 rejects rapid in-process reconnects** (`REMOTE_USER_TERMINATED`
   status 19 / `GATT_CONNECTION_TIMEOUT` 147). Do exactly ONE clean attempt per
   `connect()` and let the watchdog retry on the sensor's own advertising
   schedule — do NOT tight-loop retry within a single connect.

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
- `store.dart` (flutter_secure_storage, synchronous getters served from an
  in-memory cache loaded via `readAll()` on `open()`/`reload()`): per-**serial**
  keys for session key,
  glucose history, device info, sensor start, and the latest EGV
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
- `compileSdk = 36` / `minSdk = 23` in BOTH `android/app/build.gradle.kts` AND
  `rust_builder/android/build.gradle` (flutter_blue_plus 2.x). `flutter build`'s
  one-time "Upgrading build.gradle.kts" migration may revert `minSdk` — reset it.
- `flutter_blue_plus` 2.x: `device.connect(license: License.nonprofit)` is required.
- Auth char uses **indications**; control/backfill are subscribed only AFTER
  auth (subscribing them early makes the sensor drop the connection).

## Reference

`docs/PROTOCOL.md` has the full byte-level protocol spec and source citations
(Juggluco, DiaBLE, G7SensorKit, xDrip). `lib/src/rust/` is generated — never
hand-edit; change `rust/src/api/` and rerun codegen.
