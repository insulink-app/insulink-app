import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/injection/biometric_auth.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';

/// An action the app can hold behind the device biometric.
///
/// Every one of these used to be gated unconditionally. They still are by
/// default, because each one either puts insulin in a body, takes an alarm away
/// or throws a pairing out, and the fingerprint is what keeps a pocket tap or a
/// borrowed phone from doing it. Which of them stay gated is the owner's call,
/// so each carries its own switch and its own default.
enum GuardedAction {
  /// Opening the app at all. Off by default: it guards the data on screen
  /// rather than an action, and nobody should find their app locked by an
  /// update they did not ask for.
  appEntry(defaultOn: false),

  /// Confirming a bolus.
  bolus(),

  /// Driving the cannula into the body during pod activation.
  cannula(),

  /// Handing basal control to the automation.
  loop(),

  /// Deactivating a pod, or dropping one the app cannot reach.
  pump(),

  /// Forgetting a sensor, which deletes its key and its history.
  sensor(),

  /// Muting every glucose alarm.
  silent(),

  /// Turning the battery saver on.
  battery();

  const GuardedAction({this.defaultOn = true});

  /// Whether the gate is on for a user who has never touched the setting.
  final bool defaultOn;

  /// Where the switch is stored, and the key it rides under in the account
  /// settings: snake_case, like every other key in that blob.
  String get storageKey => 'guard_$localeKey';

  /// The camelCase key [appEntry] was stored under before the gates synced.
  /// Read as a fallback, so an update does not quietly switch a lock off.
  String get legacyStorageKey => 'guard_$name';

  String get labelKey => 'profile.security.action.$localeKey';
}

/// Which actions ask for the fingerprint, and the asking itself.
///
/// Synced with the account settings like every other switch, so a new phone
/// starts with the same gates. Read fresh at every gate, so a switch takes
/// effect on the next action with no restart.
class ProfileSecurityState {
  ProfileSecurityState({BiometricAuth? auth}) : _auth = auth ?? BiometricAuth();

  static const _storage = FlutterSecureStorage();

  final BiometricAuth _auth;

  Future<bool> isGuarded(GuardedAction action) async {
    final stored =
        await _storage.read(key: action.storageKey) ??
        await _storage.read(key: action.legacyStorageKey);
    if (stored == null) {
      return action.defaultOn;
    }
    return stored == 'true';
  }

  Future<void> setGuarded(GuardedAction action, bool guarded) {
    return _storage.write(key: action.storageKey, value: '$guarded');
  }

  /// Whether the app holds itself behind the lock: the switch is on AND this
  /// phone can ask at all. The switch now arrives from the account, and a phone
  /// with neither a biometric nor a screen lock would otherwise keep its owner
  /// out of the app for good.
  Future<bool> locksApp() async =>
      await isGuarded(GuardedAction.appEntry) && await _auth.canAuthenticate();

  /// Whether [action] may go ahead: either its gate is off, or the user has just
  /// passed it. [reason] is what the platform sheet says it is asking for.
  ///
  /// [allowDeviceCredential] lets the device PIN stand in where no biometric is
  /// enrolled, so a user without a fingerprint is not locked out of a setting.
  /// The two actions that reach the body (bolus, cannula) keep it off.
  Future<bool> confirm(
    GuardedAction action,
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    if (!await isGuarded(action)) {
      return true;
    }
    return _auth.confirm(reason, allowDeviceCredential: allowDeviceCredential);
  }
}
