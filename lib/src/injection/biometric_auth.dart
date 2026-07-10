import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper over [LocalAuthentication] for confirming a bolus with the
/// device biometric (fingerprint / face). Owns the plugin instance so callers
/// just ask [confirm].
class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Prompts the biometric sheet and returns whether it succeeded. On a device
  /// with no biometric enrolled (or a plugin error) it returns false so the
  /// caller can surface a failure rather than silently confirming.
  Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
