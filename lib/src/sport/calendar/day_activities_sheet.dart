import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/sport/activity/activity_entry.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_section.dart';
import 'package:insulink/src/sport/logbook/workout_session_detail_page.dart';
import 'package:insulink/src/sport/logbook/workout_session_title.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_detail_page.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Lists the routines and endurance trainings logged on [day], each tappable to
/// its detail page. Opened from a day cell on the sport calendar.
Future<void> showDayActivitiesSheet(BuildContext context, DateTime day) {
  return showInkSheet(
    context: context,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: context.read<TrainingState>()),
        ChangeNotifierProvider.value(
          value: context.read<CardioTrainingState>(),
        ),
      ],
      child: _DayActivitiesSheet(day: day),
    ),
  );
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DayActivitiesSheet extends StatelessWidget {
  const _DayActivitiesSheet({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final cardio = context.watch<CardioTrainingState>();
    final entries = [
      for (final entry in mergedActivities(training.sessions, cardio.trainings))
        if (_isSameDay(DateTime.fromMillisecondsSinceEpoch(entry.startMs), day))
          entry,
    ];
    return InkSheet(
      title: Text(
        MaterialLocalizations.of(context).formatMediumDate(day),
        style: InkText.bigValue.copyWith(fontSize: 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scrollable so a busy day never overflows the sheet.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (entries.isEmpty) LocaleText('sport.calendar.empty'),
                for (final entry in entries)
                  entry.session != null
                      ? _routineTile(context, entry.session!)
                      : _trainingTile(context, entry.training!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routineTile(BuildContext context, WorkoutSession session) {
    return _tile(
      context,
      color: calendarRoutineColor(Theme.of(context).colorScheme),
      icon: PhosphorIconsBold.barbell,
      title: workoutSessionTitle(context, session),
      time: DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutSessionDetailPage(session: session),
        ),
      ),
    );
  }

  Widget _trainingTile(BuildContext context, CardioTraining ride) {
    return _tile(
      context,
      color: calendarTrainingColor,
      icon: ride.type.icon,
      title: Locales.string(context, ride.type.labelKey),
      time: DateTime.fromMillisecondsSinceEpoch(ride.startMs),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CardioDetailPage(training: ride),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String title,
    required DateTime time,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatTimeOfDay(TimeOfDay.fromDateTime(time)),
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
