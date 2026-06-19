import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './locales.dart';

class LocalePreference {
  late SharedPreferences prefs;
  static late LocalePreference instance;

  static Future<LocalePreference> init() async {
    LocalePreference.instance = LocalePreference();
    instance.prefs = await SharedPreferences.getInstance();
    return instance;
  }

  setLocale(String lng) {
    prefs.setString('language', lng);
    Locales.selectedLocale = Locale(lng);
  }

  Locale? get locale {
    try {
      final localeName = prefs.getString('language');
      if (localeName == null) Locales.supportedLocales.first;
      return Locale(localeName!);
    } catch (e) {
      return Locales.supportedLocales.first;
    }
  }
}
