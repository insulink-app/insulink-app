# Logging

Where log lines go, and what may never be in one.

## Two outlets

- **The developer log panel** (Profile → developer mode). The service isolate
  sends each line to the UI (`'t': 'log'`), `CgmController` keeps them in memory
  and the panel shows them with a copy button. Nothing is written to disk.
- **The system log (logcat)** through `debugPrint`. Anyone who plugs the phone
  into a computer with USB debugging on can read it with `adb logcat`, no root
  needed.

`debugPrint` writes to logcat in every build mode, release included. So a
release build replaces it with a no-op (`ReleaseLogGate`). Each isolate has its
own `debugPrint`, so the gate is applied at every entry point: `main`,
`startCallback` (the foreground service) and the two notification action
callbacks in `alarms.dart`. A new `@pragma('vm:entry-point')` needs it too.

**flutter_blue_plus has its own outlet**, not `debugPrint`: it logs every scan,
connect, write and notification by default, with device ids and characteristic
payloads in the lines. `ReleaseLogGate` switches it off too
(`FlutterBluePlus.setLogLevel`), so a release build is quiet on both outlets.

Debug and profile builds keep printing, so `adb logcat | grep -i flutter`
works while developing. The panel works in every build.

## Never log

- **Key material**: the G7 session key, the pod's long-term key, the account
  data key, tokens, passwords. Not in hex, not truncated, not in any build.
- **Raw frames of a working protocol.** The pod and G7 frame dumps were
  removed once both protocols were stable; they were most of the noise. The
  Libre 3 dumps stay while its handshake is still being worked out
  (`docs/LIBRE3.md`); drop them once it streams.

Log the step and the outcome instead (`-> ${op.name}`, `session key derived`).
