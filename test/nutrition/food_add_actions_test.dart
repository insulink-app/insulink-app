import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/nutrition/food/food_add_actions.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The scan button behaves differently depending on why it was pressed, so the
/// two callers must be able to say which they are.
void main() {
  testWidgets('the nutrition page keeps the editing behaviour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FoodAddActions())),
    );

    final actions = tester.widget<FoodAddActions>(find.byType(FoodAddActions));

    expect(actions.onScanRequested, isNull,
        reason: 'no callback means a saved product opens for editing');
  });

  /// In the picker a scan is how a product is CHOSEN, so a barcode already saved
  /// goes straight on to the amount instead of stopping at a form the user has
  /// no reason to fill in again.
  /// The picker takes the scan over so it can close ITSELF first. Scanning from
  /// inside the sheet reveals it again the moment the scanner pops and then
  /// closes it, which reads as a stray popup opening and shutting.
  testWidgets('the bolus picker takes the scan over', (tester) async {
    var asked = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FoodAddActions(onScanRequested: () => asked++)),
      ),
    );

    await tester.tap(find.byIcon(PhosphorIconsBold.qrCode));

    expect(asked, 1, reason: 'the picker scans, not the button');
  });
}
