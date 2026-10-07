import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/theme/app_theme.dart';

Widget themed(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('a panel list draws one line between each pair of rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const InkPanel.list(rows: [Text('one'), Text('two'), Text('three')]),
      ),
    );
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('tapping an option reports its value, not its label', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      themed(
        SegmentedToggle<int>(
          selected: 24,
          onChanged: (value) => picked = value,
          options: const [
            (value: 24, label: '24 h'),
            (value: 6, label: '6 h'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('6 h'));
    expect(picked, 6);
    expect(tester.getSize(find.byType(SegmentedToggle<int>)).height, 50);
  });
}
