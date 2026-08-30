import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// Pumps the real localization stack — [LocaleBuilder] → [LocaleNotifier] →
/// MaterialApp wired with [Locales.delegates] — and switches language at
/// runtime. Exercises the inherited-widget plumbing, the delegate (load/
/// isSupported/shouldReload), the BuildContext-based [Locales] statics and
/// [LocaleText], end to end, the way the app actually uses them.
///
/// One test on purpose: [Locales.selectedLocale] / [LocalePreference.instance]
/// are global singletons, so a second test running after a locale switch would
/// inherit the polluted state. Keeping it single keeps the state clean.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app() => LocaleBuilder(
    builder: (locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: Locales.delegates,
      supportedLocales: Locales.supportedLocales,
      home: Builder(
        builder: (context) => Column(
          children: [
            // profile.glucose differs across locales (Glukose / Glucose).
            const LocaleText('profile.glucose'),
            // Non-localized + upper-cased path of LocaleText.
            const LocaleText('raw.literal', localize: false, upperCase: true),
            TextButton(
              onPressed: () => Locales.change(context, 'en'),
              child: const Text('switch'),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('localizes, exposes the locale via context, and switches', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    await tester.pumpWidget(app());
    await settleLocalized(tester);
    expect(find.text('Glukose'), findsOneWidget);
    expect(find.text('RAW.LITERAL'), findsOneWidget);

    // The context-based statics resolve against the mounted tree.
    final context = tester.element(find.byType(TextButton));
    expect(Locales.currentLocale(context), const Locale('de'));
    expect(Locales.isDirectionRTL(context), isFalse); // German isn't RTL

    await tester.tap(find.text('switch'));
    await tester.pump();
    await settleLocalized(tester);
    expect(find.text('Glucose'), findsOneWidget);
  });
}
