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

Note: on-device build/install/run is typically driven by the developer (watch
`adb logcat | grep -i flutter`); the in-app log pane mirrors each handshake step.

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

### Data + persistence

- `glucose.dart`: EGV (`0x4E`) and backfill (`dexbackfill`) decoders. Packed
  little-endian; `mgdL` is a 12-bit field. Glucose/backfill are **plaintext**.
- `device_info.dart`: parses `0x4A`/`0x52`/`0x22` (firmware, software #, serial,
  session/warmup length, hardware/algorithm version, battery) + algorithm-state
  labels. Requested right after auth in `main.dart`.
- `store.dart` (shared_preferences): per-**serial** keys for session key,
  glucose history, device info, and sensor start. The serial is NOT used by the
  protocol (the pairing code is the only auth secret) — it is purely the
  persistence key enabling reconnect, cached chart/info, and auto-connect.
  `main.dart` loads the cache on launch so the UI is populated before connecting.

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
