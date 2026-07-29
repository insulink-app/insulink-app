import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
/// alarm and sensor notification. It's a user-facing mute, persisted in secure
/// storage.
///
/// Provided above the page tree (see `main.dart`) so the profile selection and
/// the overview indicator observe the same value. The alarm code runs in the
/// foreground-service isolate, which can't watch this notifier, so it reads the
/// mode fresh from storage via [load] on every reading (no restart needed for a
/// change to take effect).
///
/// The tri-state is persisted as the two ORIGINAL boolean keys rather than one
/// enum string, because the panel coerces `silent_mode` to a bool and writes it
/// straight back into the shared settings blob — an enum string would come back
/// from a panel save as `false` and silently unmute.
class ProfileSilentState extends ChangeNotifier {
  static const _kSilent = 'silent_mode';
  static const _kTones = 'silent_tones';
  static const _storage = FlutterSecureStorage();

  SilentMode _mode;

  ProfileSilentState(this._mode);

  SilentMode get mode => _mode;

  /// Persists the mode AND mirrors it to the account.
  ///
  /// The push is here rather than at the call sites because the overview's
  /// unmute banner is not the profile page and so never triggered the
  /// leave-the-page push every other setting relies on: unmuting stuck locally,
  /// the account kept `silent_mode: true`, and the next start's account pull
  /// silently re-muted the alarms. Safety-relevant, so it syncs on the spot.
  Future<void> setMode(SilentMode mode) async {
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    await _storage.write(key: _kSilent, value: '${mode == SilentMode.all}');
    await _storage.write(key: _kTones, value: '${mode == SilentMode.tones}');
    await ProfileSettings().push(null);
  }

  /// Read the persisted mode. Used both for the initial UI state and by the
  /// service isolate's alarm checks (which can't observe the notifier). The hard
  /// mute wins over the tone mute, so a stale flag pair can never read as less
  /// muted than the user asked for.
  static Future<SilentMode> load() async {
    if (await _storage.read(key: _kSilent) == 'true') {
      return SilentMode.all;
    }
    if (await _storage.read(key: _kTones) == 'true') {
      return SilentMode.tones;
    }
    return SilentMode.off;
  }
}
