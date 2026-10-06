import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/dock_tabs.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/app_theme.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

class _FakeBody extends AppPageBody {
  _FakeBody(String name)
    : super(
        name: name,
        unselectedIcon: Icons.circle,
        selectedIcon: Icons.circle,
      );

  @override
  Widget content(BuildContext context) => const SizedBox.shrink();
}

/// One widget test on purpose: [Locales] keeps global singletons (see
/// day_section_header_test.dart).
void main() {
  testWidgets('dragging lands on the tab under the finger, tapping selects', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    final selected = <int>[];
    final bodies = [
      for (final name in ['overview', 'sport', 'nutrition', 'analysis'])
        _FakeBody('$name.label'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('de'),
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: Center(
          child: SizedBox(
            width: 272,
            height: 62,
            child: DockTabs(
              pageBodies: bodies,
              selectedIndex: 0,
              badges: const {},
              onSelect: selected.add,
            ),
          ),
        ),
      ),
    );
    await settleLocalized(tester);

    final dock = tester.getRect(find.byType(DockTabs));
    final gesture = await tester.startGesture(
      dock.centerLeft + const Offset(40, 0),
    );
    for (var step = 0; step < 16; step++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);

    await tester.tapAt(dock.centerRight - const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(selected, [2, 3]);
  });
}
