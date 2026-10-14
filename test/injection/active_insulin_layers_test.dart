import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/active_insulin_chart.dart';
import 'package:insulink/src/injection/active_insulin_legend.dart';
import 'package:insulink/src/injection/insulin_on_board_curve.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/app_theme.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// One widget test on purpose: [Locales] keeps global singletons, and a second
/// [testWidgets] in the same file inherits them in a state where the app never
/// builds its home (see day_section_header_test.dart).
void main() {
  testWidgets(
    'the stacked graph draws, names its layers and reads out a touch',
    (tester) async {
      installSecureStorageMock();
      await Locales.init(['de', 'en']);
      final now = DateTime(2026, 10, 14, 18, 30);
      final points = [
        for (var index = 0; index < 24; index++)
          InsulinOnBoardSample(
            at: now.add(Duration(minutes: index * 5 - 60)),
            boluses: 2,
            microBoluses: index > 6 ? 0.5 : 0,
            rate: 0.3,
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: Locales.delegates,
          supportedLocales: Locales.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: ActiveInsulinChart(points: points, now: now),
                ),
                ActiveInsulinLegend(points: points),
              ],
            ),
          ),
        ),
      );
      await settleLocalized(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Deine Boli'), findsOneWidget);
      expect(find.text('Mini-Boli'), findsOneWidget);
      expect(find.text('Temporäre Rate'), findsOneWidget);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final bars = chart.data.lineBarsData;
      final readout = chart.data.lineTouchData.touchTooltipData
          .getTooltipItems([
            for (var index = 0; index < bars.length; index++)
              LineBarSpot(bars[index], index, bars[index].spots[12]),
          ]);
      final text = [
        readout.last!.text,
        for (final child in readout.last!.children!) child.toPlainText(),
      ].join();
      expect(readout.take(2), everyElement(isNull));
      expect(text, contains('18:30'));
      expect(text, contains('Gesamt  2,80 E'));
      expect(text, contains('Mini-Boli  0,50 E'));
      expect(text, contains('Temporäre Rate  0,30 E'));

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(LineChart)),
      );
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
