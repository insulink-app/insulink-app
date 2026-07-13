import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_entry.dart';
import 'package:insulink/src/sport/logbook/workout_session_detail_page.dart';
import 'package:insulink/src/sport/sport_leading_badge.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_training_tile.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One logged activity — a routine session or an endurance training — as a
/// tappable list tile. Shared by the home activities list and the logbook.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.entry, this.showDate = true});

  final ActivityEntry entry;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final training = entry.training;
    if (training != null) {
      return CardioTrainingTile(training: training, showDate: showDate);
    }
    return _RoutineSessionTile(session: entry.session!, showDate: showDate);
  }
}

/// A completed routine as a list tile (name, set count, date/time), mirroring
/// [CardioTrainingTile] so both sit uniformly in a merged list.
class _RoutineSessionTile extends StatelessWidget {
  const _RoutineSessionTile({required this.session, required this.showDate});

  final WorkoutSession session;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final routine = context.read<TrainingState>().routineById(
      session.routineId,
    );
    return ListTile(
      tileColor: scheme.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      leading: const SportLeadingBadge(icon: PhosphorIconsRegular.calendarCheck),
      title: Text(
        routine?.name ??
            Locales.string(context, 'sport.logbook.deleted_routine'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        Locales.string(
          context,
          'sport.logbook.sets',
          params: ['${session.sets.length}'],
        ),
      ),
      trailing: _trailing(context, locale, started),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutSessionDetailPage(session: session),
        ),
      ),
    );
  }

  /// Right-hand corner: the time, with the date stacked above it where there is
  /// no day section header (the home list).
  Widget _trailing(
    BuildContext context,
    MaterialLocalizations locale,
    DateTime started,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final time = Text(
      locale.formatTimeOfDay(TimeOfDay.fromDateTime(started)),
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface.withValues(alpha: 0.7),
      ),
    );
    if (!showDate) {
      return time;
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          locale.formatMediumDate(started),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        time,
      ],
    );
  }
}
