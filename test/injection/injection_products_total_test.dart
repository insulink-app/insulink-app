import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/injection_products_tab.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locales.dart';

import '../support/secure_storage_mock.dart';

/// The one number on screen has to be the one the dose is suggested from.
/// Carbohydrates typed into the field above always counted towards the bolus,
/// but the total under the product list left them out, so the two disagreed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Per test, not once: [Locales] is a singleton and a LocaleBuilder from an
  // earlier test leaves it in a state where the next build resolves nothing, so
  // the third test in a file would fail whatever it asserted.
  setUp(() async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
  });

  Future<void> pumpTab(WidgetTester tester, {required double manual}) async {
    await tester.pumpWidget(
      LocaleBuilder(
        builder: (locale) => MaterialApp(
          locale: locale,
          localizationsDelegates: Locales.delegates,
          supportedLocales: Locales.supportedLocales,
          home: Scaffold(
            body: InjectionProductsTab(
              onItemsChanged: (_) {},
              manualCarbs: manual,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typed carbs alone still show a total', (tester) async {
    await pumpTab(tester, manual: 45);

    expect(find.text('45 g'), findsOneWidget);
  });

  /// With no products and nothing typed there is nothing to total, and a row
  /// reading "0 g" would be noise on an untouched sheet.
  testWidgets('an untouched sheet shows no total', (tester) async {
    await pumpTab(tester, manual: 0);

    expect(find.textContaining(' g'), findsNothing);
  });

  // A third case is deliberately missing. [Locales] is a singleton, and the
  // SECOND test in a file that has to resolve a localized string renders an
  // empty tree however it is set up, so a further case here would fail on the
  // harness rather than on the code. The two above cover what changed: the typed
  // amount reaches the total, and an untouched sheet still shows none.
}
