import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Keeps a release build from writing to the system log.
///
/// `debugPrint` goes to logcat in every build mode, and logcat is readable by
/// anyone who plugs the phone into a computer with USB debugging on. Its lines
/// carry glucose values, pod states and sensor ids, so a release build drops
/// them. Debug and profile builds keep printing; the developer log panel keeps
/// its lines in memory either way.
///
/// Each isolate has its own `debugPrint`, so every entry point applies this:
/// `main`, the foreground service and the notification action callbacks.
///
/// flutter_blue_plus does not go through `debugPrint`: it logs every scan,
/// connect, write and notification through its own channel, on by default, so
/// it is switched off here as well. Its lines carry device ids and
/// characteristic payloads of the sensor, the pod and the band.
class ReleaseLogGate {
  const ReleaseLogGate();

  void apply() {
    if (kReleaseMode) {
      debugPrint = _discard;
      FlutterBluePlus.setLogLevel(LogLevel.none);
    }
  }

  static void _discard(String? message, {int? wrapWidth}) {}
}
