import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/activity_mode/activity_mode_overview_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_selector.dart';
import 'package:insulink/src/activity_mode/activity_mode_switch_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// One widget test on purpose: [Locales] keeps global singletons, and a second
/// [testWidgets] in the same file inherits them in a state where the app never
/// builds its home (see day_section_header_test.dart).
void main() {
  testWidgets('a switch flipped in the profile reaches the overview at once', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    final switches = ActivityModeSwitchState(true, false);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: switches,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: Locales.delegates,
          supportedLocales: Locales.supportedLocales,
          home: const Scaffold(body: ActivityModeOverviewSelector()),
        ),
      ),
    );
    await settleLocalized(tester);
    expect(find.byType(ActivityModeSelector), findsNothing);

    await switches.setOnOverview(true);
    await tester.pump();
    expect(find.byType(ActivityModeSelector), findsOneWidget);

    await switches.setEnabled(false);
    await tester.pump();
    expect(find.byType(ActivityModeSelector), findsNothing);
  });
}
