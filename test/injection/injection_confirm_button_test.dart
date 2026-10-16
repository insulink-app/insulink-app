import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/injection_confirm_button.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/theme/app_theme.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The incident this file exists for: with the bolus fingerprint switched off in
/// the settings, the confirm button logged the meal and never sent anything to
/// the pod. The gate decides whether the user is ASKED, never whether the pod is,
/// so every confirmed dose has to leave the button the same way.
void main() {
  late BolusDeliveryResult? outcome;

  /// Shows the button with the bolus gate switched off, taps it and keeps what
  /// it reported.
  Future<void> confirm(
    WidgetTester tester, {
    required double bolus,
    bool usesPump = false,
  }) async {
    installSecureStorageMock()[GuardedAction.bolus.storageKey] = 'false';
    await Locales.init(['de', 'en']);
    outcome = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: Scaffold(
          body: InjectionConfirmButton(
            bolus: bolus,
            usesPump: usesPump,
            onConfirmed: (result) => outcome = result,
          ),
        ),
      ),
    );
    await settleLocalized(tester);
    await tester.tap(find.byType(FilledButton));
    await settleLocalized(tester);
  }

  testWidgets('an unasked bolus still goes to the pod', (tester) async {
    await confirm(tester, bolus: 2.5, usesPump: true);
    expect(outcome!.status, BolusDeliveryStatus.handedOver);
  });

  testWidgets('without a pod it is still only logged', (tester) async {
    await confirm(tester, bolus: 2.5);
    expect(outcome!.status, BolusDeliveryStatus.loggedOnly);
    expect(outcome!.recordedUnits, 2.5);
  });

  testWidgets('a carbs-only entry asks the pod for nothing', (tester) async {
    await confirm(tester, bolus: 0, usesPump: true);
    expect(outcome!.status, BolusDeliveryStatus.loggedOnly);
    expect(outcome!.recordedUnits, 0);
  });
}
