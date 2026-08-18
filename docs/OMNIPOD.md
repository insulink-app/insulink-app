# Omnipod DASH

Status of the DASH pump support, the byte-level protocol notes, and — most of
this file — the hazard analysis. Read the hazards section before touching
anything under `lib/src/pump/protocol/`.

> This is an interoperability/research project and **not a medical device**. The
> code here can command an insulin pump. Nothing in this document is a claim
> that doing so is safe.

## Status

The **driver is complete and verified offline**, up to but not including a live
pod. Every byte-level encoder and decoder is pinned by captured vectors, and the
pairing, session and activation SEQUENCES are exercised against a scripted pod
that computes its own side of the handshake. None of it has touched real
hardware, so delivery is locked behind [PodDeliveryGate](../lib/src/pump/pod_delivery_gate.dart),
which is off by default.

| Layer | State | Verified by |
|-------|-------|-------------|
| CRC-16 / CRC-32 / additive checksum | done | captured command trailers, IEEE reference |
| `MessagePacket` header + parse | done | captured encrypted frame, byte-exact both ways |
| BLE fragmentation / reassembly | done | round-trip every length 1–250, drop + corruption |
| Keyed payload envelope (`SP1=`, `S0.0=`) | done | round-trip + malformed input |
| X25519 (Rust) | done | RFC 7748 vector, low-order-point rejection |
| LTK pairing ladder (CMAC) | done | captured pairing; plus an independently computed pod side agreeing on the key |
| Milenage (EAP-AKA core) | done | 4 captured sessions incl. resynchronisation |
| EAP-AKA message + attributes | done | captured challenge, byte-exact round trip |
| AES-CCM session cipher | done | captured encrypt + decrypt, tamper rejection |
| Commands: status, version, set-id, deactivate, silence, stop, bolus | done | captured frames, byte-exact |
| Commands: alerts (4 configurations) | done | captured frames, byte-exact |
| Commands: basal (3 schedules), temp basal (4 rates) | done | captured frames, byte-exact |
| Responses: status, version, set-id, NAK + dispatch | done | 5 captured pod statuses, NAK, envelope validation |
| Message I/O (request-to-send / fragments / success) | done | scripted pod, incl. multi-fragment and silence |
| Pairing flow | done | scripted pod computing its own LTK |
| Session establishment flow | done | scripted pod computing its own challenge response |
| Encrypted command session + acknowledgement | done | real captured encrypted reply, decoded end to end |
| Activation sequence (two phases, resumable) | done | scripted pod; incl. resume not re-delivering insulin |
| Delivery guard (limits, staleness, reservoir) | done | unit tests |
| Pod state persistence | done | unit tests over an in-memory keystore |
| Backend mirror + restore (`/pump/register/`, `/pump/update/`, `/pump/current/`) | done | API controller tests; app side reviewed |
| Bolus delivery from the injection sheet | done | unit tests over a scripted pod |
| BLE link + scanner | written | **unverified — needs hardware** |
| Pump page: status, stop, deactivate, acknowledge alerts | done | builds and analyses; not exercised on a device |
| Activation wizard UI | **not built** | — |
| Basal/temp basal wired to a UI | **not built** — encoders done, `BasalProfile` is the obvious source | — |
| Background service, API sync, alarms | **not built** | — |

Tests: `flutter test test/pump/` (139) and `cd rust && cargo test` (9). The
pairing and flow tests load the host Rust library, so `cargo build` has to have
run first.

> Note: `flutter build apk` currently fails in `camera_android_camerax` under
> Gradle 9.7.0. That failure predates this work and is unrelated to it —
> confirmed by building with these changes stashed. `flutter build bundle`
> (the Dart half) succeeds.

### Bolus delivery from the injection sheet

The injection sheet delivers through the pod when one is paired and the delivery
gate is open, and otherwise behaves exactly as it did before — the user injects
and the app records it. `BolusDelivery` (`lib/src/injection/bolus_delivery.dart`)
makes that choice; `PodDeliveryGuard` runs in front of the pod with the user's own
`ProfileBolusState.maxBolus` as its ceiling, so the limit the sheet already
enforces is the limit the pump enforces.

**What gets recorded is one-directional, and this is the load-bearing rule:**
insulin is written to the meal log only once the pod has confirmed it. A refused
dose, or one whose fate is unknown, records the meal with **zero** insulin and
says so on screen. Understating insulin is correctable by logging it afterwards;
overstating it silently suppresses the next dose through IOB, which is the worse
of the two mistakes. The carbs are always recorded, because the user did eat them.

A refusal or an unknown outcome does not close the confirm page. The message stays
next to a button that now reads "log without bolus", so the user cannot leave
believing a dose went in. `Meal.deliveredByPump` marks the pump-given doses, which
are the ones whose recorded amount is worth doubting if a pod later turns out to
have stopped mid-delivery.

### Surviving an app reset

A pod answers only to the controller that activated it, and that binding cannot be
redone. So losing the long-term key locally means losing the ability to STOP a pod
that is still on the body — the same hazard as the section below, arrived at by
accident instead of by design.

`PumpSync` (`lib/src/pump/pump_sync.dart`) therefore mirrors the pairing to the
user's account the moment it completes, and `PodRestoreCard` offers it back when
the app has no pod but the account does. It follows `SensorSync` exactly, including
the opaque blob: the server stores bytes it never interprets, which is required
here for the licensing reason above, not just for tidiness.

Two things worth knowing:

- **The counters lag.** The key is pushed immediately; the command and session
  counters are only refreshed opportunistically after each operation. A restored
  app may therefore be behind. That is recoverable — a stale command counter earns
  one refusal, a stale session counter one resynchronisation round, both already
  handled. Being keyless is what is not recoverable, which is why the key is not
  treated as lazily as the counters.
- **A restore is never offered while a pod is paired locally.** Adopting a second
  identity would replace the key to a pod that may still be delivering.
- The stored record carries the pod's own expiry, so it ages out with the pod it
  describes rather than lingering as a usable key.

## Why there is no read-only mode

The obvious safe-looking first step — "just read pod status, don't command
anything" — **does not exist for Omnipod**, and it is worth being explicit about
why, because it changes what this feature can ever be.

A pod's BLE link is exclusive and encrypted with a long-term key established at
activation. There is no passive read: to see any pod data at all, the pod has to
be activated *by us*, with our controller id. The `SET_UNIQUE_ID` command that
does this is **irreversible for the life of the pod** — afterwards the user's own
PDM can no longer command that pod.

The consequence is the single most important safety property of this feature:

> **Once Insulink activates a pod, Insulink is the only thing that can stop it.**
> A pod delivering basal that the controlling app cannot reach can only be
> stopped by physically tearing it off.

So "pair and read" is not a safer subset of "pair and control" — it is strictly
more dangerous, because it takes on the obligation to stop delivery without
building the means to. Any shipped version of this feature must be able to
suspend and deactivate a pod reliably, or it must not activate one at all.

## Hazards and what stands against each

| Hazard | Consequence | Mitigation in this code |
|--------|-------------|-------------------------|
| Unit→pulse conversion error | wrong dose, silently | `PodBolusAmount` never carries a double past construction; a dose off the 0.05 U grid is refused, not rounded |
| Encoder bug in the bolus frame | wrong dose, silently | `PodProgramBolusCommand.encoded` reads the pulse count back out of the finished bytes from all three places the frame repeats it, plus its own CRC, and throws instead of returning a frame that disagrees |
| Corrupted frame accepted as a command | arbitrary pod behaviour | CRC-16 per command, CRC-32 per reassembled payload, AES-CCM tag per message; all three refuse rather than pass through |
| Forged or replayed pod message | false status → wrong dosing decision | AES-CCM authenticates the 16-byte header as associated data; nonce counter carries a direction bit so the two sides never share a nonce |
| Man-in-the-middle during pairing | attacker-chosen key | pod confirmation value compared in constant time before pairing is accepted; low-order X25519 points rejected in Rust |
| Retried command delivered twice | double dose | 4-bit command sequence number — the pod recognises and ignores a repeat. **Never reuse a number for a different command and never skip one** |
| Stale pod status | bolus stacked on a running one | `PodDeliveryGuard` refuses any bolus decided on a status older than 2 min |
| Repeat taps / retry loop | stacked doses | rolling one-hour ceiling in `PodDeliveryGuard`, on top of the per-bolus cap |
| Bolus larger than the reservoir | partial delivery, wrong IOB | refused when the pod reports a measurable reservoir |
| Pod in alarm or not running | command silently ignored | lifecycle checked before every bolus |
| Delivery command reaching a pod mid-activation | undefined | `PodLifecycleStatus.acceptsDelivery` gates it |

Two design rules that came out of this and should not be relaxed:

1. **Refuse, never clamp.** Every guard rejects and reports. Quietly delivering
   less than the user asked for is its own dosing error and is harder to notice
   than a refusal.
2. **The stop path carries no arithmetic.** `PodStopDeliveryCommand` contains no
   computed dose — only which streams to halt — so there is no number in it that
   can be wrong. It must never be placed behind a check that can fail closed.

## Protocol notes

Transport is BLE GATT, service `1a7e4024-e3ed-4464-8b7e-751e03d0dc5f`, with two
characteristics: CMD `1a7e2441-…` and DATA `1a7e2442-…`. Pods advertise service
`4024` and encode pod id, lot and sequence number across nine 16-bit service
UUIDs in the scan record.

Above that, four layers stack:

1. **Fragments** — 20-byte BLE writes, indexed, with a CRC-32 over the whole
   payload (`payload_fragments.dart`, `payload_reassembler.dart`).
2. **Messages** — 16-byte `TW`-prefixed header carrying source, destination,
   sequence and type (`message_packet.dart`).
3. **Security** — pairing (X25519 + AES-CMAC ladder → LTK), then per-session
   EAP-AKA/Milenage → CK, then AES-CCM on every message
   (`key_exchange.dart`, `milenage.dart`, `session_cipher.dart`).
4. **Commands** — the same opcodes the older Eros pods use, wrapped in a keyed
   envelope (`S0.0=` … `,G0.0`) (`pod_command.dart` and siblings).

Details worth not rediscovering:

- **The message length field is 11 bits split across two bytes** (`size >> 3`,
  `size << 5`), and for an encrypted message it counts the payload *without* the
  8-byte tag once the tag is attached — but *with* the plaintext length while the
  tag is being computed. That is what `toBytes(forEncryption:)` is for; getting
  it wrong breaks the CCM associated data, not the framing, so it fails as a tag
  mismatch rather than a parse error.
- **The CRC-16 is not a textbook CRC-16.** The table is the standard 0x8005
  MSB-first one, but the pod's update loop indexes it by the *low* byte of the
  running value. Generating the table and keeping the odd loop is verified
  against three captured command trailers.
- **A delivery command is always preceded by a 0x1a interlock** carrying the same
  pulse count plus an additive checksum of it. Both go in one frame.
- **`ProgramBolus` repeats the dose three times**: interlock pulse count,
  interlock program element, and tenths-of-a-pulse in the bolus body. This
  redundancy is the pod's, and the read-back check makes use of it.
- **Reservoir `0x3FF` means "more than it can measure"**, not 1023 pulses.
  `reservoirUnits` returns null there — never format it as a number.
- **NAK `illegalSecurityCode` (0x14)** is a sequence desync and carries a resync
  counter instead of a lifecycle. It must be resynced, never blindly retried.
- **There are THREE counters and mixing them up is the easiest way to break
  this.** The *pod command sequence* is a persisted 4-bit counter in the command
  header, incremented once per command, and it is what makes a retried command
  run once. The *message sequence* lives inside a session and also advances for
  acknowledgements, so it drifts away from the command counter immediately. The
  *EAP sequence* is a third persisted counter, one per session attempt, which the
  pod refuses to see twice. `PodController` keeps the command counter itself and
  persists it after every operation; it deliberately does NOT adopt the status
  reply's `lastProgrammingSequenceNumber`, which only moves for delivery programs
  and would therefore step the counter backwards onto a number already used.
- **The EAP counter is reserved before use, not after.** Losing a value to a
  crashed handshake costs nothing; reusing one costs a resynchronisation round.

## What still has to happen before this can touch a pod

1. **Hardware verification of everything above the vectors.** The captured
   vectors prove the encoders agree with a known-good implementation, and the
   scripted-pod tests prove the sequences are ordered correctly. Neither proves
   the driver behaves on a live BLE link — timing, reconnects, and the pod
   dropping the link mid-exchange are all untested.
2. The activation wizard UI, which has to walk the user through filling, priming
   off the body, attaching, and cannula insertion — and must state the
   single-controller consequence BEFORE `SET_UNIQUE_ID` is sent.
3. A background service, if delivery is ever to continue with the app closed.
   The CGM side already has one (`cgm/service/`); the pod would need the same
   treatment, and the pod state store is per-isolate cached like `CgmStore`, so
   it needs the same `reload()` discipline.
4. The decision about the injection UI above.

### What to check first with a real pod

In rough order of how likely each is to be wrong, and how much it matters:

1. **Pairing and session establishment end to end.** The crypto is pinned, but
   the control-word framing (`request-to-send` / `clear-to-send` / `success`) is
   only verified against my own scripted pod, which cannot disagree with my
   reading of it.
2. **The command sequence number across reconnects.** A wrong value gets a NAK
   with `illegalSecurityCode`; the resync path exists but has never run against
   a pod.
3. **`GET_STATUS` on a running pod**, compared against the PDM's own display —
   the cheapest way to confirm the status decoder against reality.
4. **Only then** anything that delivers, starting with the smallest bolus the
   pod accepts (0.05 U) and checking the reservoir count moves by exactly one
   pulse.

## Provenance and licence

The protocol layout, the magic constants and the test vectors come from
**AndroidAPS** (`pump/omnipod/common/bledriver`), which is **AGPL-3.0**. The app
was therefore relicensed from GPL-3.0 to **AGPL-3.0**; the Juggluco-derived CGM
files stay GPL-3.0, which both licences permit (GPL-3.0 §13 / AGPL-3.0 §13). Per
file: `NOTICE`.

**One constraint follows from this and is easy to violate by accident:** AGPL-3.0
§13 obliges anyone offering a modified version over a network to publish its
source. The app is not a network service, so it does not apply today — but
`insulink-api` is. Pod protocol logic must therefore stay in the app. The API may
store pump state as an opaque blob it never interprets; porting any of the driver
into it would turn the API into an AGPL network service.

Additional protocol background, from which no code was taken: the openomni wiki
(the Eros-level message layer that DASH reuses) and Loop's OmniBLE.
