import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';
import 'package:insulink/src/profile/profile_settings.dart';

/// How far the battery saver reaches.
///
/// [saving] stops the background work the user never asked for directly — the
/// cardio auto-detection (GPS + activity recognition, the app's biggest drain) —
/// and stretches the heart-rate poll. [extreme] additionally drops the live band
/// link and the per-reading forecast fetch, leaving only the glucose pipeline.
///
/// Nothing here ever touches the CGM read pipeline, the alarms or a MANUALLY
/// started training's route: a saver that mutes an alarm or truncates a
/// recording is a bug, not a feature.
enum BatteryMode {
  off,
  saving,
  extreme;

  /// Whether the cardio auto-detection (GPS sampling, activity recognition and
  /// the periodic detection scan) is held back.
  bool get pausesDetection => this != BatteryMode.off;

  /// Whether the Health Connect heart-rate poll runs on the stretched cadence.
  bool get slowsHeartRatePoll => this != BatteryMode.off;

  /// Whether the service stops hosting the live Fitbit band (~1 Hz BLE).
  bool get pausesBand => this == BatteryMode.extreme;

  /// Whether the per-reading forecast fetch is skipped.
  bool get pausesPrediction => this == BatteryMode.extreme;
}

/// Global battery saver: a mode plus the optional [ProfileModeWindow] it runs
/// for. Persisted in secure storage and mirrored to the account.
///
/// Provided above the page tree (see `main.dart`) so the profile selection and
/// the overview banner observe the same value. The work it gates runs in the
/// foreground-service isolate, which can't watch this notifier, so that isolate
/// reads [loadActive] fresh off its watchdog tick — a change takes effect
/// without restarting the service.
class ProfileBatteryState extends ChangeNotifier {
  static const _kMode = 'battery_saver_mode';
  static const _storage = FlutterSecureStorage();
  static const windowStore = ProfileModeWindowStore(
    'battery_saver_window_min',
    'battery_saver_until',
  );

  BatteryMode _mode;
  ProfileModeWindow _window;
  Timer? _expiry;

  ProfileBatteryState(this._mode, this._window) {
    _armExpiry();
  }

  /// The stored mode, even if its window has lapsed — what the settings
  /// segments show while the reset is still being written.
  BatteryMode get mode => _mode;

  /// The mode actually in force. Everything that gates behaviour reads THIS, so
  /// a lapsed saver stops saving without anyone having to clear it.
  BatteryMode get activeMode => _window.lapsed ? BatteryMode.off : _mode;

  ProfileModeWindow get window => _window;

  /// Switch the saver on or off. Turning it on always starts the picked window
  /// fresh, so a mode change never inherits an almost-elapsed run.
  Future<void> setMode(BatteryMode mode) async {
    if (mode == BatteryMode.off) {
      await _apply(BatteryMode.off, _window.stopped);
      return;
    }
    await _apply(mode, _window.started());
  }

  /// Change how long the saver runs, restarting it from now. Also re-arms a run
  /// that already lapsed, which is what makes "give me another 2 h" one tap.
  Future<void> setWindow(int minutes) async {
    await _apply(_mode, _window.withWindow(minutes));
  }

  /// Persists mode + window, notifies, and mirrors them to the account.
  ///
  /// The push is here rather than at the call sites because the overview banner
  /// is not the profile page and so never triggers the leave-the-page push every
  /// other setting relies on — the saver would stick locally while the account
  /// kept the old value, and the next pull would bring it back (the same trap
  /// [ProfileSilentState.setMode] documents).
  Future<void> _apply(BatteryMode mode, ProfileModeWindow window) async {
    if (mode == _mode && window == _window) {
      return;
    }
    _mode = mode;
    _window = window;
    _armExpiry();
    notifyListeners();
    await _storage.write(key: _kMode, value: mode.name);
    await windowStore.save(window);
    await ProfileSettings().push(null);
  }

  void _armExpiry() {
    _expiry?.cancel();
    _expiry = _window.expiryTimer(
      () => _apply(BatteryMode.off, _window.stopped),
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  static Future<ProfileBatteryState> load() async {
    final stored = await loadRaw();
    return ProfileBatteryState(stored.mode, stored.window);
  }

  /// The persisted values with a lapsed run normalised to off, so nothing
  /// downstream has to re-check the clock. Read by [load] and by
  /// [ProfileSettings.collect] — which must not build a notifier (it would leak
  /// the expiry timer), hence the record.
  static Future<({BatteryMode mode, ProfileModeWindow window})>
  loadRaw() async {
    final window = await windowStore.load();
    if (window.lapsed) {
      return (mode: BatteryMode.off, window: window.stopped);
    }
    return (mode: await _loadMode(), window: window);
  }

  /// The mode in force right now — what the service isolate reads off its
  /// watchdog tick (it can't observe the notifier).
  static Future<BatteryMode> loadActive() async => (await loadRaw()).mode;

  static Future<BatteryMode> _loadMode() async {
    final stored = await _storage.read(key: _kMode);
    for (final mode in BatteryMode.values) {
      if (mode.name == stored) {
        return mode;
      }
    }
    return BatteryMode.off;
  }
}
