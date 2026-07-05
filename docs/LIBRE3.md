# FreeStyle Libre 3 — protocol, design & status

Second supported sensor alongside the Dexcom G7. Reverse-engineered from open
references — **DiaBLE** (`gui-dos/DiaBLE`, `DiaBLE/Libre3.swift`) is the clean,
readable reference for the whole protocol; **Juggluco** (our upstream) is the
reference for the NFC activation mechanics and is the only open app that actually
**completes** Libre 3 pairing, because it JNI-calls Abbott's proprietary native
blobs for the BLE security crypto (see [Security handshake](#security-handshake)).

Interoperability/research only — not a medical device. Same footing as the G7.

## How the Libre 3 differs from the G7

| | Dexcom G7 | FreeStyle Libre 3 |
|---|---|---|
| Pairing | 4-digit code, EC-JPAKE | **one NFC scan** to activate, then BLE |
| Link | connects/delivers/drops every ~5 min | **continuous**, streams every ~1 min |
| Crypto | EC-JPAKE (fully open, in Rust) | ECDH + ECDSA certs + AES-CCM (**needs Abbott blob**) |
| Glucose | 12-bit mg/dL field | 13-bit mg/dL field |
| Session clock | seconds since start | "life count" = minutes since activation |

Both decode to the shared `CgmReading` (`lib/src/cgm/cgm_connection.dart`), so
everything above the wire layer (persistence, chart, stats, alarms, backend,
service watchdog) is shared. The only sensor-specific timing is `CgmTiming`
(Libre = continuous link, ~1-min cadence).

## NFC activation

One scan activates a sensor (or reads back an already-activated one); after that
all glucose is BLE. Implemented in `lib/src/libre3/libre3_activation.dart` (Android
`NfcV#transceive`, ISO 15693). Pure logic is unit-tested
(`test/libre3/libre3_activation_test.dart`).

**Activation command** — custom command `0xA8` for a fresh sensor (state byte
`patchInfo[14] == 0x01` storage), else `0xA0` to query an activated one.
Parameters (little-endian):

```
(activationTime − 1)  UInt32   Unix seconds
receiverId            UInt32   = fnv32(LibreView account GUID)
crc16(above 8 bytes)  UInt16
```

- **`fnv32`** — an FNV-1 variant with a 0-seeded accumulator and 0xFFFFFFFF mask,
  ported verbatim from DiaBLE's `String.fnv32Hash`:
  `acc = ((acc * 0x811C9DC5) & 0xFFFFFFFF) ^ ascii`.
- **`crc16`** — the FreeStyle Libre CRC-16 (CCITT/Kermit-style, init 0xFFFF), the
  same routine that validates sensor memory across xDrip/DiaBLE.

**Response** (flag `0x00`, 16 bytes, after dropping leading `0xA5` filler):

```
[0..6)   BLE MAC address   (reversed on the wire → find the sensor over BLE)
[6..10)  BLE PIN (4 bytes) (secret consumed in the BLE challenge)
[10..14) activation time   UInt32 LE
[14..16) CRC-16            over [0..14)
```

**Account-ID takeover:** the sensor binds to the receiver id it was activated
with and refuses a different one. A *fresh* sensor accepts any id; to adopt a
sensor Abbott's app already activated, pass that LibreView account's GUID
(Juggluco: *Settings → Exchange data → LibreView → Get account ID*).

> ⚠️ On-device verification pending: the raw ISO 15693 frame's request flags and
> the Abbott IC manufacturer byte (`0x07`, Texas Instruments) are marked
> `ponytail:` in the code — they can only be confirmed against a real sensor.

## BLE GATT

Data service `089810CC-EF89-11E9-81B4-2A2AE2DBCCE4`:

| Characteristic | UUID suffix `-EF89-11E9-81B4-2A2AE2DBCCE4` |
|---|---|
| Patch Control (write) | `08981338` |
| Patch Status (notify) | `08981482` |
| One-Minute Reading (notify) | `0898177A` |
| Historical Data (notify) | `0898195A` |
| Factory Data | `08981D24` |

Security service `0898203A-EF89-11E9-81B4-2A2AE2DBCCE4`:

| Characteristic | UUID suffix |
|---|---|
| Security Commands | `08982198` |
| Challenge Data | `089822CE` |
| Certificate Data | `089823FA` |

Notifications are 20-byte chunks prefixed with a sequence byte; writes carry a
2-byte little-endian offset header.

## Reading layout

One-Minute Reading (29 B, decrypted) — decoded in `libre3_glucose.dart`
(`parseOneMinuteReading`, unit-tested):

```
[0..2)   life count   UInt16  minutes since activation → secsSinceStart = ×60
[2..4)   glucose      UInt16  mg/dL = bits 0..12; bit 15 = error flag
[4..6)   rate         Int16   ÷100 → mg/dL/min (−32768 = flat)
[8..10)  projected    UInt16  ÷100 → predicted mg/dL
[14]     bitfields    trend = bits 0..2, actionable = bit 3, status = bits 4..7
[19..21) temperature  UInt16  ÷100 → °C
```

Historical/backfill (`0898195A`, 20 B) = start life count then 2-byte glucose
values at 5-minute steps. Glucose masking is certain; the record stride is marked
for on-device confirmation.

## Security handshake

**This is the gate to any glucose and the one part that is not clean-room.** On
the Security service, in order (DiaBLE sequence):

1. `0x01` Start ECDH → `0x02` Load Certificate
2. Stream the **app certificate (162 B)** to Certificate Data (20-byte chunks)
3. `0x03` Certificate Load Done → sensor `0x04` Accepted
4. `0x09` Send Certificate → receive **patch certificate (140 B)**, `0x0A`
5. `0x0D` Key Agreement + your ephemeral P-256 public key (65 B) → `0x0E` Done →
   receive sensor ephemeral key → ECDH shared secrets (Ze, Zs)
6. `0x11` Authorize Symmetric → challenge (16-B r1 + 7-B nonce)
7. send encrypted `(r1 ‖ r2 ‖ BLE PIN)`; `0x08` Challenge Load Done
8. receive encrypted **kAuth (60 B) + nonce** → decrypt → **kEnc (16 B) + ivEnc
   (8 B)**; all data thereafter is AES-128-CCM under kEnc/ivEnc with a per-command
   sequence id.

Exact ordered sequence, ported from Juggluco's `Libre3GattCallback` into
`Libre3Transport.runHandshake` (Dart, over flutter_blue_plus). Every crypto step
is delegated to the `Libre3Crypto` bridge (Juggluco's `Natives.processint`
(→ `processInt`) / `processbar` (→ `processBar`) / `intDecrypt`):

| Step | GATT action | crypto bridge call |
|---|---|---|
| init | notify challenge/cert chars | `initKeys(cachedAuthKey, secVer)` |
| `0x01` → COMMAND | start security | — |
| `0x02` → COMMAND | request cert exchange | — |
| CERT_DATA ← app cert | send 162-B app cert (18-B chunks + LE16 offset) | `appCertificate()` |
| `0x03` → COMMAND | app cert sent | — |
| CERT_DATA → 140 B | receive patch cert | `setPatchCertificate(cert140)` |
| `0x0D` → COMMAND | patch cert set | — |
| CERT_DATA ← ephemeral | send our P-256 ephemeral | `generateEphemeralKeys()` (`processbar 5`) |
| `0x0E` → COMMAND | ephemeral sent | — |
| CERT_DATA → 65 B | receive sensor ephemeral | `setPatchEphemeral(eph65)` (`processint 6`) |
| `0x11` → COMMAND | authorize symmetric | — |
| CHALLENGE → 23 B | r1(16) + nonce(7) | — |
| CHALLENGE ← 39 B | send `enc(r1‖r2‖pin)` | `encryptChallenge(nonce, r1‖r2‖pin)` (`processbar 7`) |
| `0x08` → COMMAND | challenge sent | — |
| CHALLENGE → 67 B | 60-B enc + 7-B nonce | `decryptChallenge(nonce, enc60)` → `[r2‖r1‖kEnc(16)‖ivEnc(8)]` (`processbar 8`) |
| `0x09` → COMMAND | generate session keys | `exportAuthKey()` (`processbar 9`, cache kAuth) |
| enable data chars | PATCH_CONTROL→…→GLUCOSE→PATCH_STATUS | `initCipher(kEnc, ivEnc)` |

After the handshake, each data notification is decrypted with
`decrypt(channelId, payload)` (`intDecrypt`: 3 = glucose, 4 = historic,
2 = patch status) → `Libre3GlucoseCodec`. A cached kAuth short-circuits straight
to the challenge (pre-authorised path).

The blocker: `encryptChallenge`/`decryptChallenge`/`appCertificate`/
`setPatchEphemeral` all use the **static P-256 key Abbott protects with
WhiteCryption Secure Key Box**. **Proven blob-gated:** Juggluco's own
`Common/src/main/cpp/libre3/loadlibs.cpp` `dlopen`s `liblibre3extension.so` /
`libcrl_dp.so` and its `processint` JNI delegates to their `process1` symbol;
`KEYSCrypto.java`'s embedded `LIBRE3_APP_PRIVATE_KEYS` are 160-byte SKB-wrapped
blobs, usable only through those functions. There is no clean-room path.

### Vendor-blob bridge (the chosen approach — matches Juggluco)

- `lib/src/libre3/libre3_crypto.dart` — `Libre3Crypto` interface + a
  `MethodChannel('insulink/libre3_security')` implementation.
- `android/…/Libre3SecurityPlugin.kt` — the channel handler mapping each method
  to the native `processInt`/`processBar`/`decrypt` symbols. Loads
  `liblibre3bridge.so`; if absent, returns `no_blob` (G7 builds unaffected).
- `android/app/src/main/jniLibs/README.md` — the `.so` files to supply and how to
  build the `dlopen` shim from Juggluco's `loadlibs.cpp`. **arm64-only.**
- The open parts (CRC-16, FNV-32, activation) stay in Dart. The Rust core stays
  **G7-only** — Libre crypto is the blob, not RustCrypto.

> ⚠️ Legal: shipping Abbott's proprietary binaries has redistribution
> implications (the same ones Juggluco carries). This was an explicit, accepted
> project decision.

## Implementation status

| Piece | State |
|---|---|
| Sensor abstraction (`CgmConnection`/`CgmReading`/`CgmTiming`, per-type service dispatch) | ✅ done, G7 unchanged, tested |
| NFC activation (`Libre3Activation`) | ✅ code + pure-logic tests; NFC frame flags need on-device check |
| Glucose decode (`Libre3GlucoseCodec`) | ✅ one-minute reading tested; historical stride to confirm |
| Backend `ABBOTT_LIBRE3` type | ✅ wired (`SensorType.backendType`) |
| BLE transport + handshake (`Libre3Transport`) | ✅ code ported from Juggluco; fragment framing + event order need on-device check |
| `Libre3Connection` (`CgmConnection`) + service dispatch | ✅ wired — the service builds it for `SensorType.abbottLibre3` |
| Crypto bridge (`Libre3Crypto` + `Libre3SecurityPlugin.kt`) | ✅ interface + channel done; degrades to `no_blob` |
| Abbott `.so` blobs + `liblibre3bridge.so` shim | ⛔ developer-supplied (see `jniLibs/README.md`) |
| Pairing UI sensor-type selector + NFC form | ⛔ pending (add once the pipeline streams) |

The whole clean-room pipeline (NFC → BLE handshake orchestration → decode →
persist) is implemented, compiles, and the pure logic is unit-tested. The two
remaining pieces both require a physical Libre 3: supplying Abbott's binaries +
the `dlopen` shim, and confirming the handshake's fragment framing / event
ordering on a real sensor.

## Sources

- [DiaBLE — `DiaBLE/Libre3.swift`](https://github.com/gui-dos/DiaBLE/blob/main/DiaBLE/Libre3.swift)
- [DiaBLE — Libre 3 discussion #22](https://github.com/gui-dos/DiaBLE/discussions/22)
- [Juggluco](https://github.com/j-kaltes/Juggluco) · [discussion #158](https://github.com/j-kaltes/Juggluco/discussions/158)
- [maheini/FreeStyle-Libre-3-patch](https://github.com/maheini/FreeStyle-Libre-3-patch) (account-ID takeover workflow)
- [AndroidAPS — Libre 3](https://androidaps.readthedocs.io/en/latest/CompatibleCgms/Libre3.html)
