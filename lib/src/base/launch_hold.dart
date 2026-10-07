import 'package:flutter/widgets.dart';

/// Holds back the app's first frame until the first real page is ready, so the
/// splash (Android's native one, or the web demo's in `web/index.html`) hands
/// over straight to that page instead of to the blank frame before it. Both
/// splashes go when Flutter draws its first frame.
///
/// [AuthGate] releases it once it knows its page; later gates (after a sign
/// out) find nothing held, so [release] is safe to call any number of times.
class LaunchHold {
  const LaunchHold();

  static bool _held = false;

  void hold() {
    if (_held) {
      return;
    }
    _held = true;
    WidgetsBinding.instance.deferFirstFrame();
  }

  void release() {
    if (!_held) {
      return;
    }
    _held = false;
    WidgetsBinding.instance.allowFirstFrame();
  }
}
