import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_add_actions.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

Widget _localized(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: Locales.delegates,
    supportedLocales: Locales.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// The scan button behaves differently depending on why it was pressed, so the
/// two callers must be able to say which they are.
///
/// One widget test on purpose: [Locales] keeps global singletons (see
/// day_section_header_test.dart), and the buttons read their labels from it.
void main() {
  testWidgets('the nutrition page edits, the bolus picker takes the scan over', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);

    await tester.pumpWidget(_localized(const FoodAddActions()));
    await settleLocalized(tester);
    final actions = tester.widget<FoodAddActions>(find.byType(FoodAddActions));
    expect(actions.onScanRequested, isNull,
        reason: 'no callback means a saved product opens for editing');

    // In the picker a scan is how a product is CHOSEN. The picker takes the
    // scan over so it can close ITSELF first: scanning from inside the sheet
    // reveals it again the moment the scanner pops and then closes it, which
    // reads as a stray popup opening and shutting.
    var asked = 0;
    await tester.pumpWidget(
      _localized(FoodAddActions(onScanRequested: () => asked++)),
    );
    await settleLocalized(tester);
    await tester.tap(find.byIcon(PhosphorIconsBold.qrCode));
    expect(asked, 1, reason: 'the picker scans, not the button');
    expect(find.byTooltip('Barcode scannen'), findsOneWidget);
  });
}
