import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/auth/auth_page.dart';
import 'package:insulink/src/auth/legal_page.dart';
import 'package:insulink/src/auth/permissions/permission_onboarding.dart';
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

  Future<void> _load() async {
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

  /// Sign-in succeeded: reload the app from the preferences the sign-in pull
  /// just wrote for this account.
  ///
  /// That reload is what advances this gate — it REMOUNTS the tree below it, so
  /// a fresh [_AuthGateState] runs [_load] again and finds the token [AuthService]
  /// just stored. This state is never told about the sign-in directly, so the
  /// remount is load-bearing: a reload that merely rebuilds leaves the token
  /// [initState] read (empty) in place and strands the user on the login page.
  void _onAuthenticated() {
    InsulinkApp.reload(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (!_legalAccepted) {
      return LegalPage(onAccepted: _acceptLegal);
    }
    if (!_onboardingDone) {
      return PermissionOnboarding(onDone: _finishOnboarding);
    }
    if (!_authenticated) {
      return AuthPage(onAuthenticated: _onAuthenticated);
    }
    return const AppPage();
  }
}
