import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/service_strings.dart';

import '../support/secure_storage_mock.dart';

/// ServiceStrings resolves localized text OUTSIDE the widget tree by reading the
/// persisted `language` key and walking the nested locale JSON (the `_resolve`
/// path, with the `_` self-value rule).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves a leaf key in the persisted language', () async {
    installSecureStorageMock()['language'] = 'de';
    expect(await ServiceStrings().get('alarm.low.title'), 'Zucker niedrig');
  });

  test('resolves a `_` self-value via path traversal', () async {
    installSecureStorageMock()['language'] = 'de';
    expect(await ServiceStrings().get('profile.glucose'), 'Glukose');
  });

  test('defaults to German when no language is stored', () async {
    installSecureStorageMock();
    expect(await ServiceStrings().get('alert.ok'), 'OK');
  });

  test('honours a stored English language', () async {
    installSecureStorageMock()['language'] = 'en';
    expect(await ServiceStrings().get('alarm.low.title'), 'Glucose low');
  });

  test('format substitutes the first # placeholder', () async {
    installSecureStorageMock()['language'] = 'de';
    expect(
      await ServiceStrings().format('sensor.life.remaining', 5),
      'noch 5 Tage',
    );
  });

  test('an unknown key falls back to the key itself', () async {
    installSecureStorageMock()['language'] = 'de';
    expect(await ServiceStrings().get('nope.missing'), 'nope.missing');
  });
}
