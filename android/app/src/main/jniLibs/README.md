# FreeStyle Libre 3 native crypto (`jniLibs/`)

The Libre 3 BLE security handshake is gated by a static P-256 key Abbott protects
with WhiteCryption Secure Key Box. There is **no clean-room path** — confirmed
from Juggluco's own `loadlibs.cpp`, which `dlopen`s Abbott's binaries and
delegates to their `process1`/`process2` symbols. So this app, like Juggluco,
must call those binaries. They are **not** and cannot be committed here.

To enable the Libre 3, add — for **`arm64-v8a/`** (the only supported ABI):

1. **Abbott's blobs**, extracted from an official APK / Juggluco:
   - `liblibre3extension.so`  (the ECDH / challenge / AES crypto)
   - `libcrl_dp.so`           (activation / data-provider helpers)
   - `libinit.so`             (dependency loader)
2. **`liblibre3bridge.so`** — a small shim you build that `dlopen`s the three
   blobs and exposes their symbols as the JNI functions
   `Libre3SecurityPlugin.processInt/processBar/appCertificate/setPatchCertificate/initCipher/decrypt`.
   Port this from Juggluco's `Common/src/main/cpp/libre3/loadlibs.cpp`
   (`dlopen(RTLD_NOW)` + `dlsym` of `process1`, `process2`,
   `DPGetActivationCommandData`, …) and wire it via CMake/`externalNativeBuild`
   in `android/app/build.gradle.kts`.

Without these files the app still builds and runs; `Libre3SecurityPlugin`
reports `nativeLoaded = false` and every crypto call returns a `no_blob` error,
so only the Libre 3 pairing is unavailable — the Dexcom G7 is unaffected.

The embedded app certificate / patch signing keys / wrapped private keys live in
Juggluco's `KEYSCrypto.java`; they are inputs the blob consumes (the wrapped
private keys are SKB-protected and unusable without it).

⚠️ Shipping Abbott's proprietary binaries has redistribution implications — the
same ones Juggluco carries. This was an explicit project decision (see
`docs/LIBRE3.md`).
