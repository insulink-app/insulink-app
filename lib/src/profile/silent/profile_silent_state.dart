import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/profile_settings.dart';

/// Global "silent mode": while on, no glucose alarms or sensor notifications are
/// shown. It's a user-facing mute, persisted in secure storage.
///
/// Provided above the page tree (see `main.dart`) so the profile toggle and the
/// overview indicator observe the same value. The alarm code runs in the
/// foreground-service isolate, which can't watch this notifier, so it reads the
/// flag fresh from storage via [load] on every reading (no restart needed for a
/// toggle to take effect).
class ProfileSilentState extends ChangeNotifier {
  static const _kSilent = 'silent_mode';
  static const _storage = FlutterSecureStorage();

  bool _silent;

  ProfileSilentState(this._silent);

  bool get silent => _silent;

  /// Persists the flag AND mirrors it to the account.
  ///
  /// The push is here rather than at the call sites because the overview's
  /// unmute banner is not the profile page and so never triggered the
  /// leave-the-page push every other setting relies on: unmuting stuck locally,
  /// the account kept `silent_mode: true`, and the next start's account pull
  /// silently re-muted the alarms. Safety-relevant, so it syncs on the spot.
  Future<void> setSilent(bool v) async {
    if (v == _silent) {
      return;
    }
    _silent = v;
    notifyListeners();
    await _storage.write(key: _kSilent, value: '$v');
    await ProfileSettings().push(null);
  }

  /// Read the persisted flag. Used both for the initial UI state and by the
  /// service isolate's alarm checks (which can't observe the notifier).
  static Future<bool> load() async {
    return (await _storage.read(key: _kSilent)) == 'true';
  }
}
