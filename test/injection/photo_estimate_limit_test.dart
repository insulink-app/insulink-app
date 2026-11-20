import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/injection/photo_estimate_limit.dart';
import 'package:insulink/src/localization/locales.dart';

import '../support/locale_pump.dart';
import '../support/secure_storage_mock.dart';

/// The 1605 reply carries its reset as epoch ms; the dialog says when and how
/// long. One widget test on purpose: [Locales] keeps global singletons (see
/// day_section_header_test.dart).
void main() {
  test('the reset is read from epoch ms, and missing when absent', () {
    final resetsAt = DateTime(2026, 11, 20, 18, 30);
    final limit = PhotoEstimateLimit.fromJson({
      'resets_at': resetsAt.millisecondsSinceEpoch,
    });
    expect(limit.resetsAt, resetsAt);
    expect(PhotoEstimateLimit.fromJson(null).resetsAt, isNull);
    expect(PhotoEstimateLimit.fromJson({'resets_at': 'soon'}).resetsAt, isNull);
  });

  testWidgets('the reset is told as a time and a wait', (tester) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Locales.delegates,
        supportedLocales: Locales.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await settleLocalized(tester);

    final soon = DateTime.now().add(const Duration(hours: 1, minutes: 30));
    expect(
      PhotoEstimateLimit(soon).resetText(captured),
      contains('1 h 30 min'),
    );
    final later = DateTime.now().add(const Duration(days: 2));
    expect(PhotoEstimateLimit(later).resetText(captured), contains(', '));
    expect(
      const PhotoEstimateLimit(null).resetText(captured),
      contains('not known'),
    );
  });
}
