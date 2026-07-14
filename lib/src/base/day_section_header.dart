import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// The date heading above one day's entries on the logbook pages (meals,
/// activities, …). Recent days are named instead of dated, because that is how
/// the user thinks of them: "Heute", "Gestern", then weekday + date for the rest
/// of the past week, and a plain date once the weekday stops locating anything.
class DaySectionHeader extends StatelessWidget {
  const DaySectionHeader({super.key, required this.day, required this.first});

  /// Any moment on the day being labelled — the time of day is ignored.
  final DateTime day;

  /// Whether this is the list's first heading, which gets no top spacing.
  final bool first;

  /// How far back the weekday still helps place a day. Beyond a week "Dienstag"
  /// is just noise — the date carries it.
  static const _weekdayWithin = Duration(days: 7);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
      child: Text(
        _label(context),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  /// Ages the day in CALENDAR days, not elapsed hours: a meal logged at 23:00
  /// yesterday is "Gestern" an hour later, never "Heute".
  String _label(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final elapsed = _midnight(DateTime.now()).difference(_midnight(day));
    if (elapsed == Duration.zero) {
      return Locales.string(context, 'date.today');
    }
    if (elapsed == const Duration(days: 1)) {
      return Locales.string(context, 'date.yesterday');
    }
    if (elapsed <= _weekdayWithin) {
      return locale.formatFullDate(day);
    }
    return locale.formatShortDate(day);
  }

  DateTime _midnight(DateTime time) =>
      DateTime(time.year, time.month, time.day);
}
