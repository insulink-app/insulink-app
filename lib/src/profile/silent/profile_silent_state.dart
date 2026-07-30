import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';
import 'package:insulink/src/profile/profile_settings.dart';

/// How far the user's mute reaches.
///
/// [tones] exists for the night-stand case: the phone still buzzes and the alarm
/// still appears, only the audible tone is held back. [all] is the hard mute —
/// nothing is shown or played at all, which is safety-relevant and therefore the
/// only mode gated behind a warning + biometric check.
enum SilentMode {
  off,
  tones,
  all;

  /// Whether this mode holds back the notification itself.
  bool get mutesNotifications => this == SilentMode.all;

  /// Whether this mode holds back the alarm tone. Muting everything mutes the
  /// tone too — a notification that never shows has nothing to sound for.
  bool get mutesSound => this != SilentMode.off;
}

/// Global "silent mode": mutes either the alarm tones alone or every glucose
/// alarm and sensor notification, for good or for a picked window
/// ([ProfileModeWindow]). It's a user-facing mute, persisted in secure storage.
///
/// Provided above the page tree (see `main.dart`) so the profile selection and
/// the overview indicator observe the same value. The alarm code runs in the
/// foreground-service isolate, which can't watch this notifier, so it reads the
/// mode fresh from storage via [load] on every reading (no restart needed for a
/// change to take effect) — and because [load] resolves the window itself, a
/// lapsed mute un-mutes the alarms with no other code involved.
///
/// The tri-state is persisted as the two ORIGINAL boolean keys rather than one
/// enum string, because the panel coerces `silent_mode` to a bool and writes it
/// straight back into the shared settings blob — an enum string would come back
/// from a panel save as `false` and silently unmute. The window keys are new and
/// untyped there, so they pass through untouched.
class ProfileSilentState extends ChangeNotifier {
  static const _kSilent = 'silent_mode';
  static const _kTones = 'silent_tones';
  static const _storage = FlutterSecureStorage();
  static const windowStore = ProfileModeWindowStore(
    'silent_window_min',
    'silent_until',
  );

  SilentMode _mode;
  ProfileModeWindow _window;
  Timer? _expiry;

  ProfileSilentState(
    this._mode, [
    this._window = const ProfileModeWindow.none(),
  ]) {
    _armExpiry();
  }

  /// The stored mode, even if its window has lapsed — what the settings
  /// segments show while the reset is still being written.
  SilentMode get mode => _mode;

  /// The mute actually in force. The overview indicator reads THIS, so a lapsed
  /// mute stops showing without anyone having to clear it.
  SilentMode get activeMode => _window.lapsed ? SilentMode.off : _mode;

  ProfileModeWindow get window => _window;

  /// Mute, or unmute. Muting always starts the picked window fresh, so it never
  /// inherits an almost-elapsed run.
  Future<void> setMode(SilentMode mode) async {
    if (mode == SilentMode.off) {
      await _apply(SilentMode.off, _window.stopped);
      return;
    }
    await _apply(mode, _window.started());
  }

  /// Change how long the mute lasts, restarting it from now.
  Future<void> setWindow(int minutes) async {
    await _apply(_mode, _window.withWindow(minutes));
  }

  /// Persists the mode + window AND mirrors them to the account.
  ///
  /// The push is here rather than at the call sites because the overview's
  /// unmute banner is not the profile page and so never triggered the
  /// leave-the-page push every other setting relies on: unmuting stuck locally,
  /// the account kept `silent_mode: true`, and the next start's account pull
  /// silently re-muted the alarms. Safety-relevant, so it syncs on the spot.
  Future<void> _apply(SilentMode mode, ProfileModeWindow window) async {
    if (mode == _mode && window == _window) {
      return;
    }
    _mode = mode;
    _window = window;
    _armExpiry();
    notifyListeners();
    await _storage.write(key: _kSilent, value: '${mode == SilentMode.all}');
    await _storage.write(key: _kTones, value: '${mode == SilentMode.tones}');
    await windowStore.save(window);
    await ProfileSettings().push(null);
  }

  void _armExpiry() {
    _expiry?.cancel();
    _expiry = _window.expiryTimer(
      () => _apply(SilentMode.off, _window.stopped),
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  /// The mute in force right now. Used both for the initial UI state and by the
  /// service isolate's alarm checks (which can't observe the notifier), so a
  /// lapsed window reads as [SilentMode.off] for every caller.
  static Future<SilentMode> load() async => (await loadRaw()).mode;

  /// The persisted mode + window, with a lapsed run normalised to unmuted.
  ///
  /// The hard mute wins over the tone mute, so a stale flag pair can never read
  /// as less muted than the user asked for. An absent or unparseable window is
  /// [ProfileModeWindow.permanent] — a mute must never expire by accident.
  static Future<({SilentMode mode, ProfileModeWindow window})> loadRaw() async {
    final window = await windowStore.load();
    if (window.lapsed) {
      return (mode: SilentMode.off, window: window.stopped);
    }
    return (mode: await _loadMode(), window: window);
  }

  static Future<SilentMode> _loadMode() async {
    if (await _storage.read(key: _kSilent) == 'true') {
      return SilentMode.all;
    }
    if (await _storage.read(key: _kTones) == 'true') {
      return SilentMode.tones;
    }
    return SilentMode.off;
  }
}
