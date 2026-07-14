import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/day_section_header.dart';
import 'package:insulink/src/localization/locales.dart';

import '../support/secure_storage_mock.dart';

/// The logbook day headings: named for the days a user thinks of by name, dated
/// for the rest. Pumps the real widget through the localization stack, since the
/// labels come half from [Locales] and half from [MaterialLocalizations].
///
/// One test on purpose, like locale_widget_test.dart: [Locales] keeps global
/// singletons, and a second [testWidgets] in the same file inherits them in a
/// state where the MaterialApp never builds its home.
///
/// Asserts on the PRESENCE of the weekday rather than on exact strings — the
/// date format itself is the locale's business, not this widget's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  Widget app(DateTime day) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: Locales.delegates,
    supportedLocales: Locales.supportedLocales,
    home: DaySectionHeader(day: day, first: true),
  );

  testWidgets('names today/yesterday, dates the rest, drops the weekday after '
      'a week', (tester) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);

    Future<String> label(DateTime day) async {
      await tester.pumpWidget(app(day));
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.byType(Text)).data!;
    }

    String weekdayOf(DateTime day) => weekdays[day.weekday - 1];

    final now = DateTime.now();
    expect(await label(now), 'Heute');
    expect(await label(now.subtract(const Duration(days: 1))), 'Gestern');

    // Aged in CALENDAR days, not elapsed hours: 23:55 yesterday is "Gestern"
    // five minutes later — the trap a naive `difference(...).inDays == 0` falls
    // into.
    final yesterdayLateEvening = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(minutes: 5));
    expect(await label(yesterdayLateEvening), 'Gestern');

    final threeDaysAgo = now.subtract(const Duration(days: 3));
    final withinWeek = await label(threeDaysAgo);
    expect(withinWeek, contains(weekdayOf(threeDaysAgo)));
    expect(withinWeek, contains('${threeDaysAgo.year}'));

    // The boundary is inclusive: a week ago still carries its weekday.
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    expect(await label(sevenDaysAgo), contains(weekdayOf(sevenDaysAgo)));

    final longAgo = now.subtract(const Duration(days: 8));
    final beyondWeek = await label(longAgo);
    expect(beyondWeek, isNot(contains(weekdayOf(longAgo))));
    expect(beyondWeek, contains('${longAgo.year}'));
    expect(beyondWeek, contains('${longAgo.day}'));
  });
}
