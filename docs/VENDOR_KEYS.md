# Vendor keys (Dexcom G7, Omnipod DASH, FreeStyle Libre 3)

Three handshakes need material that belongs to the manufacturers, not to this
project. None of it is committed (the history was rewritten to remove the copies
that once were), and all of it lives in one gitignored folder:

```
assets/vendor_keys/
  vendor_keys.example.json          committed, the layout with placeholders
  vendor_keys.json                  yours: every key, all three devices
  jniLibs/arm64-v8a/
    liblibre3extension.so           yours: Abbott's Libre 3 crypto blob
```

## What goes in

| Device | `vendor_keys.json` field | What | Source |
|--------|--------------------------|------|--------|
| Dexcom G7 | `dexcom.display_certificates` | display certificate chain, 2 DER certs | Juggluco `DexGattCallback.certs` |
| Dexcom G7 | `dexcom.display_private_key` | the leaf cert's P-256 key, 32 bytes | Juggluco `getKeyC` in `ecJPake.cpp` (31 bytes, zero-pad at the front) |
| Omnipod DASH | `omnipod.milenage_operator` | Milenage operator constant OP, 16 bytes | AndroidAPS `MILENAGE_OP` in the DASH driver's `Milenage.kt` |
| Libre 3 | `libre3.app_certificates` | app certificate per security version, 162 bytes each | Juggluco `KEYSCrypto.java`, `LIBRE3_APP_CERTIFICATES_B` |
| Libre 3 | `libre3.app_private_keys` | SKB-wrapped key per security version, 165 bytes each | Juggluco `KEYSCrypto.java`, `LIBRE3_APP_PRIVATE_KEYS` |

Every value is a lowercase hex string; the Libre 3 lists are in security-version
order. Start from `vendor_keys.example.json`. The blob comes out of Juggluco's
APK, steps in `docs/LIBRE3_BLOB.md`. `libinit.so` may sit next to it, it is
optional.

Then build as usual. **An APK built this way contains all of it**: do not
publish such an APK.

## Who reads what

- **Dart** (Dexcom, Omnipod): `VendorKeys.ensureLoaded()` reads the JSON as a
  Flutter asset once per isolate, like `RustCore`: `main` for the UI isolate,
  `CgmTaskHandler._ensureReady` for the service isolate, and `PodConnection`
  before every pairing or session. The Dexcom key is handed to Rust's `pop_sign`.
  The asset entry lists the folder, which bundles only its direct files, so the
  blob under `jniLibs/` is not copied into the Flutter assets.
- **Gradle** (Libre 3): `android/app/build.gradle.kts` parses the same JSON into
  `BuildConfig` for `Libre3Keys.kt`, adds `jniLibs/` as a native library source,
  and records whether the blob was there (`BuildConfig.LIBRE3_BLOB`).

A missing or malformed file leaves everything empty; nothing throws at build or
load time.

## When something is missing

- **On every app start** `VendorKeysWarning` (wrapping `AuthGate`) shows an
  `Alert` naming each device that cannot pair. Libre 3 counts as missing when
  either its keys or its blob are absent; that is answered from the build-time
  flags (`vendorKeysComplete` on the Libre 3 channel), so the check never loads
  the blob. The warning returns on each launch on purpose: a build without the
  keys otherwise looks healthy until a pairing fails.
- **Dexcom G7:** a fresh pair stops before its first J-PAKE round with
  `Dexcom vendor keys missing`. A reconnect with a stored session key needs
  neither cert nor key, so an already paired sensor keeps reading.
- **Omnipod DASH:** `PodConnection` refuses pairing and sessions before touching
  the radio. Pairing without the OP would hand a pod a key it could never be
  commanded with.
- **Libre 3:** the channel answers `no_blob`, or the handshake has no key for the
  sensor's security version.
- **Tests:** the Milenage known-answer tests and the session-establishment flow
  read the local file through `test/pump/vendor_keys_fixture.dart` and are
  skipped (not failed) without it. The Rust PoP test signs with a test key.
