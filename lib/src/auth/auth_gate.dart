import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/auth/auth_page.dart';
import 'package:insulink/src/auth/biometric_lock.dart';
import 'package:insulink/src/auth/legal_page.dart';
import 'package:insulink/src/auth/permissions/permission_onboarding.dart';
import 'package:insulink/src/base/launch_hold.dart';
import 'package:insulink/src/base/launch_reveal.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/main.dart';

/// App entry point: shows the permission onboarding on first run, then the
/// sign-in / sign-up page until authenticated, then the main app. Each step
/// persists so a returning (or logged-out) user skips the parts already done.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _storage = FlutterSecureStorage();
  bool _loading = true;
  bool _legalAccepted = false;
  bool _onboardingDone = false;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads which page comes first, then lets the first frame through
  /// ([LaunchHold]) so the splash hands over straight to that page, never to
  /// the blank frame before it. Released even if reading fails, so a broken
  /// storage cannot keep the splash up forever.
  Future<void> _load() async {
    try {
      final legal = await _storage.read(key: "legal_accepted") == "true";
      final done = await _storage.read(key: "onboarding_done") == "true";
      final token = await _storage.read(key: "authentication_token") ?? "";
      if (!mounted) {
        return;
      }
      setState(() {
        _legalAccepted = legal;
        _onboardingDone = done;
        _authenticated = token.isNotEmpty;
        _loading = false;
      });
    } finally {
      const LaunchHold().release();
    }
  }

  Future<void> _acceptLegal() async {
    await _storage.write(key: "legal_accepted", value: "true");
    if (mounted) {
      setState(() => _legalAccepted = true);
    }
  }

  Future<void> _finishOnboarding() async {
    await _storage.write(key: "onboarding_done", value: "true");
    if (mounted) {
      setState(() => _onboardingDone = true);
    }
  }

  /// Sign-in succeeded: advance this gate to the app, then reload so the data
  /// providers pick up the preferences the sign-in pull just wrote.
  ///
  /// We set [_authenticated] directly rather than relying on the reload to
  /// remount us: the reload only re-keys the data-provider subtree, while the
  /// [Navigator] above this gate carries a GlobalKey and is preserved across it
  /// — so a fresh [_AuthGateState] never runs and the token [initState] read
  /// (empty) would otherwise strand the user on the login page.
  void _onAuthenticated() {
    setState(() => _authenticated = true);
    InsulinkApp.reload(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return LaunchReveal(child: _firstPage());
  }

  Widget _firstPage() {
    if (!_legalAccepted) {
      return LegalPage(onAccepted: _acceptLegal);
    }
    if (!_onboardingDone) {
      return PermissionOnboarding(onDone: _finishOnboarding);
    }
    if (!_authenticated) {
      return AuthPage(onAuthenticated: _onAuthenticated);
    }
    return const BiometricLock(child: AppPage());
  }
}
