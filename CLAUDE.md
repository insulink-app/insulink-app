# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

InsuLink is a Flutter (Android-first) app that reads glucose data from a Dexcom G7 transmitter directly over BLE — no Dexcom app/cloud in the loop. It also intends to surface OmniPod 5 status (not yet implemented). The whole app currently lives in three files under `lib/`.

## Commands

- Run the app (device/emulator must be attached): `flutter run`
- Static analysis (uses `flutter_lints` via `analysis_options.yaml`): `flutter analyze`
- Run tests: `flutter test` (single file: `flutter test test/some_test.dart`)
- Install/update dependencies after editing `pubspec.yaml`: `flutter pub get`
- Build a release APK: `flutter build apk`

There is no CI config and the `test/` directory is currently empty (only `.gitkeep`).

## Architecture

Three files, each with a distinct responsibility:

- `lib/protocol.dart` — Pure Dart, no Flutter/BLE dependencies. Defines the Dexcom G7 BLE wire protocol: GATT service/characteristic UUIDs (`DexcomUUIDs`), opcodes (`Opcode`), AES-128-ECB challenge-response crypto (`DexcomCrypto`), and typed TX/RX message classes (`AuthRequestTx`, `AuthChallengeTx`, `KeepAliveTx`, `EGlucoseTx`, `AuthChallengeRx`, `AuthStatusRx`, `EGlucoseRx`). `classifyPacket(Uint8List)` turns raw bytes into a `DexcomPacket` sealed-class hierarchy (`AuthChallengePacket` / `AuthStatusPacket` / `GlucosePacket` / `UnknownPacket`) — this is the boundary between raw bytes and typed protocol messages. This file is a port of logic from xDrip+ (NightscoutFoundation/xDrip, AGPLv3) — see the file header comment before changing the byte layouts.
- `lib/service.dart` — `DexcomG7Service extends ChangeNotifier` (provided via `package:provider` at app root in `main.dart`). Owns all BLE state and the connection lifecycle as an explicit state machine (`DexConnectionState`: idle → scanning → connecting → authenticating → connected, plus error/disconnected). Drives `flutter_blue_plus` to scan for devices advertising as `DXCM`/`DX02`/`DX01`, discover the CGM GATT service, and perform the auth handshake (`_startAuthentication` → `_handleChallenge` → `_handleAuthStatus`) using the pairing code converted to an AES key in `protocol.dart`. Holds the rolling `_history` of `DexcomReading`s (capped at 288 = 24h of 5-min readings) and exposes `lastReading`/`history`/`connectionState`/`statusMessage`/`errorMessage` as the UI's only window into BLE state — widgets never touch `flutter_blue_plus` directly.
- `lib/main.dart` — UI only. `HomeScreen` consumes `DexcomG7Service` via `Consumer`/`Provider.of` and renders glucose value, connection status, the 4-digit pairing code input (persisted to `SharedPreferences` under key `transmitter_id`), and connect/disconnect/read actions gated by `permission_handler` Bluetooth/location grants. `HistoryScreen` renders `service.history`. UI strings are in German.

### Key invariants when modifying the protocol/service layer

- The AES key is derived purely from the 4-digit pairing code (`DexcomCrypto.buildKey`); it is never read from the BLE link, so a wrong code fails authentication (`AuthStatusRx.authenticated == false`) rather than throwing.
- `EGlucoseRx.parse` returns `null` (not an exception) on malformed/short payloads — `classifyPacket` and callers rely on this to fall through to `UnknownPacket` instead of crashing on unexpected device traffic.
- `_setState`/`_setError` in `service.dart` are the only places that mutate connection state and always call `notifyListeners()`; new state transitions should go through these rather than mutating `_connectionState` directly.
- `_reset()` is responsible for tearing down all stream subscriptions and the device connection before any new `connect()` attempt — when adding new subscriptions, add their cleanup there too.