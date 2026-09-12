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

  /// Load this locale's JSON. Decoded HERE rather than through
  /// `rootBundle.loadString`, which hands anything from 50 KiB up to `compute`
  /// — a real isolate that a `testWidgets` fake clock never lets finish, so the
  /// delegate's future stays pending and the whole app renders as a blank
  /// screen. Every widget test in the suite broke the day a locale file crossed
  /// that line; the decode is microseconds, so keep it inline.
  Future load() async {
    final data = await rootBundle.load(
      'assets/locales/${locale.languageCode}.json',
    );
    final jsonString = utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStings = _flatten(jsonMap);
  }

  /// Flatten the nested locale JSON to the dot-separated keys the app looks up.
  /// A `_` key carries a node's own value when it ALSO has children (e.g.
  /// `profile.glucose` is both a section label and a prefix), so it maps to the
  /// parent path rather than `parent._`.
  Map<String, String> _flatten(Map<String, dynamic> map, [String prefix = '']) {
    final flat = <String, String>{};
    map.forEach((key, value) {
      final path = key == '_'
          ? prefix
          : (prefix.isEmpty ? key : '$prefix.$key');
      if (value is Map<String, dynamic>) {
        flat.addAll(_flatten(value, path));
      } else {
        flat[path] = value.toString();
      }
    });
    return flat;
  }

  String get(String key, [List<String>? params, List<String>? localeParams]) {
    key = key.replaceAll(" ", "_").toLowerCase();
    // A `_` self-value flattens to its PARENT path (see `_flatten`), so a
    // `parent._` key never exists in the flat map — it is always the mistaken
    // form of `parent`. Heal it instead of returning the raw `$parent._`
    // placeholder (a recurring slip when adding a section label).
    if (key.endsWith('._')) {
      key = key.substring(0, key.length - 2);
    }
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

  /// Whether this locale carries [key] at all.
  ///
  /// A missing key resolves to `$key` rather than to nothing, so a caller that
  /// walks a numbered run of keys cannot recognise the end by comparing against
  /// the key itself — it has to ask.
  bool has(String key) =>
      _localizedStings.containsKey(key.replaceAll(' ', '_').toLowerCase());

  /// Whether the active locale carries [key].
  static bool contains(BuildContext context, String key) =>
      Localizations.of<Locales>(context, Locales)!.has(key);

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
