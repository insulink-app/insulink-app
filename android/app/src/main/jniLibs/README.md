# FreeStyle Libre 3 native crypto (`jniLibs/`)

The Libre 3 BLE security handshake is gated by a static P-256 key Abbott protects
with WhiteCryption Secure Key Box. There is **no clean-room path** — confirmed
from Juggluco's own `loadlibs.cpp`, which `dlopen`s Abbott's binaries and
delegates to their `process1`/`process2` symbols. So this app, like Juggluco,
must call those binaries. They are **never committed** (`.gitignore` blocks
`jniLibs/**/*.so`); every build supplies them locally.

## Where the binary comes from

From **Juggluco's own release APK** — Juggluco has already extracted and
repackaged Abbott's Libre 3 crypto into `liblibre3extension.so`, and our shim is
ported from Juggluco's `loadlibs.cpp` to match it exactly (class
`…Libre3SKBCryptoLib`, symbols `process1`/`process2`).

> ⚠️ NOT the LibreLink app. LibreLink (`com.freestylelibre.app`) is obfuscated and
> ships differently-named libs (`libDataProcessing.so`, `libSecureKeyBoxJava.so`)
> that do NOT match this shim. Use the Juggluco APK.

```sh
# 1. Download the arm64 Juggluco APK from https://www.juggluco.nl/Juggluco/download.html
unzip -o Juggluco*.apk 'lib/arm64-v8a/liblibre3extension.so' -d jug
# 2. Copy it here:
cp jug/lib/arm64-v8a/liblibre3extension.so \
   android/app/src/main/jniLibs/arm64-v8a/
```

Only `liblibre3extension.so` is needed (the ECDH / challenge crypto =
`process1`/`process2`). `libcrl_dp.so` / `libinit.so` are for Abbott-side NFC
activation, which we do clean-room in Dart (`Libre3Activation`), so they're
optional.

## What is already wired

`liblibre3bridge.so` — the `dlopen` shim (`src/main/cpp/libre3bridge.cpp`, built
via `externalNativeBuild`) — is **already in this repo**. It ports Juggluco's
`loadlibs.cpp`: it `dlopen`s `liblibre3extension.so`, intercepts its
`JNI_OnLoad` → `RegisterNatives` to capture `process1`/`process2`, and exposes
them to `Libre3SecurityPlugin`. Drop the Abbott `.so` in and the handshake
primitives (`initKeys`, `generateEphemeralKeys`, `setPatchCertificate`,
`setPatchEphemeral`, `encryptChallenge`, `decryptChallenge`, `exportAuthKey`)
work. Without it, `nativeLoaded = false` → `no_blob`, and the Dexcom G7 is
unaffected.

## Already ported (no extra binary)

- **App certificate + wrapped private keys**: Abbott's key material, so it is
  NOT committed either. `Libre3Keys.kt` reads it from `BuildConfig`, which Gradle
  fills from the gitignored `android/libre3.properties`. Copy the hex bytes of
  `LIBRE3_APP_CERTIFICATES_B` (162 B each) and `LIBRE3_APP_PRIVATE_KEYS` (165 B
  each) from Juggluco's `KEYSCrypto.java`, one comma-separated list per security
  version order:

  ```properties
  certificates=<hex v0>,<hex v1>
  private_keys=<hex v0>,<hex v1>
  ```

  Missing file → empty lists → the app still builds, Libre 3 just can't pair.
  `initKeys` runs the real two-step load (`process1(1)` then
  `process1(2, privateKey, kAuth)`); `appCertificate` returns the cert.
- **AES-128-CCM data path** — `Libre3Ccm` (pointycastle), RFC-3610 tested.

## SKB anti-tamper caveat (on-device frontier)

The Juggluco 10.9.5 `liblibre3extension.so` is WhiteCryption-SKB-protected: its
JNI class name is runtime-decrypted (not in the binary), and Juggluco's real
loader carries anti-tamper machinery (Frida-Gum `gumshim_install_*`, a
`process1 = JNI_OnLoad + offset` fallback, a date-pinned `libre3_gum_…` wrapper)
because SKB resists a faked JNI env. Our `libre3bridge.cpp` implements the clean
RegisterNatives-intercept only. It may work (the intercept fires with the
decrypted name at runtime) — but if SKB detects the fake VM, Juggluco's Gum layer
would need porting too. Decidable only on-device: watch `adb logcat` for the
shim's `dlopen` / `process1=%p` lines.

So the blob is packaged and every clean-room piece is done; a first real reading
still hinges on this SKB question plus the `ponytail:`-marked protocol details
(NFC frame flags, CCM nonce/MAC, fragment framing) — a sensor is required.

⚠️ Abbott's binaries and keys must not be redistributed: not in git, and not in a
published APK either (an APK built with them contains them). Build with them for
your own device only.
