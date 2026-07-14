# Insulink

A from-scratch **diabetes companion app** built in Flutter — [insulink.de](https://insulink.de).
It reads CGM sensors directly over Bluetooth, without the official apps, and
keeps live and historical glucose alongside the rest of the day: meals, sport,
injections and vitals. Android-first.

- **Sensors:** **Dexcom G7** (fully working) and **FreeStyle Libre 3** (in
  progress — NFC activation and glucose decode are done, the BLE handshake is
  not; see `docs/LIBRE3.md`). Everything above the wire layer is
  sensor-agnostic, so both feed the same chart, statistics and alarms.
- **Background reading:** the BLE pipeline runs in an Android foreground service,
  so glucose keeps arriving with the app closed, including glucose, sensor-expiry
  and connection-lost alarms that pierce Do Not Disturb.
- **Beyond glucose:** nutrition (meals, food, hydration), sport (activities,
  workouts, routines), insulin injections, Google Health / Health Connect import
  (heart rate, sleep, steps) and an analysis tab with AGP-style patterns and
  time-in-range.
- **Account sync:** an optional account (`api.insulink.de`) syncs glucose,
  sensors, events, meals, sport and vitals across devices.

|      | Build Status                                                                                                                                                                      | Test Code Coverage                                                                                                                    |
|------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| main | [![Build Status](https://github.com/breuerlukas/insulink/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/breuerlukas/insulink/actions/workflows/build.yml) | [![codecov](https://codecov.io/gh/breuerlukas/insulink/graph/badge.svg?token=QU5RWJ6XWB)](https://codecov.io/gh/breuerlukas/insulink) |

> ⚠️ **Use at your own risk.** This is an interoperability and research project,
> **not a medical device**. Use it only with sensors you own and **never** for
> dosing or treatment decisions. Parts of the protocol are reverse-engineered.
> Not affiliated with or endorsed by Dexcom or Abbott.

## Build & run

```bash
# regenerate the Dart<->Rust bridge after editing rust/src/api/*
flutter_rust_bridge_codegen generate

# on a connected device
flutter run

# or a smaller/faster single-ABI debug build:
flutter build apk --debug --target-platform android-arm64
```

You need Flutter 3.44+, Rust 1.88+, `flutter_rust_bridge_codegen` 2.12.x and the
Android NDK. The `flutter_rust_bridge` version must be identical in `pubspec.yaml`,
`rust/Cargo.toml` and the generated `rust/src/frb_generated.rs`, otherwise
`RustLib.init()` fails at runtime. The Rust core is pure Rust, so no cmake, ninja
or NDK environment variables are required.

Test on-device with a **profile or release** build — a standalone debug build
often hangs on the splash screen. Because only one app may own the sensor's
connection, stop the official Dexcom app and any receiver before pairing.

## Architecture

Two layers, bridged by flutter_rust_bridge: **Dart** owns BLE, the handshake
state machine, parsing, persistence and UI; **Rust** (`rust/src/api/jpake.rs`)
owns only the crypto the G7 pairing needs — EC-JPAKE (secp256r1 + SHA-256) and
the ECDSA proof-of-possession — verified byte-for-byte against known-answer
vectors from Juggluco.

Code is packaged **by feature, not by layer**: `cgm/` (shared read pipeline +
Dexcom G7 wire code under `cgm/protocol/`), `libre3/`, `overview/`, `sensor/`,
`analysis/`, `nutrition/`, `sport/`, `injection/`, `profile/`,
`google_health/`, `auth/`, with cross-cutting code in `base/`, `localization/`
and `theme/`. `lib/src/rust/` is generated — never hand-edit it.

The per-topic details live in `docs/`: `PROTOCOL.md` (byte-level G7 protocol),
`LIBRE3.md`, `ALARMS.md` and `LOCALIZATION.md`.

## Tests

```bash
flutter test           # Dart unit + widget tests
cd rust && cargo test  # Rust core known-answer tests
```

## Contributions

Contributions are welcome. For larger changes please open an issue first so we
can discuss the approach. Continuous integration runs the analyzer, the Flutter
tests and the Rust known-answer tests on every pull request, so please keep them
green.

## License & credits

Licensed under **GPL-3.0** (see `LICENSE`). Insulink is a derivative work of
[Juggluco](https://github.com/j-kaltes/Juggluco) by Jaap Korthals Altes
(GPL-3.0). Protocol details were also informed by
[DiaBLE](https://github.com/gui-dos/DiaBLE),
[LoopKit/G7SensorKit](https://github.com/LoopKit/G7SensorKit) and
[xDrip+](https://github.com/NightscoutFoundation/xDrip).
