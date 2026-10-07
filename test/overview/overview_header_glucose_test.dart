import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/overview/overview_data_view.dart';
import 'package:insulink/src/overview/overview_header_glucose.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:provider/provider.dart';

class _ReadingController extends CgmController {
  @override
  int? get currentMgdl => 137;

  @override
  double? get displayTrendPerMin => 0.3;

  @override
  bool get currentIsStale => false;
}

void main() {
  testWidgets('fades in with the scroll position and back out', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CgmController>.value(
            value: _ReadingController(),
          ),
          ChangeNotifierProvider<ProfileGlucoseState>(
            create: (_) => ProfileGlucoseState(
              unit: GlucoseUnit.mgdl,
              targetLow: 70,
              targetHigh: 180,
              urgentLow: 55,
              low: 70,
              high: 180,
              urgentHigh: 250,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: OverviewHeaderGlucose())),
        ),
      ),
    );
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: find.text('137'), matching: find.byType(Opacity)),
        )
        .opacity;

    overviewScrollOffset.value = 0;
    await tester.pump();
    expect(find.text('137'), findsNothing);

    overviewScrollOffset.value = 75;
    await tester.pump();
    expect(opacity(), inExclusiveRange(0.0, 1.0));

    overviewScrollOffset.value = 300;
    await tester.pump();
    expect(opacity(), 1);

    overviewScrollOffset.value = 0;
    await tester.pump();
    expect(find.text('137'), findsNothing);
  });
}
