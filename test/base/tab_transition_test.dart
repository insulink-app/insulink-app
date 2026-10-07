import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/tab_transition.dart';

void main() {
  testWidgets('the old and the new tab are never visible at the same time', (
    tester,
  ) async {
    Widget page(int index) => Directionality(
      textDirection: TextDirection.ltr,
      child: TabTransition(index: index, child: Text('tab $index')),
    );
    double opacityOf(String text) => tester
        .widget<Opacity>(
          find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
        )
        .opacity;

    await tester.pumpWidget(page(0));
    await tester.pumpWidget(page(1));

    for (final elapsed in [30, 60, 90, 120, 150, 200, 250]) {
      await tester.pump(const Duration(milliseconds: 30));
      final outgoing = opacityOf('tab 0');
      final incoming = opacityOf('tab 1');
      expect(outgoing == 0 || incoming == 0, isTrue, reason: '${elapsed}ms');
    }
    await tester.pumpAndSettle();
    expect(find.text('tab 0'), findsNothing);
    expect(opacityOf('tab 1'), 1);
  });
}
