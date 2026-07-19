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

All frames are ported byte-for-byte from **Juggluco** (`libre3/NFC.java` +
`cpp/libre3/dp_activation.hpp`), the GPL upstream that works on real hardware —
NOT DiaBLE (whose activation is unverified for Libre 3, and was the source of our
initial wrong bytes; see § "On-device result").

**Frame** — `flags(0x02) ‖ command ‖ manufacturer ‖ params`, where the
manufacturer byte is **read from the sensor UID** (Libre 3 = `0x7A`, not the
Libre 1/2 `0x07`), see [Manufacturer byte](#manufacturer-byte).

**Command selection** — first read patch info with `0xA1` (no params). Then, from
the raw reply (ISO flag byte at `[0]` included), Juggluco's `nfc1[17]`:
`patchInfo[17] == 1 → 0xA0`, else `→ 0xA8`. (Both reach the activation logic; the
byte is a sensor discriminator, NOT a simple "activated?" flag — do not invert.)

**Params** (`dp_activation.hpp`, all little-endian):

```
(activationTime − 1)  UInt32   Unix seconds
account               UInt32   low 32 bits of the LibreView account NUMBER
crc16Activation([0,8)) UInt16
```

- **`account`** — a decimal integer (Juggluco `getlibreAccountIDnumber()`), NOT a
  hashed GUID. Blank ⇒ 0. (Our earlier `fnv32(string)` was a DiaBLE mistake.)
- **`crc16Activation`** — poly `0x1021`, init `0xFFFF`, **refin=true**
  (each input byte bit-reversed), refout=false, xorout=0, stored LE. NOT the
  FreeStyle Kermit CRC. KATs (Juggluco static-asserts):
  `crc(00×8)=0x313E`, `crc(01,00×7)=0xCCBF`, `crc(08,00,00,00,0C,00,00,00)=0x2063`.

**Response** — Juggluco's packed `nfc2` struct (`cpp/libre3/nfc.cpp`), 19 bytes:

```
[0]      zero            ISO success flag 0x00
[1..3)   response        2 bytes, ignored
[3..9)   deviceAddress   BLE MAC, reversed on the wire → find the sensor over BLE
[9..13)  pin             BLE PIN (4 bytes), consumed in the BLE challenge
[13..17) activationTime  UInt32 LE
[17..19) crc16           NOT verified (Juggluco's interpret3NFC2 doesn't either)
```

A 4-byte reply `00 A5 01 <code>` is Juggluco's `nfc2error` (app-level rejection).
Verified by the real captured vector in `nfc.cpp`
(`00 A500 111DB7193218 9A948F6E 9F0A7562 A2FA` → MAC `18:32:19:B7:1D:11`, PIN
`9A948F6E`, A_UTC `1651837599`), used as a KAT.

> ⚠️ The OLD DiaBLE layout was `flag ‖ MAC(6) ‖ PIN(4) ‖ time(4) ‖ crc(2)` — it
> omitted the 2-byte `response` field after the flag, so MAC/PIN read 2 bytes
> early and the (also-wrong) Kermit CRC "mismatched". That was the last bug.

**Account-ID takeover:** the sensor binds to the receiver id it was activated
with. A *fresh* sensor is activated under whatever account number is sent; to
adopt a sensor Abbott's app already activated, pass that LibreView account's
number (Juggluco: *Settings → Exchange data → LibreView → Get account ID*).

<a name="pin-rotation"></a>
### The BLE PIN rotates on every NFC scan (measured — don't try to persist it)

**Each NFC scan of the same sensor returns a NEW BLE PIN, and the sensor honours
only the most recently issued one.** Measured on a real sensor (`…97:33`): a PIN
restored from our backend was `aa6064bd`, an immediate re-scan of that same
sensor returned `7e725938`.

The symptom of using a stale PIN is **not** an error code — the whole handshake
runs perfectly (app cert 162 B → patch cert 140 B → ephemeral 65 B → challenge
23 B), and then the sensor **terminates the link** the moment it gets our
`enc(r1‖r2‖pin)` (`status=19 REMOTE_USER_TERMINATED`, surfacing as a downstream
`writeCharacteristic … Device is disconnected`). It looks exactly like a crypto
bug in the blob. It isn't.

Consequences, both implemented:
- **A Libre 3 cannot be restored from stored credentials** — not from our
  backend, not from a device backup. Juggluco has the same constraint: every new
  device needs its own scan. `SensorSync._libreData` therefore ships only the MAC
  + session info (no PIN, no kAuth — a stale secret on the server buys nothing),
  and the restore offer (`sensor_restore_offer.dart`) sends the user straight
  into the NFC scan sheet (`Libre3ScanFlow`).
- The cached **kAuth dies with the PIN it was derived from**, so a re-scan clears
  it (`CgmController.activateLibre3`), and a rejected pre-authorised handshake
  falls back once to the full cert exchange (`Libre3Connection._handshake`).
- A missing PIN now fails loudly (`Libre3Transport._respondToChallenge`); it used
  to be sent as four zero bytes, which the sensor rejects identically to a stale
  one — an indistinguishable failure that cost real debugging time.

<a name="manufacturer-byte"></a>
> ⚠️ Manufacturer byte: Android reports the ISO 15693 UID LSB-first (the `0xE0`
> tag byte LAST), so the IC manufacturer code is `uid[6]` — the byte before
> `0xE0`. `manufacturerFromUid` reads it; `0x07` is only the fallback.

### On-device result (2026-07, real Libre 3)

First scan of a real sensor: **every custom command was rejected** with ISO
15693 error `01 d3` (byte 0 = `0x01` error flag, byte 1 = `0xD3`, Abbott's
`0xA0–0xDF` custom range) — including read-patch-info (`0xA1`, no params), which
the old code silently ignored (only checked `length > 14`). Captured:

```
patchInfo (0xA1) → 01 d3
cmd 0xA0 params 22da4b6a 00000000 1081 → 01 d3
uid = 316B978E8E007AE0
```

**Root cause of `0xD3` found in the UID.** Android reports the ISO 15693 UID
LSB-first (the `0xE0` tag byte is LAST), so the bytes are `31 6B 97 8E 8E 00 7A
E0` and the IC **manufacturer code is byte 6 = `0x7A`**, not the `0x07` (Texas
Instruments, the Libre 1/2 chip) we were hardcoding. ISO 15693 custom commands
require the tag's own manufacturer code or the IC rejects them — the exact
`0xD3`. Fix: `manufacturerFromUid` reads the code from the polled UID and
`_customCommand` sends it (`0x07` kept only as fallback).

**With `0x7A`, read-patch-info (`0xA1`) now succeeds** and returns a valid patch
info (with the real sensor serial as trailing ASCII):

```
00 | a5 00 01 00 01 00 01 00 60 54 1e 02 04 01 04 0c 01 30 | 4a5537394655544a | 9ebf
^flag OK   patchInfo[14]=0x01 → storage/fresh                ^"JU79FUTJ" serial  ^CRC
```

**But the activate command (`0xA8`) is still rejected — ISO error `0xC2`.** With
the sensor confirmed *fresh* (so `0xA8` is the correct command, not `0xA0`) and
a *non-zero* receiver id (`fnv32("insulink")` = `b1639881`), the params
`16dd4b6a b1639881 <crc>` still return `01 c2`. `0xC2` is an **app-layer** custom
error (`0xA0–0xDF`), not a standard ISO framing error — Abbott validated the
frame shape but rejected its **contents**. So the blocker is the exact activate
**parameter structure**, which is ported from DiaBLE and **unverified for Libre
3**; Libre 3's activate likely expects a different (possibly key-derived
"unlock") payload that can't be inferred from error codes.

**Then `0xA8` returned a NEW error `0xC2`** (not `0xD3`), i.e. an app-layer
rejection of the activate frame's *contents* — with a non-zero receiver id, so
not the account.

**Resolved against Juggluco source** (`libre3/NFC.java` + `dp_activation.hpp`).
Three bugs vs the working reference, all inherited from the DiaBLE port:
1. **Command byte** — Juggluco selects on `nfc1[17]` (`==1 → 0xA0`, else `0xA8`),
   we used `patchInfo[14]` with inverted logic. Our `patchInfo[17]=0x01` ⇒ the
   correct command is `0xA0`, but we sent `0xA8` ⇒ `0xC2`.
2. **CRC** — the payload CRC is poly `0x1021`/init `0xFFFF`/refin=true, NOT the
   FreeStyle Kermit CRC we used. (Now KAT-verified vs Juggluco static-asserts.)
3. **Account** — a raw numeric account (`(uint32)account`), not `fnv32(string)`.

Fixed in `Libre3Activation` (command selection on byte 17, `crc16Activation`,
numeric `account`).

**Then `0xA0` returned `0xB0`** — because `account` was 0 (blank field).
`ScanNfcV.java:154` shows Juggluco itself refuses `getlibreAccountIDnumber()==0`
("zero account ID"); the sensor rejects a zero receiver id. It does NOT validate
the value against Abbott's cloud over NFC, so any non-zero id it can bind to
works for local reading. `_account` falls back to a fixed non-zero
`_defaultAccount` when the field is blank/zero.

**Then the sensor ACCEPTED the command and returned a full 19-byte response**,
which failed only our (wrong) response parser — "CRC mismatch". Root cause: the
DiaBLE response layout omitted the 2-byte `response` field, so MAC/PIN were read
2 bytes early; the CRC was also the wrong algorithm AND is not verified by
Juggluco at all. `parseActivationResponse` now matches the `nfc2` struct and
drops the CRC check. **The NFC activation exchange is now complete end-to-end**
(request + response byte-matched to Juggluco); next gate is the BLE handshake.

## BLE GATT

Data service `089810CC-EF89-11E9-81B4-2A2AE2DBCCE4`:

| Characteristic | UUID suffix `-EF89-11E9-81B4-2A2AE2DBCCE4` |
|---|---|
| Patch Control (write) | `08981338` |
| Patch Status (notify) | `08981482` |
| One-Minute Reading (notify) | `0898177A` |
| Historical Data (notify) | `0898195A` |
| Clinical Data (notify) | `08981AB8` |
| Event Log (notify) | `08981BEE` |
| Factory Data (notify) | `08981D24` |

**All seven are notify-enabled at connect** — the sensor appears to withhold its
streams until the full set is subscribed (see "Historic / backfill" below).

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

Historical/backfill (`0898195A`, decrypted) = a `uint16` start life count then
back-to-back `uint16` glucose values, each **+5 minutes** after the last
(ascending). Ported from Juggluco's `bluetooth.cpp` `HistoryData`: historic
glucose is a **plain `uint16` mg/dL** (no 13-bit mask / error flag — those are
specific to the one-minute reading), range-validated 39–501.

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
| init | notify challenge/cert chars | `initKeys(cachedAuthKey, secVer=1)` |
| `0x01` → COMMAND | start security | — |
| `0x02` → COMMAND | request cert exchange | — |
| CERT_DATA ← app cert | send app cert as fixed 20-B frames (LE16 offset + ≤18 data, zero-padded) | `appCertificate()` |
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
| enable data chars | PATCH_CONTROL→HISTORIC→CLINICAL→EVENTLOG→FACTORY→GLUCOSE→PATCH_STATUS (status last) | `initCipher(kEnc, ivEnc)` |

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

- **The binary comes from Juggluco's own release APK** —
  `lib/arm64-v8a/liblibre3extension.so` (Juggluco already repackaged Abbott's
  crypto; our shim matches it 1:1). **NOT LibreLink** — that app is obfuscated and
  ships differently-named, incompatible libs. Steps:
  `android/app/src/main/jniLibs/README.md`. **arm64-only.** Not committed here.
- **App cert + wrapped private keys are embedded** in `Libre3Keys.kt`, ported
  from Juggluco's GPL `KEYSCrypto.java` (162-B cert, 165-B SKB-wrapped key, per
  security version). `initKeys` = `process1(1)` then `process1(2, key, kAuth)`.
- `android/…/cpp/libre3bridge.cpp` — **shipped** dlopen shim, ported from
  Juggluco's `loadlibs.cpp`: `dlopen`s `liblibre3extension.so`, intercepts its
  `JNI_OnLoad` → `RegisterNatives` to capture Abbott's `process1`/`process2`, and
  exposes them as JNI. Built via `externalNativeBuild` (CMake). Absent the `.so`,
  it returns `no_blob` and the G7 is unaffected.
  - **Anti-tamper patch (load-bearing, aarch64).** Abbott's blob runs an
    anti-instrumentation/root check (a `bl` to a "gum root encoder") from inside
    `JNI_OnLoad`; under the dlopen + fake-VM setup it dereferences invalid state
    and **SIGSEGVs**. `patchAntiTamper` NOPs that `bl` (`04 2E 05 94` →
    `E0 03 00 AA` = `mov x0,x0`) at `OnLoad + 0x119c + 7560 - 4` BEFORE running
    `JNI_OnLoad`, via an mprotect `Unprotect` guard — a faithful port of
    Juggluco's `changelib`/`unprotect.hpp`. The offset + expected bytes are
    specific to Juggluco's `liblibre3extension.so`; on a mismatch it leaves the
    code untouched (never patches a wrong instruction). Juggluco layers extra
    anti-debug around each `process*` call (`has_debugger`/`getsid`/`wrongfiles`,
    a `libinit.so` `PATH` shim) — NOT ported; if the blob still detects
    instrumentation past OnLoad, that's the next thing to port.
- `Libre3SecurityPlugin.kt` — maps the handshake ops onto `process1`/`process2`
  (initKeys=1, setPatchCertificate=4, generateEphemeralKeys=5, setPatchEphemeral=6,
  encryptChallenge=7, decryptChallenge=8, exportAuthKey=9). **Registered on BOTH
  engines**: the UI engine via `MainActivity.configureFlutterEngine`, AND the
  foreground-service engine via `InsulinkApplication`, which adds an FFT
  `TaskLifecycleListener` whose `onEngineCreate` registers the channel. The
  handshake runs in the SERVICE isolate, so without the service-side
  registration `initKeys` throws `MissingPluginException` (FFT only auto-registers
  *pub* plugins, not this hand-rolled channel). Done from `Application.onCreate`
  so it survives a system/sticky service restart when `MainActivity` never runs.
- `lib/src/libre3/libre3_crypto.dart` — `Libre3Crypto` interface +
  `MethodChannel('insulink/libre3_security')` implementation.
- The open parts (CRC-16, FNV-32, activation) stay in Dart. The Rust core stays
  **G7-only**.

**Clean-room data path (done):** the AES-128-CCM decrypt (`initcrypt`/`intDecrypt`
in Juggluco — its OWN code, not the blob) is `lib/src/libre3/libre3_ccm.dart`
using pointycastle's audited `CCMBlockCipher`, keyed by the kEnc/ivEnc from
`decryptChallenge`. RFC-3610 verified (`test/libre3/libre3_ccm_test.dart`). The
`ponytail:`-marked Libre specifics (nonce = ivEnc, 4-byte MAC, AAD) need an
on-device capture to confirm. The **app certificate** loads from
`assets/libre3/app_certificate.bin` — the proprietary `LIBRE3_APP_CERTIFICATES_B`
bytes the user drops in (see that folder's README).

> ⚠️ Legal: shipping Abbott's proprietary binaries has redistribution
> implications (the same ones Juggluco carries). This was an explicit, accepted
> project decision.

## Historic / backfill (gap-fill)

**The problem:** the Libre streams one value/minute on One-Minute (`0898177A`,
decrypt channel 3). When the BLE link drops for a few minutes, those minutes are
lost from the live stream. Filling that gap from the **sensor's own buffer** is
what "backlog"/backfill means.

Two separate things are often confused — keep them distinct:

- **In-memory history persistence (DONE).** `Libre3Connection` seeds `_byTime`
  from the store once per process (`_historyLoaded`), persists `sensorStart`
  (`_anchorSensorStart`/`saveSensorStart`), and the store caps readings by a **24 h
  time window** (`saveReadings`, cadence-independent — a fixed point count gave the
  1-min Libre only ~5 h). This keeps the chart across reconnects/restarts. It is
  **NOT** sensor-buffer gap-fill — it only re-shows data we already received.
- **Sensor-buffer gap-fill (implemented as a Juggluco-faithful port).** Retrieving
  the missed minutes from the patch — resolved below.

### The full notify set must be enabled (on-device confirmed)

The data service (`089810CC`) has **seven** characteristics; all seven are enabled
at connect in the documented order (PATCH_CONTROL → historic → clinical → eventLog
→ factory → GLUCOSE → PATCH_STATUS, status last) and return `GATT_SUCCESS`.
Glucose (ch3, every minute) and **patchStatus** (`08981482`, ch2) push
automatically; historic (`0898195A`, ch4) is **request-based** (below).

### The command (request-based, ported from Juggluco)

Resolved from Juggluco's `Libre3GattCallback` source: `fillHistory` sends
`Natives.libre3ControlHistory(1, from)` and the sensor replies on `0898195A`. The
earlier 3-byte guess `[0x01, lifeCountLE16]` was length-rejected
(`GATT_INVALID_ATTRIBUTE_LENGTH`) because the real command is a **7-byte struct,
then AES-CCM-encrypted** to a 13-byte frame — not a short plaintext. The full
path, byte-exact to Juggluco:

1. **Plaintext** (`ControlHistory` = `RequestData{ kind={1,0}, arg=1, from }`,
   packed LE): `01 00 01 <from as int32 LE>` = 7 bytes
   (`Libre3Transport._backfillCommand`). `from` is the start life count, **snapped
   to a 5-min boundary** with Juggluco's 16-count margin `((from-16)/5)*5`
   (`historicBoundary`) — the historic buffer is keyed at 5-min steps, so an
   unsnapped start returns no records.
2. **Encrypt** on the control channel (kind 0): `Libre3Crypto.encrypt(0, plain)`
   = `intEncrypt` — 13-byte nonce `seq(2 LE) ‖ packetDescriptor[0]={00,00,00} ‖
   ivEnc(8)`, no AAD, 4-byte MAC; frame is `ciphertext ‖ tag(4) ‖ seq(2 LE)` =
   13 bytes; `outCryptoSequence` starts at 1 and increments per command.
3. **Write** the encrypted frame to Patch Control `08981338` **raw**
   (`setValue(encr)`, with response — Juggluco's `sendcommandonly`), NOT the
   2-byte-offset 20-byte framing the cert/challenge writes use. Framing the
   command trips `GATT_INVALID_ATTRIBUTE_LENGTH` — the write must be the bare
   13-byte encrypted payload.

Gated to real gaps only (`Libre3Connection.backfillStartLifeCount`), behind the
`_activeBackfillWrite` kill-switch (default on). The reply decode is
`Libre3GlucoseCodec.parseHistorical` (see "Reading layout" — ascending +5 min,
plain `uint16`), unit-tested.

### Confirmed working on real hardware (2026-07)

Full round trip observed on a physical Libre 3: a real gap → snapped request
`010001d0480000` (`from` 18640) → `patch-control write ok` → sensor replies on
`historic` (ch4), 20 B → 14 B decrypted → 2 valid records merged into the chart.
This also settled the last open question — the sensor accepting the encrypted
command and replying confirms the outgoing CCM path (no AAD, `outCryptoSequence`
from 1, channel 0, raw write). The patch-control notify (`access1100`, channel 1)
is a bare ACK, not data — we raw-log it and ignore it.

Notes:
- Backfill fills at the sensor's **5-min historic cadence**, not the 1-min live
  cadence — a short gap yields one or two points, the zero-padded tail of the
  6-slot frame is dropped by the 39–501 range check.
- Encrypt/decrypt are also RFC-3610 verified and the control-channel frame
  round-trips in `libre3_ccm_test.dart`; `historicBoundary` is unit-tested.
- `Libre3Connection._minBackfillGapMin` gates how big a gap triggers a request —
  keep it at **10 min** for production (a low value re-requests on every minor
  reconnect).

## Implementation status

| Piece | State |
|---|---|
| Sensor abstraction (`CgmConnection`/`CgmReading`/`CgmTiming`, per-type service dispatch) | ✅ done, G7 unchanged, tested |
| NFC activation (`Libre3Activation`) | ✅ end-to-end on a real sensor — re-ported byte-for-byte from Juggluco (mfg `0x7A` from UID, command on `patchInfo[17]`, `crc16Activation` + `nfc2` response KAT-verified, numeric account, non-zero fallback). Sensor accepts the command and returns MAC/PIN. |
| Glucose decode (`Libre3GlucoseCodec`) | ✅ one-minute reading tested (incl. temperature); historical stride to confirm |
| Historic / backfill (gap-fill from sensor buffer) | ✅ working on real hardware — 7-byte `ControlHistory` → AES-CCM ch0 → raw write to `08981338` (boundary-snapped `from`); sensor replays on `historic` ch4, decoded ascending +5 min into the chart. Unit-tested; confirmed end-to-end 2026-07. |
| Backend `ABBOTT_LIBRE3` type | ✅ wired (`SensorType.backendType`) |
| BLE transport + handshake (`Libre3Transport`) | ✅ code ported from Juggluco; fragment framing + event order need on-device check |
| `Libre3Connection` (`CgmConnection`) + service dispatch | ✅ wired — the service builds it for `SensorType.abbottLibre3` |
| Crypto bridge (`Libre3Crypto` + `Libre3SecurityPlugin.kt`) | 🔧 channel registered on BOTH engines (fixed service-isolate `MissingPluginException`); native anti-tamper `bl` NOP'd in `libre3bridge.cpp` (fixed `JNI_OnLoad` SIGSEGV); handshake re-test pending |
| Pairing UI (sensor-type selector + NFC activation form) + de/en locale | ✅ done — pick "FreeStyle Libre 3", scan to activate |
| Native dlopen bridge (`libre3bridge.cpp` + CMake + Kotlin) | ✅ shipped, compiles into the APK; bridges Abbott `process1`/`process2` |
| AES-128-CCM data path (`Libre3Ccm`, pointycastle) | ✅ done, RFC-3610 tested; Libre nonce/MAC wiring marked for on-device check |
| App cert + wrapped private keys (`Libre3Keys.kt`, from Juggluco GPL) | ✅ embedded; `initKeys`/`appCertificate` ported faithfully |
| Abbott `liblibre3extension.so` (from **Juggluco's** APK) | ⛔ user-extracted — `jniLibs/README.md`. The ONE remaining artifact. |

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
