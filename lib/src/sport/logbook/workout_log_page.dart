import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/workout_session_detail_page.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';
import 'package:provider/provider.dart';

/// Logbook of completed routines: each [WorkoutSession] with date, routine name,
/// duration and set count (newest first). Read-only view over the already-saved
/// sessions.
class WorkoutLogPage extends StatelessWidget {
  const WorkoutLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final sessions = training.sessions;
    final snapshot = training.activeWorkout;
    final resumeRoutine = snapshot == null
        ? null
        : training.routineById(snapshot.routineId);
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.logbook'),
      ),
      body: sessions.isEmpty && resumeRoutine == null
          ? Center(child: LocaleText('sport.logbook.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                if (resumeRoutine != null)
                  _resumeCard(context, snapshot!, resumeRoutine),
                for (var index = sessions.length - 1; index >= 0; index--)
                  _row(context, training, sessions[index]),
              ],
            ),
    );
  }

  /// Banner to resume a workout that is still in progress (paused / left via
  /// back). Reopens the runner with the saved snapshot.
  Widget _resumeCard(
    BuildContext context,
    WorkoutSnapshot snapshot,
    SportRoutine routine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  WorkoutRunnerPage(routine: routine, resume: snapshot),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill, size: 36, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocaleText(
                        'sport.logbook.resume',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        routine.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    TrainingState training,
    WorkoutSession session,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    final routine = training.routineById(session.routineId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        leading: Icon(Icons.event_available, color: scheme.primary),
        title: Text(
          routine?.name ??
              Locales.string(context, 'sport.logbook.deleted_routine'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${locale.formatMediumDate(started)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(started))}',
        ),
        trailing: Text(
          Locales.string(
            context,
            'sport.logbook.sets',
            params: ['${session.sets.length}'],
          ),
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutSessionDetailPage(session: session),
          ),
        ),
      ),
    );
  }
}
