import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper over [LocalAuthentication] for confirming a bolus with the
/// device biometric (fingerprint / face). Owns the plugin instance so callers
/// just ask [confirm].
class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Prompts wait for each other. The platform shows one sheet at a time and
  /// answers a second call with "already in progress", which arrives as a plain
  /// refusal — so the app-entry lock and a gate that were both woken by the same
  /// unlock would knock each other out. Process-wide, because the sheet is.
  static Future<void> _queue = Future<void>.value();

  /// How long a rejected prompt waits for the app to report that it left the
  /// foreground. The platform cancel beats the activity's own pause, so the
  /// rejection reaches us a moment before the lifecycle change does.
  static const Duration _interruptionGrace = Duration(seconds: 2);

  /// Prompts the biometric sheet and returns whether it succeeded. On a device
  /// with no biometric enrolled (or a plugin error) it returns false so the
  /// caller can surface a failure rather than silently confirming.
  ///
  /// A prompt the system tears down (screen off, app switched away) is reported
  /// by Android as a plain rejection, which used to turn an accepted fingerprint
  /// into "authentication failed" once the user came back. A rejection that the
  /// app leaving the foreground explains is therefore not an answer: the sheet
  /// comes back when the user does, and only their own "no" counts as one.
  ///
  /// [allowDeviceCredential] falls back to the device PIN/pattern when no
  /// biometric is enrolled — used for the silent-mode gate so a user without a
  /// fingerprint is not locked out of muting; the bolus gate keeps it off
  /// (biometric-only).
  Future<bool> confirm(
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    final ahead = _queue;
    final mine = Completer<void>();
    _queue = mine.future;
    await ahead;
    try {
      return await _answer(reason, allowDeviceCredential);
    } finally {
      mine.complete();
    }
  }

  /// The prompt, and the retry an interruption earns it.
  Future<bool> _answer(String reason, bool allowDeviceCredential) async {
    if (await prompt(reason, allowDeviceCredential: allowDeviceCredential)) {
      return true;
    }
    if (!await _leftForeground()) {
      return false;
    }
    await _backInForeground();
    return prompt(reason, allowDeviceCredential: allowDeviceCredential);
  }

  /// Whether this device can authenticate at all: a biometric enrolled or a
  /// screen lock set. False on a plugin error, because a prompt that cannot be
  /// shown is one nobody can pass.
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// One run of the platform sheet, false on any refusal or plugin error.
  @protected
  @visibleForTesting
  Future<bool> prompt(
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: !allowDeviceCredential,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  /// Whether the app dropped out of the foreground around the rejection, within
  /// [_interruptionGrace] of it.
  Future<bool> _leftForeground() {
    if (_isBackground(WidgetsBinding.instance.lifecycleState)) {
      return Future<bool>.value(true);
    }
    final completer = Completer<bool>();
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        if (_isBackground(state) && !completer.isCompleted) {
          completer.complete(true);
        }
      },
    );
    final grace = Timer(_interruptionGrace, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    return completer.future.whenComplete(() {
      grace.cancel();
      listener.dispose();
    });
  }

  /// Resolves once the user is back in the app, so the sheet is shown to
  /// somebody who can answer it.
  Future<void> _backInForeground() {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    final listener = AppLifecycleListener(onResume: completer.complete);
    return completer.future.whenComplete(listener.dispose);
  }

  bool _isBackground(AppLifecycleState? state) {
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
  }
}
