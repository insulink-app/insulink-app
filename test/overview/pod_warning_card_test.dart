import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/pod_warning_card.dart';
import 'package:insulink/src/theme/app_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The pod card: every standing warning in one card, each one dismissable on
/// its own (by its close button as well as by a swipe), and nothing at all on
/// screen once there is nothing to report.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCard(WidgetTester tester, List<PodWarningLine> lines) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: Scaffold(
          body: PodWarningCard(lines: lines, onOpen: () {}),
        ),
      ),
    );
    await settleLocalized(tester);
  }

  PodWarningLine line(
    String title,
    List<String> dismissed, {
    bool critical = false,
  }) {
    return PodWarningLine(
      dismissKey: title,
      icon: PhosphorIconsBold.warning,
      title: title,
      message: '$title message',
      critical: critical,
      onDismiss: () => dismissed.add(title),
    );
  }

  testWidgets('shows every warning and dismisses each on its own', (
    tester,
  ) async {
    final dismissed = <String>[];
    await pumpCard(tester, [
      line('Pod expires soon', dismissed),
      line('Pod stopped', dismissed, critical: true),
    ]);

    expect(find.text('Pod expires soon'), findsOneWidget);
    expect(find.text('Pod stopped message'), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsBold.x).first);
    await tester.drag(find.text('Pod stopped'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(dismissed, ['Pod expires soon', 'Pod stopped']);
  });

  testWidgets('draws nothing without a warning', (tester) async {
    await pumpCard(tester, const []);
    expect(find.byType(Material), findsWidgets);
    expect(find.byIcon(PhosphorIconsFill.warningCircle), findsNothing);
  });
}
