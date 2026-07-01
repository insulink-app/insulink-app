import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/workout_session_detail_page.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Logbuch der durchgeführten Routinen: jede [WorkoutSession] mit Datum,
/// Routinenname, Dauer und Satz-Anzahl (neueste zuerst). Reine Lese-Ansicht über
/// die bereits gespeicherten Sessions.
class WorkoutLogPage extends StatelessWidget {
  const WorkoutLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final sessions = training.sessions;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.logbook'),
      ),
      body: sessions.isEmpty
          ? Center(child: LocaleText('sport.logbook.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                for (var index = sessions.length - 1; index >= 0; index--)
                  _row(context, training, sessions[index]),
              ],
            ),
    );
  }

  Widget _row(BuildContext context, TrainingState training, WorkoutSession session) {
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
          routine?.name ?? Locales.string(context, 'sport.logbook.deleted_routine'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${locale.formatMediumDate(started)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(started))}',
        ),
        trailing: Text(
          Locales.string(context, 'sport.logbook.sets', params: ['${session.sets.length}']),
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
