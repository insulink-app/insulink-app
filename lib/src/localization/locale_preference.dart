import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import './locales.dart';

/// Persists the selected app language in [FlutterSecureStorage] under the same
/// `language` key the rest of the app uses. The value is loaded once in [init]
/// (awaited before `runApp`) and cached in memory so [locale] stays synchronous.
class LocalePreference {
  static const _storage = FlutterSecureStorage();
  static late LocalePreference instance;

  String? _language;

  static Future<LocalePreference> init() async {
    LocalePreference.instance = LocalePreference();
    instance._language = await _storage.read(key: 'language');
    return instance;
  }

  void setLocale(String lng) {
    _language = lng;
    Locales.selectedLocale = Locale(lng);
    // Fire-and-forget: the in-memory value already reflects the change.
    _storage.write(key: 'language', value: lng);
  }

  Locale? get locale {
    final lng = _language;
    if (lng == null || lng.isEmpty) {
      return Locales.supportedLocales.first;
    }
    return Locale(lng);
  }
}
