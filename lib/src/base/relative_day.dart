import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:intl/intl.dart';

/// A day as the lists name it: "Heute", "Gestern", otherwise the weekday and
/// the date ("So., 4. Okt."). Aged in calendar days, not elapsed hours, so
/// something at 23:00 yesterday is "Gestern" an hour later. The days are
/// compared as UTC midnights: local ones are 23 hours apart in spring, which
/// made yesterday "Heute".
class RelativeDay {
  const RelativeDay(this.day);

  final DateTime day;

  String label(BuildContext context) {
    final elapsed = _utcDay(DateTime.now()).difference(_utcDay(day)).inDays;
    if (elapsed == 0) {
      return Locales.string(context, 'date.today');
    }
    if (elapsed == 1) {
      return Locales.string(context, 'date.yesterday');
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.MMMEd(locale).format(day);
  }

  DateTime _utcDay(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day);
}
