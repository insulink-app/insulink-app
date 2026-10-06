import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:provider/provider.dart';

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
    create: (_) => glucoseState(unit),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders the value, unit and trend', (tester) async {
    await tester.pumpWidget(
      wrap(const OverviewCurrentValue(mgdl: 120, trendPerMin: 1.0)),
    );
    expect(find.text('120'), findsOneWidget);
    expect(find.text('mg/dL'), findsOneWidget);
    expect(find.text('+1.0/min'), findsOneWidget);
  });

  testWidgets('renders in the chosen display unit (mmol/L)', (tester) async {
    await tester.pumpWidget(
      wrap(
        const OverviewCurrentValue(mgdl: 180, trendPerMin: null),
        unit: GlucoseUnit.mmol,
      ),
    );
    expect(find.text('10.0'), findsOneWidget);
    expect(find.text('mmol/L'), findsOneWidget);
  });

  testWidgets('shows a loader instead of a value when no reading is known', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const OverviewCurrentValue(mgdl: null, trendPerMin: null)),
    );
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });
}
