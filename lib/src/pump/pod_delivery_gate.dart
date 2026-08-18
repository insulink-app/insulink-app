import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether this build is allowed to activate and command a pod.
///
/// Off by default, and deliberately so: the DASH driver has been verified only
/// against captured protocol vectors, never against a pod. Until someone has
/// confirmed it on real hardware, the paths that deliver insulin must not be
/// reachable by tapping through the app.
///
/// The gate covers activation, basal programming and bolus. It does NOT cover
/// reading status or suspending delivery — a pod that is already running must
/// stay stoppable regardless of any setting, so those paths never consult this.
///
/// Follows the same shape as the other profile settings: a [ChangeNotifier]
/// provided above the page tree, with a static reader for the isolates that
/// cannot observe it.
class PodDeliveryGate extends ChangeNotifier {
  PodDeliveryGate(this._enabled);

  static const _key = 'pod.delivery_enabled';

  bool _enabled;

  /// Whether commands that deliver insulin may be sent.
  bool get allowsDelivery => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    const storage = FlutterSecureStorage();
    await storage.write(key: _key, value: value.toString());
  }

  /// Reads the persisted flag. Defaults to off, including when storage fails.
  static Future<bool> load() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _key) == 'true';
  }

  static Future<PodDeliveryGate> restore() async =>
      PodDeliveryGate(await load());
}
