import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';

void main() {
  Widget host(
    void Function(double) onSubmit, {
    double initial = 3,
    bool decimal = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SportEditableNumber(
            valueText: decimal ? '3,0' : '3',
            initial: initial,
            min: 1,
            max: 12,
            decimal: decimal,
            onSubmit: onSubmit,
          ),
        ),
      ),
    );
  }

  testWidgets('typing a new integer commits that value', (tester) async {
    double? got;
    await tester.pumpWidget(host((value) => got = value));
    await tester.tap(find.byType(SportEditableNumber));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(got, 8);
  });

  testWidgets('clamps to max', (tester) async {
    double? got;
    await tester.pumpWidget(host((value) => got = value));
    await tester.tap(find.byType(SportEditableNumber));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(got, 12);
  });

  testWidgets('committing without typing leaves the value unchanged', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(host((_) => calls++));
    await tester.tap(find.byType(SportEditableNumber));
    await tester.pumpAndSettle();
    // No text entered — the field started empty, so committing must not fire.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('decimal comma commits', (tester) async {
    double? got;
    await tester.pumpWidget(
      host((value) => got = value, initial: 3, decimal: true),
    );
    await tester.tap(find.byType(SportEditableNumber));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '5,5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(got, 5.5);
  });
}
