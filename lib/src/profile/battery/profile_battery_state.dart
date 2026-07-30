import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

/// Global battery saver: a mode, the window it runs for, and the timestamp that
/// window ends at. Persisted in secure storage and mirrored to the account.
///
/// Provided above the page tree (see `main.dart`) so the profile selection and
/// the overview banner observe the same value. The work it gates runs in the
/// foreground-service isolate, which can't watch this notifier, so that isolate
/// reads [loadActive] fresh off its watchdog tick — a change takes effect
/// without restarting the service.
///
/// The end is a stored TIMESTAMP, not a countdown, so it survives the app being
/// closed: [activeMode] just compares against the clock. The window is stored
/// alongside it because the timestamp alone can't say which duration the user
/// picked once time has passed.
class ProfileBatteryState extends ChangeNotifier {
  static const _kMode = 'battery_saver_mode';
  static const _kWindow = 'battery_saver_window_min';
  static const _kUntil = 'battery_saver_until';
  static const _storage = FlutterSecureStorage();

  /// Window/end value meaning "no expiry" — the saver runs until turned off.
  static const permanent = 0;

  /// The temporary windows the settings UI offers, in minutes.
  static const windows = [120, 480];

  BatteryMode _mode;
  int _windowMin;
  int _until;
  Timer? _expiry;

  ProfileBatteryState(this._mode, this._windowMin, this._until) {
    _armExpiry();
  }

  /// The stored mode, even if its window has lapsed — what the settings
  /// segments show while the reset is still being written.
  BatteryMode get mode => _mode;

  /// The mode actually in force. Everything that gates behaviour reads THIS, so
  /// a lapsed saver stops saving without anyone having to clear it.
  BatteryMode get activeMode => _lapsed ? BatteryMode.off : _mode;

  /// The picked window in minutes, or [permanent].
  int get windowMin => _windowMin;

  /// When the saver turns itself off (epoch ms), or [permanent].
  int get until => _until;

  /// What is left of a temporary window; null when off or permanent.
  Duration? get remaining {
    if (activeMode == BatteryMode.off || _until == permanent) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      _until,
    ).difference(DateTime.now());
  }

  bool get _lapsed =>
      _until != permanent && DateTime.now().millisecondsSinceEpoch >= _until;

  /// Switch the saver on or off. Turning it on always starts the picked window
  /// fresh, so a mode change never inherits an almost-elapsed one.
  Future<void> setMode(BatteryMode mode) async {
    if (mode == BatteryMode.off) {
      await _apply(BatteryMode.off, _windowMin, permanent);
      return;
    }
    await _apply(mode, _windowMin, _endFor(_windowMin));
  }

  /// Change how long the saver lasts ([permanent] or one of [windows] minutes),
  /// re-anchoring the end from now. Also re-arms a window that already lapsed,
  /// which is what makes "give me another 2 h" one tap.
  Future<void> setWindow(int minutes) async {
    if (_mode == BatteryMode.off) {
      await _apply(_mode, minutes, permanent);
      return;
    }
    await _apply(_mode, minutes, _endFor(minutes));
  }

  int _endFor(int minutes) {
    if (minutes == permanent) {
      return permanent;
    }
    return DateTime.now()
        .add(Duration(minutes: minutes))
        .millisecondsSinceEpoch;
  }

  /// Persists the three values, notifies, and mirrors them to the account.
  ///
  /// The push is here rather than at the call sites because the overview banner
  /// is not the profile page and so never triggers the leave-the-page push every
  /// other setting relies on — the saver would stick locally while the account
  /// kept the old value, and the next pull would bring it back (the same trap
  /// `ProfileSilentState.setMode` documents).
  Future<void> _apply(BatteryMode mode, int windowMin, int until) async {
    if (mode == _mode && windowMin == _windowMin && until == _until) {
      return;
    }
    _mode = mode;
    _windowMin = windowMin;
    _until = until;
    _armExpiry();
    notifyListeners();
    await _storage.write(key: _kMode, value: mode.name);
    await _storage.write(key: _kWindow, value: '$windowMin');
    await _storage.write(key: _kUntil, value: '$until');
    await ProfileSettings().push(null);
  }

  /// Schedules the self-reset so a temporary saver visibly ends on time while
  /// the app is open. With the app closed nothing has to fire: [activeMode] and
  /// [loadActive] read the clock, and the next [ProfileSettings.collect] writes
  /// the lapsed mode back as off.
  void _armExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final left = remaining;
    if (left == null || left <= Duration.zero) {
      return;
    }
    _expiry = Timer(left, () => _apply(BatteryMode.off, _windowMin, permanent));
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  static Future<ProfileBatteryState> load() async {
    final stored = await loadRaw();
    return ProfileBatteryState(stored.mode, stored.windowMin, stored.until);
  }

  /// The persisted values with a lapsed window normalised to off, so nothing
  /// downstream has to re-check the clock. Read by [load] and by
  /// [ProfileSettings.collect] — which must not build a notifier (it would leak
  /// the expiry timer), hence the record.
  static Future<({BatteryMode mode, int windowMin, int until})>
  loadRaw() async {
    final windowMin = await _loadInt(_kWindow);
    final until = await _loadInt(_kUntil);
    if (until != permanent && DateTime.now().millisecondsSinceEpoch >= until) {
      return (mode: BatteryMode.off, windowMin: windowMin, until: permanent);
    }
    return (mode: await _loadMode(), windowMin: windowMin, until: until);
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

  static Future<int> _loadInt(String key) async {
    return int.tryParse(await _storage.read(key: key) ?? '') ?? permanent;
  }
}
