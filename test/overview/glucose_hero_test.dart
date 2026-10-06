import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/glucose_hero.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:provider/provider.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

ProfileGlucoseState glucoseState(GlucoseUnit unit) => ProfileGlucoseState(
  unit: unit,
  targetLow: 70,
  targetHigh: 180,
  urgentLow: 55,
  low: 70,
  high: 180,
  urgentHigh: 250,
);

Widget wrap(Widget child, {GlucoseUnit unit = GlucoseUnit.mgdl}) {
  return ChangeNotifierProvider<ProfileGlucoseState>(
    key: ValueKey(unit),
    create: (_) => glucoseState(unit),
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: Locales.delegates,
      supportedLocales: Locales.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// One widget test on purpose: [Locales] keeps global singletons, and a second
/// [testWidgets] in the same file inherits them in a state where the app never
/// builds its home (see day_section_header_test.dart).
void main() {
  testWidgets('renders value, unit, trend, mmol and the loader', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);

    await tester.pumpWidget(wrap(const GlucoseHero(mgdl: 120, trendPerMin: 1)));
    await settleLocalized(tester);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('mg/dL'), findsOneWidget);
    expect(
      find.text('Steigt +1,0 pro Min.', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(
      wrap(const GlucoseHero(mgdl: 64, trendPerMin: -1.1)),
    );
    await tester.pumpAndSettle();
    final low = tester.widget<Text>(find.text('64')).style!.color;
    expect(low, InsulinkColors.light.low);

    await tester.pumpWidget(
      wrap(
        const GlucoseHero(mgdl: 180, trendPerMin: null),
        unit: GlucoseUnit.mmol,
      ),
    );
    await settleLocalized(tester);
    expect(find.text('10,0'), findsOneWidget);
    expect(find.text('mmol/L'), findsOneWidget);

    await tester.pumpWidget(
      wrap(const GlucoseHero(mgdl: null, trendPerMin: null)),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  test('trend buckets map to arrow rotations', () {
    expect(GlucoseTrendDirection.of(0.3).degrees, 0);
    expect(GlucoseTrendDirection.of(1.0).degrees, -45);
    expect(GlucoseTrendDirection.of(2.5).degrees, -90);
    expect(GlucoseTrendDirection.of(-1.1).degrees, 45);
    expect(GlucoseTrendDirection.of(-2.0).degrees, 90);
  });
}
