import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/auth/biometric_lock.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The app lock: it must not show the data before it has asked, it must ask
/// again every time the app comes back, and it must stay out of the way
/// entirely for the users who never switched it on.
class _FakeSecurity extends ProfileSecurityState {
  _FakeSecurity({required this.gated, this.opens = true});

  bool gated;

  bool opens;

  int asked = 0;

  @override
  Future<bool> isGuarded(GuardedAction action) async => gated;

  @override
  Future<bool> locksApp() async => gated;

  @override
  Future<bool> confirm(
    GuardedAction action,
    String reason, {
    bool allowDeviceCredential = false,
  }) async {
    asked++;
    return gated ? opens : true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> lifecycle(AppLifecycleState state) {
    return TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage('$state'),
          (_) {},
        );
  }

  Future<void> pumpLock(WidgetTester tester, _FakeSecurity security) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: BiometricLock(
          security: security,
          child: const Scaffold(body: Text('the app')),
        ),
      ),
    );
    await settleLocalized(tester);
  }

  setUp(() => lifecycle(AppLifecycleState.resumed));

  testWidgets('an app that does not lock shows no lock screen', (tester) async {
    final security = _FakeSecurity(gated: false);
    await pumpLock(tester, security);
    expect(find.text('the app'), findsOneWidget);
    expect(security.asked, 0);
  });

  testWidgets('a locked app opens once the check passes', (tester) async {
    final security = _FakeSecurity(gated: true);
    await pumpLock(tester, security);
    expect(find.text('the app'), findsOneWidget);
    expect(security.asked, 1);
  });

  testWidgets('a declined check leaves the app behind the lock', (
    tester,
  ) async {
    final security = _FakeSecurity(gated: true, opens: false);
    await pumpLock(tester, security);
    expect(find.text('the app'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    security.opens = true;
    await tester.tap(find.byType(FilledButton));
    await settleLocalized(tester);
    expect(find.text('the app'), findsOneWidget);
    expect(security.asked, 2);
  });

  testWidgets('leaving the app locks it again', (tester) async {
    final security = _FakeSecurity(gated: true);
    await pumpLock(tester, security);
    expect(find.text('the app'), findsOneWidget);
    security.opens = false;
    await lifecycle(AppLifecycleState.paused);
    await lifecycle(AppLifecycleState.resumed);
    await settleLocalized(tester);
    expect(
      find.text('the app'),
      findsNothing,
      reason: 'a return from the background is an entry like any other',
    );
    expect(security.asked, 2);
  });
}
