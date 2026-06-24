# Insulink

A from-scratch **Dexcom G7 glucose reader** built in Flutter. It connects to the
sensor over Bluetooth and shows live and historical glucose, including a chart,
trend and alarms, without the official app. Android-first.

|      | Build Status                                                                                                                                                                      | Test Code Coverage                                                                                                                    |
|------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| main | [![Build Status](https://github.com/breuerlukas/insulink/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/breuerlukas/insulink/actions/workflows/build.yml) | [![codecov](https://codecov.io/gh/breuerlukas/insulink/graph/badge.svg?token=QU5RWJ6XWB)](https://codecov.io/gh/breuerlukas/insulink) |

> ⚠️ **Use at your own risk.** This is an interoperability and research project,
> **not a medical device**. Use it only with sensors you own and **never** for
> dosing or treatment decisions. Parts of the protocol are reverse-engineered.
> Not affiliated with or endorsed by Dexcom.

## Build & run (Android)

```bash
# regenerate the Dart<->Rust bridge after editing rust/src/api/*
flutter_rust_bridge_codegen generate

flutter run                                   # on a connected device
# or a smaller/faster single-ABI debug build:
flutter build apk --debug --target-platform android-arm64
```

You need Flutter 3.44+, Rust 1.88+, `flutter_rust_bridge_codegen` 2.11.x and the
Android NDK. The Rust core is pure Rust, so no cmake, ninja or NDK environment
variables are required. Because only one app may own the sensor's connection,
stop the official Dexcom app and any receiver before pairing.

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
