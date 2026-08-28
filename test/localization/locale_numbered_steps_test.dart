import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Numbered locale keys (`..._step_1`, `_step_2`, …) are read until the first
/// number the locale has no key for. That only works if the run is unbroken and
/// starts at one — a gap would cut the list short, and a stray higher number
/// would never be reached.
///
/// The reason this is worth a test: a missing key resolves to `$key` rather than
/// to nothing, so a run that misbehaves shows raw placeholders on screen instead
/// of failing loudly. That is exactly how `attach_step_6` once made it onto the
/// activation page.
void main() {
  Map<String, dynamic> section(String language) {
    final raw = File('assets/locales/$language.json').readAsStringSync();
    final tree = jsonDecode(raw) as Map<String, dynamic>;
    return (tree['pump'] as Map<String, dynamic>)['activate']
        as Map<String, dynamic>;
  }

  for (final language in const ['de', 'en']) {
    test('$language: the attach steps are an unbroken run from one', () {
      final keys = section(language)
          .keys
          .where((key) => key.startsWith('attach_step_'))
          .map((key) => int.parse(key.substring('attach_step_'.length)))
          .toList()
        ..sort();

      expect(keys, isNotEmpty);
      expect(keys, [for (var number = 1; number <= keys.length; number++) number]);
    });
  }

  test('both locales carry the same number of steps', () {
    int count(String language) => section(language)
        .keys
        .where((key) => key.startsWith('attach_step_'))
        .length;
    expect(count('de'), count('en'));
  });
}
