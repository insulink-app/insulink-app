import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locales.dart';

/// Loads the real bundled locale JSON and exercises the flatten + lookup path,
/// including the `_` self-value convention for nodes that are both a label and
/// a prefix.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Locales> loaded(String code) async {
    final locales = Locales(Locale(code));
    await locales.load();
    return locales;
  }

  test('resolves leaf keys from the nested German JSON', () async {
    final de = await loaded('de');
    expect(de.get('alert.ok'), 'OK');
    expect(de.get('profile.glucose.target'), 'Zielbereich');
    expect(de.get('statistics.range.in_range'), 'Im Zielbereich');
  });

  test('a `_` self-value resolves to the parent path', () async {
    final de = await loaded('de');
    // profile.glucose is both the section label AND the prefix of .target etc.
    expect(de.get('profile.glucose'), 'Glukose');
    expect(de.get('profile.bolus'), 'Bolus');
  });

  test('substitutes the # placeholder with a param', () async {
    final de = await loaded('de');
    expect(de.get('sensor.life.remaining', ['5']), 'noch 5 Tage');
  });

  test('unknown keys fall back to a visible \$key marker', () async {
    final de = await loaded('de');
    expect(de.get('does.not.exist'), startsWith('\$'));
  });

  test('English locale resolves the same keys in English', () async {
    final en = await loaded('en');
    expect(en.get('alert.ok'), 'OK');
    expect(en.get('profile.glucose'), 'Glucose');
    expect(en.get('statistics.range.in_range'), 'In Range');
  });
}
