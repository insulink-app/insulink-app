# Insulink

A from-scratch **Dexcom G7 BLE reader** in Flutter, implementing the sensor
authentication handshake ourselves (EC-JPAKE) rather than depending on the
official app. Android-first.

> ⚠️ **Interoperability / research project.** Use only with sensors you own.
> The G7 is a medical device; do not rely on this for dosing decisions. Several
> protocol details below are reverse-engineered and **must be confirmed against
> a real sensor capture** before the data can be trusted.

## Architecture

```
Flutter (Dart)                       Rust core (the only non-Dart part)
─────────────                        ──────────────────────────────────
lib/src/g7/opcodes.dart       auth opcodes (extracted from the APK)
lib/src/g7/uuids.dart         GATT UUIDs (confirmed vs. Juggluco)
lib/src/g7/glucose.dart       EGV / backfill decoder (offsets — verify)
lib/src/g7/ble_transport.dart   flutter_blue_plus: scan/connect/notify/write
lib/src/g7/auth_session.dart    handshake state machine ─FRB─► rust/src/api/jpake.rs
                                                               custom EC-JPAKE on p256
                                                               (Juggluco port, byte-validated)
```

Why Rust + p256: the G7 authenticates with a **custom EC-JPAKE** (secp256r1 +
SHA-256) using raw-point wire framing — NOT mbedTLS's TLS encoding. There is no
pure-Dart EC-JPAKE, so the core is a hand port of Juggluco's `ecJPake.cpp` onto
the RustCrypto `p256` crate. It is **byte-validated against Juggluco's compiled
reference output** (see `cargo test`): round payloads, derived session key, and
AES confirmation all match exactly.

## What is confirmed vs. what to verify

| Item | Status |
|---|---|
| Auth opcode **byte values** (`opcodes.dart`) | ✅ Extracted from `AuthOpCodes` enum |
| EC-JPAKE crypto + wire framing + key derivation | ✅ **Byte-exact** vs. Juggluco reference (`cargo test`) |
| GATT **UUIDs** incl. 3538 J-PAKE char (`uuids.dart`) | ✅ Confirmed against Juggluco source |
| Handshake **sequence** (`auth_session.dart`) | ✅ Mirrors Juggluco's DexGattCallback flow |
| AES key-confirmation (0x02/03/04/05) | ✅ Verified on real sensor (statusReply `05 01 02`) |
| `0x0B` cert exchange / `0x0C` proof-of-possession | ✅ Works on real sensor (both certs exchanged, PoP accepted) |
| OS bonding (06/07/08 → createBond) | ✅ Bonds successfully; control + backfill channels open |
| Reconnect without re-pairing (persisted key) | ✅ Stored session key → fast AES re-auth, no bond dialog |
| Glucose decoding (`glucose.dart`) | ✅ EGV (`0x4E`) + backfill parsed (Juggluco `glucoseinput`/`dexbackfill` layout) |

**Status: complete, working G7 reader on real hardware** (DXCM G7) — first run
pairs (EC-JPAKE → AES auth → display-cert → proof-of-possession → OS bond), every
run after reconnects fast with the persisted key, then streams live glucose
(`156 mg/dL (+0.2/min)…`). Serial, pairing code, and per-sensor session key persist
across launches.

UI: live value + trend arrow, an `fl_chart` glucose graph fed by **backfill
history** (`0x59` request → last 24 h) plus live EGVs, and **auto-connect on
launch** when a paired sensor is stored. (`fl_chart` added to `pubspec.yaml`;
`flutter pub get` runs as part of the build.)

The remaining gap (`0x0B`/`0x0C`) is the one part no open client fully reveals;
see `docs/PROTOCOL.md`. Capture it with Frida or an nRF sniffer if your firmware
requires it.

## Prerequisites

- Flutter 3.44+, Rust 1.88+, `flutter_rust_bridge_codegen` 2.11.x
- Android NDK (tested with 28.2.13676358). **No cmake/ninja/bindgen needed** —
  the core is pure Rust now.

## Build & run (Android)

```bash
# regenerate the Dart<->Rust bridge after editing rust/src/api/*
flutter_rust_bridge_codegen generate

# validate the crypto core (byte-exact KATs vs. Juggluco reference)
cd rust && cargo test && cd ..

# single ABI is smaller/faster while iterating
flutter build apk --debug --target-platform android-arm64
# or: flutter run   (on a connected device)
```

No environment variables are required for the Rust build anymore (the old
mbedTLS C build needed `ANDROID_NDK`/`CMAKE_GENERATOR`/`BINDGEN_EXTRA_CLANG_ARGS`).

In the app: enter the **pairing code** (the serial field is optional, for scan
identification) and tap **Pair & Read**. The log pane shows every BLE
service/characteristic (to confirm UUIDs) and each handshake step.

### Build fixes already applied (for reference / other machines)

1. **Gradle 9 removed `Project.exec()`** — `rust_builder/cargokit/gradle/plugin.gradle`
   patched to use an injected `ExecOperations` service.
2. **compileSdk** — flutter_blue_plus 2.x requires API 36. Bumped in BOTH
   `android/app/build.gradle.kts` (`compileSdk = 36`, `minSdk = 23`) **and**
   `rust_builder/android/build.gradle` (`compileSdkVersion 36`) — the AAR check
   flagged the `:rust_lib_g7_reader` module specifically. If `flutter build`
   reverts `minSdk` (its one-time "Upgrading build.gradle.kts" migration), reset it.

> Only one app may own the sensor's auth session — uninstall/stop the official
> Dexcom app and any receiver before pairing.

## Handshake (validated against Juggluco)

```
EC-JPAKE round 0/1/2   {0x0A, n} on auth(3535) + 160-byte payload on jpake(3538)
AppKeyChallenge (0x02)  0x02 ‖ nonce8 ‖ 0x02
ChallengeReply  (0x03)  0x03 ‖ AES8(key,nonce8) ‖ challenge8   (sensor → us)
HashFromDisplay (0x04)  0x04 ‖ AES8(key,challenge8)
StatusReply     (0x05)  {0x05, authed, status}
[0x0B cert / 0x0C proof-of-possession — TODO, firmware-dependent]
KeepConnectionAlive(0x06) ‖ RequestBond(0x07) → RequestBondResponse(0x08) → OS bond
```

## Layout

- `rust/src/api/jpake.rs` — EC-JPAKE core + host test
- `lib/src/g7/` — protocol, BLE, state machine
- `lib/src/rust/` — generated FRB bindings (do not edit by hand)

## License & credits

Licensed under **GPL-3.0** (see `LICENSE`).

This project is a derivative work of **[Juggluco](https://github.com/j-kaltes/Juggluco)**
by Jaap Korthals Altes (GPL-3.0). The EC-JPAKE implementation in
`rust/src/api/jpake.rs` is a port of Juggluco's `ecJPake.cpp`, and the embedded
Dexcom display certificate chain + signing key (`lib/src/g7/display_certs.dart`,
`DISPLAY_PRIV_KEY`) are taken from Juggluco. Protocol details were also informed
by [DiaBLE](https://github.com/gui-dos/DiaBLE), [LoopKit/G7SensorKit](https://github.com/LoopKit/G7SensorKit),
and [xDrip+](https://github.com/NightscoutFoundation/xDrip).

**Disclaimer:** interoperability/research project for use with your own sensor.
Not affiliated with or endorsed by Dexcom. Not a medical device — do not use for
treatment decisions.
