import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/calendar/day_activities_sheet.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Dot colour for logged routines on the sport calendar (brand colour).
Color calendarRoutineColor(ColorScheme scheme) => scheme.primary;

/// Dot colour for endurance trainings — a fixed warm accent so it reads apart
/// from the routine dot in both light and dark themes.
const calendarTrainingColor = Color(0xFFF5842C);

/// Month calendar of past sport activities: routines (session log) and endurance
/// trainings, colour-differentiated. Tapping a day with activities opens its
/// list.
class SportCalendarSection extends StatefulWidget {
  const SportCalendarSection({super.key});

  @override
  State<SportCalendarSection> createState() => _SportCalendarSectionState();
}

class _SportCalendarSectionState extends State<SportCalendarSection> {
  late DateTime _month = _firstOfMonth(DateTime.now());

  static DateTime _firstOfMonth(DateTime date) =>
      DateTime(date.year, date.month);

  bool _isThisMonth(DateTime other) =>
      other.year == _month.year && other.month == _month.month;

  void _step(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final routineDays = <int>{};
    for (final session in context.watch<TrainingState>().sessions) {
      final date = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
      if (_isThisMonth(date)) {
        routineDays.add(date.day);
      }
    }
    final trainingDays = <int>{};
    for (final training in context.watch<CardioTrainingState>().trainings) {
      final date = DateTime.fromMillisecondsSinceEpoch(training.startMs);
      if (_isThisMonth(date)) {
        trainingDays.add(date.day);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _monthBar(context),
        const SizedBox(height: 8),
        _weekdayHeader(context),
        const SizedBox(height: 4),
        _grid(context, routineDays, trainingDays),
        const SizedBox(height: 10),
        _legend(context),
      ],
    );
  }

  Widget _monthBar(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final atCurrent = _isThisMonth(_firstOfMonth(DateTime.now()));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _step(-1),
        ),
        Text(
          locale.formatMonthYear(_month),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          // No stepping into the future — there are no activities there.
          onPressed: atCurrent ? null : () => _step(1),
        ),
      ],
    );
  }

  int get _firstDayOfWeek => 1; // Monday-first, matching the app's locales.

  Widget _weekdayHeader(BuildContext context) {
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < 7; index += 1)
          Expanded(
            child: Center(
              child: Text(
                narrow[(_firstDayOfWeek + index) % 7],
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    Set<int> routineDays,
    Set<int> trainingDays,
  ) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstDow = _month.weekday % 7; // 0=Sun..6=Sat
    final leading = (firstDow - _firstDayOfWeek + 7) % 7;
    final cells = <Widget>[
      for (var blank = 0; blank < leading; blank += 1) const SizedBox(),
      for (var day = 1; day <= daysInMonth; day += 1)
        _dayCell(
          context,
          day,
          routineDays.contains(day),
          trainingDays.contains(day),
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: cells,
    );
  }

  Widget _dayCell(
    BuildContext context,
    int day,
    bool hasRoutine,
    bool hasTraining,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isToday = _isThisMonth(today) && today.day == day;
    final tappable = hasRoutine || hasTraining;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: tappable
          ? () => showDayActivitiesSheet(
              context,
              DateTime(_month.year, _month.month, day),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.15),
                  )
                : null,
            child: Text('$day', style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasRoutine) _dot(calendarRoutineColor(scheme)),
              if (hasRoutine && hasTraining) const SizedBox(width: 3),
              if (hasTraining) _dot(calendarTrainingColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dot(calendarRoutineColor(scheme)),
        const SizedBox(width: 6),
        LocaleText(
          'sport.calendar.routine',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(width: 20),
        _dot(calendarTrainingColor),
        const SizedBox(width: 6),
        LocaleText(
          'sport.calendar.training',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
