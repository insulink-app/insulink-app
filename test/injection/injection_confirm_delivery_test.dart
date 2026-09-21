import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/bolus_delivery.dart';
import 'package:insulink/src/injection/injection_confirm_page.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/app_theme.dart';

import '../pump/fake_secure_storage.dart';
import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The incident this file exists for: with the bolus fingerprint switched off in
/// the settings, the confirm button logged the meal and never sent anything to
/// the pod. The gate decides whether the user is ASKED, never whether the pod is,
/// so every confirmed dose has to leave this page the same way.
class _PumpDelivery extends BolusDelivery {
  _PumpDelivery(PodStore store)
    : super(
        controller: PodController(store: store),
        maxBolusUnits: 10,
        maxUnitsPerHour: 10,
      );

  @override
  bool get usesPump => true;
}

void main() {
  late BolusDeliveryResult? outcome;

  BolusDelivery pumpDelivery() {
    final backing = <String, String>{};
    return _PumpDelivery(PodStore(FakeSecureStorage(backing), backing));
  }

  /// Opens the page with the bolus gate switched off, taps its one button and
  /// hands back what the page popped.
  Future<void> confirm(
    WidgetTester tester, {
    required double bolus,
    BolusDelivery? delivery,
  }) async {
    installSecureStorageMock()[GuardedAction.bolus.storageKey] = 'false';
    await Locales.init(['de', 'en']);
    outcome = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(context).push<BolusDeliveryResult>(
                MaterialPageRoute<BolusDeliveryResult>(
                  builder: (_) => InjectionConfirmPage(
                    carbs: 40,
                    glucoseMgdl: 180,
                    bolus: bolus,
                    delivery: delivery,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await settleLocalized(tester);
    await tester.tap(find.text('open'));
    await settleLocalized(tester);
    await tester.tap(find.byType(FilledButton));
    await settleLocalized(tester);
  }

  testWidgets('an unasked bolus still goes to the pod', (tester) async {
    await confirm(tester, bolus: 2.5, delivery: pumpDelivery());
    expect(outcome!.status, BolusDeliveryStatus.handedOver);
  });

  testWidgets('without a pod it is still only logged', (tester) async {
    await confirm(tester, bolus: 2.5);
    expect(outcome!.status, BolusDeliveryStatus.loggedOnly);
    expect(outcome!.recordedUnits, 2.5);
  });

  testWidgets('a carbs-only entry asks the pod for nothing', (tester) async {
    await confirm(tester, bolus: 0, delivery: pumpDelivery());
    expect(outcome!.status, BolusDeliveryStatus.loggedOnly);
    expect(outcome!.recordedUnits, 0);
  });
}
