import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locale_preference.dart';
import 'package:insulink/src/localization/locales.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  setUp(() {
    backing = installSecureStorageMock();
    Locales.supportedLocales = const [Locale('de'), Locale('en')];
  });

  test('init with no stored language falls back to the first locale', () async {
    final pref = await LocalePreference.init();
    expect(pref.locale, Locales.supportedLocales.first);
  });

  test('init reads the persisted language', () async {
    backing['language'] = 'en';
    final pref = await LocalePreference.init();
    expect(pref.locale, const Locale('en'));
  });

  test('setLocale updates the cache, selectedLocale and storage', () async {
    final pref = await LocalePreference.init();
    pref.setLocale('en');
    expect(pref.locale, const Locale('en'));
    expect(Locales.selectedLocale, const Locale('en'));
    expect(backing['language'], 'en');
  });
}
