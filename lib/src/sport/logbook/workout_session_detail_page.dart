import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Detail of a completed routine: header metrics (date, duration, sets) plus the
/// logged sets per exercise. Deletable via the app bar.
class WorkoutSessionDetailPage extends StatelessWidget {
  const WorkoutSessionDetailPage({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final routine = training.routineById(session.routineId);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          routine?.name ??
              Locales.string(context, 'sport.logbook.deleted_routine'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.logbook.delete_confirm',
              onConfirm: () {
                context.read<TrainingState>().removeSession(session.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        children: [
          _header(context, scheme),
          const SizedBox(height: 24),
          for (final row in _setRows(context, training)) row,
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${locale.formatMediumDate(started)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(started))}',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat(
                context,
                scheme,
                Icons.timer_outlined,
                'sport.logbook.duration',
                _duration(),
              ),
              _stat(
                context,
                scheme,
                Icons.repeat_rounded,
                'sport.routines.sets',
                '${session.sets.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _duration() {
    if (session.sets.isEmpty) {
      return '–';
    }
    final total = Duration(
      milliseconds: session.sets.last.atEpochMs - session.startedAtMs,
    );
    final minutes = total.inMinutes;
    final seconds = total.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _stat(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String labelKey,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Locales.string(context, labelKey),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  /// The sets grouped by exercise (in log order) as small cards.
  List<Widget> _setRows(BuildContext context, TrainingState training) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    String? lastExercise;
    var setNumber = 0;
    for (final set in session.sets) {
      if (set.exerciseId != lastExercise) {
        lastExercise = set.exerciseId;
        setNumber = 0;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 20, bottom: 8),
            child: Text(
              training.exerciseById(set.exerciseId)?.name ?? '—',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      setNumber += 1;
      rows.add(_setLine(context, scheme, setNumber, set));
    }
    return rows;
  }

  Widget _setLine(
    BuildContext context,
    ColorScheme scheme,
    int number,
    SetLog set,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              Locales.string(
                context,
                'sport.logbook.set_n',
                params: ['$number'],
              ),
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
            Text(
              _value(set),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  String _value(SetLog set) {
    final core = set.seconds != null ? '${set.seconds} s' : '${set.reps ?? 0}';
    final weight = set.weightKg != null
        ? ' · ${set.weightKg!.toStringAsFixed(1)} kg'
        : '';
    return '$core$weight';
  }
}
