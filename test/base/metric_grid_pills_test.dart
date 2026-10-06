import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/base/pill_scroll_row.dart';
import 'package:insulink/src/theme/app_theme.dart';

Widget _themed(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('five figures make three rows, two lines between them', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themed(
        const MetricGrid(
          cells: [
            (label: 'a', value: '1', unit: null),
            (label: 'b', value: '2', unit: '%'),
            (label: 'c', value: '3', unit: null),
            (label: 'd', value: '4', unit: null),
            (label: 'e', value: '5', unit: null),
          ],
        ),
      ),
    );
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byType(VerticalDivider), findsNWidgets(3));
  });

  testWidgets('tapping a pill reports its value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _themed(
        PillScrollRow<String>(
          selected: 'ranges',
          onChanged: (value) => picked = value,
          options: const [
            (value: 'ranges', label: 'Bereiche'),
            (value: 'patterns', label: 'Muster'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Muster'));
    expect(picked, 'patterns');
  });
}
