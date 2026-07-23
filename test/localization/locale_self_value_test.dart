import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locales.dart';

/// Locks the `_` self-value handling: a node's own label is read by its PARENT
/// path, and the recurring `parent._` slip is healed back to it rather than
/// rendering a raw `$…` placeholder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('get() heals a mistaken parent._ key to the parent path', () async {
    final locales = Locales(const Locale('de'), initialize: false);
    await locales.load();

    final viaParent = locales.get('sport.summary');
    expect(viaParent, isNot(startsWith(r'$'))); // actually resolved
    expect(locales.get('sport.summary._'), viaParent);
  });
}
