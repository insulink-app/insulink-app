import 'package:flutter/material.dart';
import 'package:insulink/src/auth/biometric_lock_screen.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';

/// Holds the app behind the device biometric while [GuardedAction.appEntry] is
/// on, at every entry: the first build after sign-in, and every return from the
/// background.
///
/// It arms on the way out rather than on the way in, so the lock is already in
/// place while the app is away, and what the system shows of it in the task
/// switcher is the lock screen and not the last glucose reading.
///
/// The gate is read from storage on both edges instead of being cached, so the
/// switch in the settings holds from the very next time the app is put down.
class BiometricLock extends StatefulWidget {
  const BiometricLock({super.key, required this.child, this.security});

  final Widget child;

  /// Injectable for tests; the app leaves it null and gets the real gate.
  final ProfileSecurityState? security;

  @override
  State<BiometricLock> createState() => _BiometricLockState();
}

class _BiometricLockState extends State<BiometricLock> {
  late final ProfileSecurityState _security =
      widget.security ?? ProfileSecurityState();
  late final AppLifecycleListener _lifecycle;

  /// Null until the first read says whether this app locks at all, so an app
  /// that does not lock never flashes a lock screen on the way in.
  bool? _locked;

  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _arm, onResume: _askAgain);
    _unlock();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _arm() async {
    if (await _security.isGuarded(GuardedAction.appEntry)) {
      _show(true);
    }
  }

  void _askAgain() {
    if (_locked ?? true) {
      _unlock();
    }
  }

  /// Paints the lock before it asks, so the sheet stands in front of the lock
  /// screen rather than in front of the data it is protecting. The gate is read
  /// twice for that (once here, once inside the confirm) which is one storage
  /// read, against a frame of exposed data.
  Future<void> _unlock() async {
    if (_asking) {
      return;
    }
    if (!await _security.isGuarded(GuardedAction.appEntry)) {
      _show(false);
      return;
    }
    _show(true);
    if (!mounted) {
      return;
    }
    _asking = true;
    final opened = await _security.confirm(
      GuardedAction.appEntry,
      Locales.string(context, 'profile.security.lock.reason'),
      allowDeviceCredential: true,
    );
    _asking = false;
    if (opened) {
      _show(false);
    }
  }

  void _show(bool locked) {
    if (mounted && _locked != locked) {
      setState(() => _locked = locked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (_locked!) {
      return BiometricLockScreen(onUnlock: _unlock);
    }
    return widget.child;
  }
}
