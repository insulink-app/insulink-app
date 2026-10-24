import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Silences the app's own console output in release builds.
///
/// `debugPrint` is NOT stripped from a release build: it is a throttled
/// `print` and lands in logcat, where any app with log access on a rooted or
/// debug-enabled phone reads pod frames, glucose and pairing steps.
/// flutter_blue_plus logs every GATT call the same way. Profile and debug keep
/// both, since that is where `adb logcat` debugging happens.
///
/// Every isolate has its own `debugPrint`, so each entry point calls this: the
/// UI (`main`), the foreground service (`startCallback`) and the notification
/// action isolate.
void silenceLogsInRelease() {
  if (!kReleaseMode) {
    return;
  }
  debugPrint = (String? message, {int? wrapWidth}) {};
  FlutterBluePlus.setLogLevel(LogLevel.none);
}
