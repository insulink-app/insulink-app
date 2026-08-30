import 'package:flutter_test/flutter_test.dart';

/// Lets a localization delegate's asset load finish on REAL time, then settles.
///
/// [WidgetTester.pumpAndSettle] waits for frames, not for actual asynchronous
/// work, and reading the locale JSON is actual asynchronous work: Flutter
/// decodes an asset over 50 KB in a background isolate, and `de.json` crossed
/// that line as the app grew. Every widget test that renders a [LocaleText] then
/// settled with no strings loaded and rendered `$key` placeholders instead.
///
/// The frame must already have been pumped when this is called, so the load is
/// under way before the real-time gap is given to it.
Future<void> settleLocalized(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}
