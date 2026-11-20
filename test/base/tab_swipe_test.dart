import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/tab_swipe.dart';

/// A fast flick opens the neighbouring tab; a slow drift or a flick past the
/// first or last tab changes nothing.
void main() {
  Future<List<int>> flick(
    WidgetTester tester,
    int index,
    Offset by,
    double speed,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TabSwipe(
          index: index,
          count: 3,
          onSelect: selected.add,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.flingFrom(const Offset(400, 300), by, speed);
    return selected;
  }

  testWidgets('a flick to the left opens the tab to the right', (tester) async {
    expect(await flick(tester, 1, const Offset(-200, 0), 1000), [2]);
  });

  testWidgets('a flick to the right opens the tab to the left', (tester) async {
    expect(await flick(tester, 1, const Offset(200, 0), 1000), [0]);
  });

  testWidgets('a slow drift switches nothing', (tester) async {
    expect(await flick(tester, 1, const Offset(-200, 0), 100), isEmpty);
  });

  testWidgets('there is no tab past either end', (tester) async {
    expect(await flick(tester, 0, const Offset(200, 0), 1000), isEmpty);
    expect(await flick(tester, 2, const Offset(-200, 0), 1000), isEmpty);
  });
}
