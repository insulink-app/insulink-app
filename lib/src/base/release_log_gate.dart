import 'package:flutter/foundation.dart';

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
class ReleaseLogGate {
  const ReleaseLogGate();

  void apply() {
    if (kReleaseMode) {
      debugPrint = _discard;
    }
  }

  static void _discard(String? message, {int? wrapWidth}) {}
}
