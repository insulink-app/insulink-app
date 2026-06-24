import 'dart:collection';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:insulink/src/localization/locale_notifier.dart';
import 'package:insulink/src/localization/locale_preference.dart';
import 'package:intl/intl.dart' as intl;

class Locales {
  static late Locale selectedLocale;

  static String get lang => selectedLocale.languageCode;

  static bool get selectedLocaleRtl => selectedLocale.languageCode != 'en';

  final Locale locale;

  Locales(this.locale, {bool initialize = true}) {
    if (initialize) {
      selectedLocale = locale;
    }
  }

  static Locales? of(BuildContext context) {
    return Localizations.of<Locales>(context, Locales);
  }

  static bool isDirectionRTL(BuildContext context) {
    return intl.Bidi.isRtlLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  static late List<Locale> supportedLocales;

  static Future init(List<String> localeNames) async {
    try {
      supportedLocales = localeNames.map((name) => Locale(name)).toList();
      final pref = await LocalePreference.init();
      log('prefLocale: ${pref.locale}');
      Locales.selectedLocale = pref.locale ?? supportedLocales.first;
    } catch (e) {
      log('error while loading locale: $e');
    }
  }

  static dynamic change(BuildContext context, String lang) =>
      LocaleNotifier.of(context)!.change(lang);

  static Locale? currentLocale(BuildContext context) =>
      LocaleNotifier.of(context)!.locale;

  static const LocalizationsDelegate<Locales> delegate = _LocalesDelegate();

  static const delegates = [
    Locales.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Map<String, String> _localizedStings = HashMap();

  Future load() async {
    String lng = locale.languageCode;
    String jsonString = await rootBundle.loadString("assets/locales/$lng.json");

    Map<String, dynamic> jsonMap = json.decode(jsonString);

    _localizedStings = jsonMap.map((key, value) {
      return MapEntry(key, value.toString());
    });
  }

  String get(String key, [List<String>? params, List<String>? localeParams]) {
    key = key.replaceAll(" ", "_").toLowerCase();
    String result = _localizedStings[key] ?? "\$$key";
    bool localizeParams = localeParams != null;
    if (localeParams != null) {
      params = localeParams;
    }

    if (params != null && params.isNotEmpty) {
      for (int index = 0; index < params.length; index++) {
        String hash = "#" * (index + 1);
        final param = params[index];
        final resolved = localizeParams
            ? _localizedStings[param.replaceAll(' ', '_').toLowerCase()]
            : param;
        if (resolved != null) {
          result = result.replaceFirst(hash, resolved);
        }
      }
      result = result.replaceAll("#", "");
    }
    return result;
  }

  static String string(
    BuildContext context,
    String key, {
    List<String>? params,
    List<String>? localeParams,
  }) {
    return Localizations.of<Locales>(
      context,
      Locales,
    )!.get(key, params, localeParams);
  }
}

class _LocalesDelegate extends LocalizationsDelegate<Locales> {
  const _LocalesDelegate();

  @override
  bool isSupported(Locale locale) {
    for (Locale l in Locales.supportedLocales) {
      if (l.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<Locales> load(Locale locale) async {
    Locales localization = Locales(locale);
    await localization.load();
    return localization;
  }

  @override
  bool shouldReload(LocalizationsDelegate<Locales> old) {
    return false;
  }
}
