# Dexcom G7 Authentication Handshake — Byte-Level Spec

Reverse-engineered from open-source implementations (Juggluco, DiaBLE, G7SensorKit,
xDrip+) and cross-checked against the opcode bytes we extracted from the official
app. **Juggluco is the authoritative reference** — the only fully open, working
EC-JPAKE implementation. DiaBLE provides a verbatim wire trace that agrees with it.

## ✅ Resolved: core ported to p256 and byte-validated

The working open clients do **not** use mbedTLS's `ecjpake_*` API — they roll their
own EC-JPAKE on raw EC point math. The G7 wire payload is a **raw `X‖Y ‖ X‖Y ‖ proof`
concatenation (64+64+32 = 160 bytes)**, not mbedTLS's TLS/ASN.1 framing.

`rust/src/api/jpake.rs` now implements this as a hand port of Juggluco's
`ecJPake.cpp` on the RustCrypto `p256` crate (mbedTLS dropped entirely). It is
**byte-validated against Juggluco's compiled reference**: `cargo test` checks the
round-1 payload, round-3 payload, derived session key (`6f83…673f`), and the AES
key-confirmation all match Juggluco's `testmulti()` output exactly. A simulated
two-party handshake also confirms both sides derive the same key.

## GATT characteristics (service F8083532-…)

| Short | Role |
|---|---|
| `3534` | **Control** — glucose `0x4E`, backfill cmd `0x59`, version `0x4A`/`0x52` |
| `3535` | **Authentication** — short opcode commands (our target `f8083535-…`) |
| `3536` | **Backfill** (notify) |
| `3538` | **J-PAKE / cert bulk data** — large payloads, `WRITE_NO_RESPONSE` |

Key: short opcodes go on `3535`; the bulky ~160 B J-PAKE/cert bytes go on `3538`,
**interleaved**. Everything chunks at a hard **20 bytes** regardless of MTU.

## Full pairing sequence (phone = display/writer, sensor = notifier)

```
enable notify on 3535 and 3538

# 1. EC-JPAKE — 3 phases, round material on 3538, index on 3535
write  3535  0A 00            ; phase 0
notify 3538  120 B            ; sensor round payload (X‖Y‖X‖Y‖proof)
notify 3535  0A 00 00         ; ack {0A, status, phase}
notify 3538  40 B
write  3538  160 B            ; phone round payload
write  3535  0A 01            ; phase 1   (repeat notify/write pattern)
write  3535  0A 02            ; phase 2

# 2. AES key-confirmation (proves possession of J-PAKE key)
write  3535  02 + nonce8 + 02 ; AppKeyChallenge: 0x02 ‖ random8 ‖ 0x02
notify 3535  03 + hash8 + chal8 ; ChallengeReply: 0x03 ‖ tokenHash8 ‖ challenge8
write  3535  04 + AES8         ; HashFromDisplay: 0x04 ‖ AES8(key, challenge8)
notify 3535  05 01 02          ; StatusReply: {0x05, authed=1, status=2(pair)/1(reconnect)}

# 3. Certificate exchange (opcode 0x0B), phases 0/1/2, bulk on 3538
write  3535  0B 00 + len(LE32)
...

# 4. Proof of possession (opcode 0x0C): ECDSA-P256 signature
write  3535  0C + random16
notify 3535  0C 00 + 16 B
write  3538  signature (raw r‖s, 64 B)

# 5. Bonding
write  3535  06 19            ; proceed/keep-alive
write  3535  07               ; RequestBond  -> notify 07 00
notify 3535  08 01            ; RequestBondResponse -> OS createBond

# then control traffic on 3534 (4A/52 version, EA params, 4E EGV, …)
```

**Reconnect (already bonded)** skips J-PAKE/cert/PoP: just `01 00` → `02+8+02`
→ `03+16` → `04+8` → `05 01 01`, then control traffic.

## Per-opcode payloads (confirmed)

- **`0x01` TxIdChallenge** — phone writes `01 00`; opens the exchange (reconnect path).
- **`0x02` AppKeyChallenge** — phone writes `02 ‖ random8 ‖ 02` (10 B).
- **`0x03` ChallengeReply** — sensor notifies `03 ‖ tokenHash8 ‖ challenge8` (17 B).
- **`0x04` HashFromDisplay** — phone writes `04 ‖ AES8(key, challenge8)` (9 B).
  AES = **AES-128-ECB single block, no IV**: the 8-byte challenge is doubled to 16 B,
  encrypted, first 8 B returned. Key = first 16 B of the J-PAKE shared secret.
- **`0x05` StatusReply** — `{05, authed, status}`; `data[1]==1` authed, `data[2]` 1=reconnect/2=pair.
- **`0x06` KeepConnectionAlive** — `{06,0x19}` proceed, `{06,0x01}` keep-alive.
- **`0x07` RequestBond** — `{07}` → sensor `07 00`.
- **`0x08` RequestBondResponse** — sensor `08 01` → call OS `createBond`.
- **`0x0A` ExchangePakePayload** — `{0A, num}` on 3535 (num=0/1/2 selects round);
  160-byte round material on 3538.

## EC-JPAKE specifics (port from Juggluco `ecJPake.cpp`)

- Curve secp256r1, hash SHA-256. Pairing code (4 chars) = J-PAKE password.
- **160-byte round payload** = `pub1(X32‖Y32) ‖ pub2(X32‖Y32) ‖ proof32`, raw affine
  coords, **no 0x04 point prefix, no length prefixes**.
- Round selected by the `{0A,num}` index byte, not an in-payload tag.
- Schnorr ZKP hash *inputs* (internal only) DO use `len(BE32) ‖ uncompressed-point(65)`
  per RFC-8235, plus party labels: party A = `"client"` (`63 6c 69 65 6e 74`),
  party B = `37 56 27 67 56 27`.
- Round 3 uses a hardcoded exponent in Juggluco:
  `fbc971b837e9491e45a4179ed33865c508a1e0a1d350f5af0f96370695fdc393`.
- **Session key** = `SHA256( X(shared_point) )[0:16]` (AES-128). Used ONLY for the
  `0x04` challenge. **Glucose/backfill are PLAINTEXT** — no per-packet encryption.

## Still not fully open

The exact `0x0B` certificate-chain transcript and `0x0C` proof-of-possession KDF are
only partially revealed (Juggluco embeds a cert chain + native sign; DiaBLE embeds
cert hex but stubs the logic). Look at Juggluco `getchallenge`/`getDexCertSize` +
embedded certs, and xDrip's `libkeks` (`jamorham/keks/Calc.java`).

## Source references

- **Juggluco** (branch `primary`): `Common/src/dex/java/tk/glucodata/DexGattCallback.java`
  (UUIDs 306–317; phases 85–97; 0x02 428–436; 0x04 540–544; status 548–553; bond
  493–495; 0x0B 76–84; 0x0C 696–705; 0x0A 899–903; chunking 368–415); and
  `Common/src/main/cpp/dexcom/ecJPake.cpp` (byteify 410–427; mkhash 308–331; labels
  333–334; round3 exp 488–489; mkSharedKey 526–548; AES 672–683; pin 813); and
  `java.cpp` (16-byte key 429–435; plaintext glucose 192–222, 381–398).
- **DiaBLE** (`main`): `DiaBLE/DexcomG7.swift` (opcodes 18–50; wire trace 53–133;
  160-B layout 511–531; coresdk skeleton 735–800), `DiaBLE/Dexcom.swift` (UUIDs 47–71;
  chunker 178–186).
- **G7SensorKit** (`main`): `Messages/AuthChallengeRxMessage.swift` (parses 0x05 only;
  relies on OS bonding). No J-PAKE.
- **xDrip+** (`master`): `Ob1G5StateMachine.java` — G7 delegates to closed `parent.plugin`;
  no open EC-JPAKE.
