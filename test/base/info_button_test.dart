import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/info_button.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/app_theme.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The explanation is off the page until the ⓘ is tapped, then in a sheet.
/// One widget test on purpose: [Locales] keeps global singletons (see
/// day_section_header_test.dart).
void main() {
  testWidgets('the explanation opens in a sheet', (tester) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('de'),
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: const Scaffold(
          body: InfoButton(
            titleKey: 'profile.battery',
            bodyKey: 'profile.battery.description',
          ),
        ),
      ),
    );
    await settleLocalized(tester);
    final explanation = find.textContaining('Akku zu sparen');
    expect(explanation, findsNothing);

    await tester.tap(find.byType(InfoButton));
    await tester.pumpAndSettle();

    expect(explanation, findsOneWidget);
  });
}
