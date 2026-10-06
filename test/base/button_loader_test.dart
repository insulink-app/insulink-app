import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/button_loader.dart';
import 'package:insulink/src/theme/app_theme.dart';

void main() {
  testWidgets('a busy, disabled button shows a light spinner on dark', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: FilledButton(onPressed: null, child: ButtonLoader()),
        ),
      ),
    );
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    final color = spinner.color!;
    expect(color, isNot(AppTheme.dark.colorScheme.onPrimary));
    expect(color.withValues(alpha: 1).computeLuminance(), greaterThan(0.5));
  });

  testWidgets('an enabled button keeps the spinner in its own foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: FilledButton(onPressed: () {}, child: const ButtonLoader()),
        ),
      ),
    );
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, AppTheme.dark.colorScheme.onPrimary);
  });
}
