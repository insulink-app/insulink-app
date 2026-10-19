# Pod key encryption

The app mirrors the pod's long-term key (LTK) and the G7 session key to the
account, so a reinstalled app can still reach a pod on the body
(`PumpSync`, `SensorSync`). Those copies used to sit on the server in plain
form: a database copy or a stolen session was enough to command the pod from
BLE range. They are now sealed with a key the server cannot open.

## The keys

- **Data key** (`DataKey`, `lib/src/auth/data_key/`): 32 random bytes per
  account, kept on the device under `account.data_key`.
- **Envelope** (`DataKeyEnvelope`): the data key encrypted with a key derived
  from the account password. Only this is stored on the server
  (`/user/key/find/`, `/user/key/change/`).

```json
{"version": 1, "kdf": "pbkdf2-sha256", "iterations": 600000,
 "salt": "<16 bytes, base64>", "nonce": "<12 bytes, base64>",
 "wrapped": "<AES-256-GCM ciphertext + 16 byte tag, base64>"}
```

PBKDF2-HMAC-SHA256 runs on the platform (`PasswordKeyPlugin.kt`); a Dart
implementation needs many seconds on a phone at 600 000 iterations. The web
panel builds and opens the same envelope with WebCrypto when the password
changes there (`insulink-panel/src/lib/data-key.ts`); `test/auth/data_key_test.dart`
and the panel's `data-key.check.ts` both check one vector made independently
with Python.

## Sealed fields

`DataKey.seal` is AES-256-GCM with the nonce taken from
HMAC-SHA256(data key, plaintext), written as `v1.` + base64(nonce ‖ ciphertext ‖ tag).
Deterministic on purpose: the sync uploads only when the blob changed, and a
random nonce would make every sync a change. It only reveals whether two
sealed values are equal.

| Blob | Plain field (before / without a data key) | Sealed field |
|---|---|---|
| pump | `long_term_key` | `long_term_key_enc` |
| G7 sensor | `session_key` | `session_key_enc` |

The sealed value goes under its own name, so an older app reading a new blob
finds no key instead of mistaking a sealed one for plain. The pairing code stays
plain: it is printed on the applicator and the panel shows it.

## Backwards compatibility

- Restoring reads both fields. An old plain blob restores as before, with or
  without a data key (`PodRestore.fromBlob`, `SensorSync._sessionKey`).
- A device only seals while it holds a data key, and it only ever saves one
  after the server confirmed it holds the matching envelope. So nothing
  reaches the account sealed with a key a reinstalled app could not get back.
- A device that stays signed in from before this change has no data key and
  keeps mirroring in plain form until the next sign-in, sign-up or password
  change: the password is only at hand then.

## When the key moves

| Moment | What happens (`DataKeySync`) |
|---|---|
| Sign-up | A new data key is created, wrapped and stored on the account, then saved locally. |
| Sign-in | The account's envelope is opened with the password and the key saved. An account without one gets a new key, but only when `/user/key/find/` answered "none" (code 1000): a key created after a failed lookup could replace one whose sealed secrets are still on file. |
| Password change (app or panel) | The key is re-wrapped for the new password and sent with the change, which the api stores in one go. The api refuses a change without it (1006) once the account has a key. |
| Reinstall | Sign-in opens the envelope; the pod offer (`PodRestoreCard`) then opens the sealed LTK. |
| Sign-out, account deletion | The local data key is wiped with the rest of the account state. |

## What it protects against, and what not

Protected: a copy of the database or its backups, a stolen app or panel
session (cookie, refresh token), a server-side bug that leaks pump records.

Not protected: someone who knows the password. With the password alone a
reinstalled app gets the pod key back, which is the point; whoever has the
password can do the same. Sign-in throttling and the password minimum
(insulink-api `docs/ACCOUNT_SECURITY.md`) are what stand there.
