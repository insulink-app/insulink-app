import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// A dash standing on its own as punctuation: an em dash, an en dash, or a
/// hyphen with space around it. A hyphen INSIDE a word is untouched, because
/// German compounds legitimately carry one (`Glukose-Alarme`, `App-Reset`).
final RegExp _looseDash = RegExp(r'(^|\s)[—–-](\s|$)');

/// Every leaf string in a locale file, keyed by its dotted path.
Map<String, String> _strings(Map<String, dynamic> tree, [String prefix = '']) {
  final flat = <String, String>{};
  tree.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      flat.addAll(_strings(value, path));
    } else if (value is String) {
      flat[path] = value;
    }
  });
  return flat;
}

Map<String, String> _localeFile(String language) {
  final raw = File('assets/locales/$language.json').readAsStringSync();
  return _strings(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  /// A dash reads as an afterthought bolted onto a sentence, and the em dash in
  /// particular reads as machine-written. Every one of them can be a comma, a
  /// colon or a full stop, and the sentence is better for it. Enforced here
  /// rather than left to whoever writes the next string.
  group('user-facing strings carry no dash as punctuation', () {
    for (final language in const ['de', 'en']) {
      test('$language.json', () {
        final offenders = <String>[
          for (final entry in _localeFile(language).entries)
            if (_looseDash.hasMatch(entry.value)) '${entry.key}: ${entry.value}',
        ];
        expect(
          offenders,
          isEmpty,
          reason: 'Rewrite with a comma, a colon or a full stop instead:\n'
              '${offenders.join('\n')}',
        );
      });
    }
  });
}
