import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/dock_tab_slot.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/demo/demo_app.dart';
import 'package:insulink/src/overview/chart/overview_chart_page.dart';
import 'package:insulink/src/overview/chart/overview_chart_preview.dart';
import 'package:integration_test/integration_test.dart';

const String language = String.fromEnvironment('LANGUAGE', defaultValue: 'en');
const String theme = String.fromEnvironment('THEME', defaultValue: 'dark');
const List<String> tabs = ['overview', 'sport', 'nutrition', 'analysis'];

/// Photographs the demo for the screenshots published next to the web demo
/// (`docs/SCREENSHOTS.md`). One run is one language and theme, passed as
/// `--dart-define=LANGUAGE=` and `THEME=`; the driver writes each shot to
/// `build/screenshots/<language>-<theme>/<name>.png`.
///
/// The binding is created inside the demo's request zone, like the website's,
/// and the app starts in the test body: a widget tree mounted before the test
/// starts is replaced by the binding's "Test starting" placeholder.
void main() {
  final demo = DemoApp(language: language, theme: theme);
  demo.inZone(() {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    testWidgets('screenshots $language $theme', (tester) async {
      Future<void> shoot(String name) =>
          binding.takeScreenshot('$language-$theme/$name');
      await demo.inZone(demo.start);
      await waitForTabs(tester);
      for (var index = 0; index < tabs.length; index++) {
        appTab.value = index;
        await settle(tester);
        await shoot(tabs[index]);
      }
      appTab.value = 0;
      await settle(tester);
      await tester.tap(find.byType(OverviewChartPreview));
      await settle(tester);
      expect(find.byType(OverviewChartPage), findsOneWidget);
      await shoot('glucose');
    });
  });
}

/// Pumps frame by frame for two seconds, so a tab or page transition plays
/// out before the shot; the test binding only draws the frames it is asked for.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until the demo has pulled its account and shows the tab bar.
Future<void> waitForTabs(WidgetTester tester) async {
  for (var second = 0; second < 60; second++) {
    await tester.pump(const Duration(seconds: 1));
    if (find.byType(DockTabSlot).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('the demo never showed its tab bar');
}
