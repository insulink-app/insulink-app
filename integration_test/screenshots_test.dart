import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/dock_tab_slot.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/demo/demo_app.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_page.dart';
import 'package:integration_test/integration_test.dart';

import 'screenshot_scenes.dart';

const String language = String.fromEnvironment('LANGUAGE', defaultValue: 'en');
const String theme = String.fromEnvironment('THEME', defaultValue: 'dark');
const List<String> tabs = ['overview', 'sport', 'nutrition', 'analysis'];
const List<String> analyses = [
  'analysis-ranges',
  'analysis-patterns',
  'analysis-averages',
  'analysis-history',
  'analysis-events',
  'analysis-forecast',
];

/// Settings topics, by the title key of their row on the profile page.
const Map<String, String> settings = {
  'settings-glucose': 'profile.glucose',
  'settings-bolus': 'profile.bolus',
  'settings-basal': 'profile.basal',
  'settings-notifications': 'profile.notification',
  'settings-alarm-tones': 'profile.alarmtone',
  'settings-automation': 'profile.loop',
  'settings-security': 'profile.security',
};

/// Photographs the demo for the screenshots published next to the web demo
/// (`docs/SCREENSHOTS.md`): the tabs, every analysis, the screens in
/// [screenshotScenes] and the settings topics. One run is one language and
/// theme, passed as `--dart-define=LANGUAGE=` and `THEME=`; the driver writes
/// each shot to `build/screenshots/<language>-<theme>/<name>.png`.
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
      final log = <String>[];
      binding.reportData = {'log': log};
      FlutterError.onError = (details) => log.add(
        'FE ${details.exceptionAsString()} ${'${details.stack}'.split('\n').take(6).join(' / ')}',
      );
      reportTestException = (details, description) => log.add(
        'RTE ${details.exceptionAsString()} ${'${details.stack}'.split('\n').take(8).join(' / ')}',
      );
      await demo.inZone(demo.start);
      await waitForTabs(tester);
      final home = tester.element(find.byType(AppPage));
      final homeRoute = ModalRoute.of(home)!;
      Future<void> backHome() async {
        Navigator.of(home).popUntil((route) => route == homeRoute);
        await settle(tester);
      }

      for (var index = 0; index < tabs.length; index++) {
        appTab.value = index;
        await settle(tester);
        await shoot(tabs[index]);
      }
      final analysis = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      for (var index = 0; index < analyses.length; index++) {
        analysis.index = index;
        await settle(tester);
        await shoot(analyses[index]);
      }
      appTab.value = 0;
      await settle(tester);
      for (final scene in screenshotScenes) {
        scene.open(home);
        await settle(tester);
        await shoot(scene.name);
        log.add('ok ${scene.name}');
        await backHome();
      }
      for (final topic in settings.entries) {
        await openSetting(tester, home, topic.value);
        await shoot(topic.key);
        log.add('ok ${topic.key}');
        await backHome();
      }
    });
  });
}

/// Opens the profile page and taps the row titled [titleKey], once it is
/// scrolled fully into view.
Future<void> openSetting(
  WidgetTester tester,
  BuildContext home,
  String titleKey,
) async {
  Navigator.of(
    home,
  ).push(MaterialPageRoute<void>(builder: (_) => ProfilePage()));
  await settle(tester);
  final row = find.text(Locales.string(home, titleKey)).first;
  await tester.ensureVisible(row);
  await settle(tester);
  await tester.tap(row);
  await settle(tester);
}

/// Pumps frame by frame for a second, so a tab or page transition (about
/// 300 ms) plays out before the shot; the test binding only draws the frames
/// it is asked for.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
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
