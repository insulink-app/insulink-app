import 'package:flutter/foundation.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';

/// The two activity-mode switches, observed by the profile and the overview.
///
/// Provided above the page tree (`main.dart`) so flipping a switch in the
/// profile redraws the overview at once: the overview is not rebuilt on the way
/// back, so a value read once there would stay stale. The service isolate
/// cannot observe this and reads [ActivityModeSettings] fresh instead; both go
/// through the same keys.
class ActivityModeSwitchState extends ChangeNotifier {
  ActivityModeSwitchState(this._enabled, this._onOverview);

  bool _enabled;
  bool _onOverview;

  /// Whether the activity mode is used at all.
  bool get enabled => _enabled;

  /// Whether the hand choice also sits on the overview.
  bool get onOverview => _onOverview;

  /// Whether the overview shows the choice: asked for, and the mode is on.
  bool get showsOnOverview => _enabled && _onOverview;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await ActivityModeSettings.enabled.save(value);
  }

  Future<void> setOnOverview(bool value) async {
    _onOverview = value;
    notifyListeners();
    await ActivityModeSettings.onOverview.save(value);
  }

  static Future<ActivityModeSwitchState> load() async {
    return ActivityModeSwitchState(
      await ActivityModeSettings.enabled.load(),
      await ActivityModeSettings.onOverview.load(),
    );
  }
}
