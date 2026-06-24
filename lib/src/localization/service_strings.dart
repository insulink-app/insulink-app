import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Resolves localized strings OUTSIDE the widget tree — for the foreground
/// service isolate and [G7Controller], which have no [BuildContext] and, in a
/// freshly-spawned isolate, no initialized [Locales] state either.
///
/// Reads the persisted language directly from secure storage (the same
/// `language` key [LocalePreference] writes) and loads that locale's JSON from
/// the asset bundle. Falls back to German, then to the key itself, on any
/// failure — so a missing translation degrades to a readable key, never a crash.
class ServiceStrings {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// The persisted language code, defaulting to German (the app's base locale).
  Future<String> _language() async {
    final lng = await _storage.read(key: 'language');
    return (lng == null || lng.isEmpty) ? 'de' : lng;
  }

  /// The translation for [key] in the active locale, or [key] if unavailable.
  Future<String> get(String key) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/locales/${await _language()}.json',
      );
      final map = json.decode(raw) as Map<String, dynamic>;
      return _resolve(map, key) ?? key;
    } catch (_) {
      return key;
    }
  }

  /// Walk the nested locale JSON along the dot-separated [key]. When the path
  /// lands on a node that also has children, its own value lives under `_`
  /// (e.g. `profile.glucose` is both a label and a prefix).
  String? _resolve(Map<String, dynamic> map, String key) {
    dynamic node = map;
    for (final part in key.split('.')) {
      if (node is! Map<String, dynamic>) {
        return null;
      }
      node = node[part];
    }
    if (node is Map<String, dynamic>) {
      node = node['_'];
    }
    return node?.toString();
  }

  /// Like [get] but substitutes the first `#` placeholder with [value] — the
  /// substitution convention used throughout the locale JSON files.
  Future<String> format(String key, Object value) async {
    final template = await get(key);
    return template.replaceFirst('#', '$value');
  }
}
