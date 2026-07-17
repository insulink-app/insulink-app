import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/set_editor_sheet.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/training_metrics_chart.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Detail of a completed routine: header metrics (date, duration, sets) plus the
/// logged sets per exercise. Sets are editable in place (tap to change values,
/// delete, or add a set per exercise); the whole entry is deletable via the app
/// bar.
class WorkoutSessionDetailPage extends StatelessWidget {
  const WorkoutSessionDetailPage({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    // Re-read the live session so in-place edits reflect immediately (the passed
    // one is a snapshot from the log list).
    final current = training.sessions.firstWhere(
      (other) => other.id == session.id,
      orElse: () => session,
    );
    final routine = training.routineById(current.routineId);
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
            icon: const Icon(PhosphorIconsBold.trash),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.logbook.delete_confirm',
              onConfirm: () {
                context.read<TrainingState>().removeSession(current.id);
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
          _header(context, scheme, current),
          const SizedBox(height: 20),
          _metricsChart(context, current),
          const SizedBox(height: 24),
          for (final row in _setRows(context, training, current)) row,
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    WorkoutSession session,
  ) {
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
                PhosphorIconsBold.timer,
                'sport.logbook.duration',
                _duration(session),
              ),
              _stat(
                context,
                scheme,
                PhosphorIconsBold.repeat,
                'sport.routines.sets',
                '${session.sets.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The glucose + heart-rate chart over the session span — reused from the
  /// cardio detail page. No map here, so the hover callback is a no-op (the
  /// tooltip + haptics still work).
  Widget _metricsChart(BuildContext context, WorkoutSession session) {
    final endMs = session.sets.isEmpty
        ? session.startedAtMs
        : session.sets.last.atEpochMs;
    // Pad the query so the chart can show the reading just before/after a short
    // workout too.
    const pad = Duration(minutes: 15);
    final glucose = context.watch<CgmController>().archiveBetween(
      DateTime.fromMillisecondsSinceEpoch(session.startedAtMs).subtract(pad),
      DateTime.fromMillisecondsSinceEpoch(endMs).add(pad),
    );
    return TrainingMetricsChart(
      startMs: session.startedAtMs,
      endMs: endMs,
      glucose: glucose,
      track: const [],
      onHoverMs: (_) {},
    );
  }

  String _duration(WorkoutSession session) {
    if (session.sets.isEmpty) {
      return '–';
    }
    final total = Duration(
      milliseconds: session.sets.last.atEpochMs - session.startedAtMs,
    );
    return sportClock(total.inSeconds);
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
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
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

  /// The sets grouped by exercise (in log order) as small editable cards, each
  /// group closed by an "add set" button.
  List<Widget> _setRows(
    BuildContext context,
    TrainingState training,
    WorkoutSession session,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    String? lastExercise;
    var setNumber = 0;
    for (var index = 0; index < session.sets.length; index += 1) {
      final set = session.sets[index];
      final isNewGroup = set.exerciseId != lastExercise;
      if (isNewGroup && lastExercise != null) {
        rows.add(_addSetButton(context, scheme, training, session, index - 1));
      }
      if (isNewGroup) {
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
      rows.add(_setLine(context, scheme, training, session, index, setNumber));
    }
    if (session.sets.isNotEmpty) {
      rows.add(
        _addSetButton(
          context,
          scheme,
          training,
          session,
          session.sets.length - 1,
        ),
      );
    }
    return rows;
  }

  Widget _setLine(
    BuildContext context,
    ColorScheme scheme,
    TrainingState training,
    WorkoutSession session,
    int index,
    int number,
  ) {
    final set = session.sets[index];
    final kind =
        training.exerciseById(set.exerciseId)?.kind ?? ExerciseKind.reps;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showSetEditorSheet(
            context,
            set: set,
            kind: kind,
            onChanged: (edited) =>
                _replaceSet(training, session, index, edited),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Locales.string(
                        context,
                        'sport.logbook.set_n',
                        params: ['$number'],
                      ),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    if (_meta(context, set) case final meta?) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  _value(set),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    PhosphorIconsBold.x,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                  onPressed: () => confirmDelete(
                    context,
                    messageKey: 'sport.logbook.delete_set_confirm',
                    onConfirm: () => _deleteSet(training, session, index),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addSetButton(
    BuildContext context,
    ColorScheme scheme,
    TrainingState training,
    WorkoutSession session,
    int afterIndex,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _addSet(training, session, afterIndex),
        icon: const Icon(PhosphorIconsBold.plus, size: 18),
        label: LocaleText('sport.logbook.add_set'),
      ),
    );
  }

  void _replaceSet(
    TrainingState training,
    WorkoutSession session,
    int index,
    SetLog edited,
  ) {
    final sets = [...session.sets]..[index] = edited;
    training.updateSession(session.copyWith(sets: sets));
  }

  void _deleteSet(TrainingState training, WorkoutSession session, int index) {
    final sets = [...session.sets]..removeAt(index);
    training.updateSession(session.copyWith(sets: sets));
  }

  /// Adds a set right after [afterIndex], copying that set's values so the new
  /// row starts from the same reps/weight the user just did.
  void _addSet(TrainingState training, WorkoutSession session, int afterIndex) {
    final template = session.sets[afterIndex];
    final copy = SetLog(
      exerciseId: template.exerciseId,
      reps: template.reps,
      seconds: template.seconds,
      weightKg: template.weightKg,
      atEpochMs: template.atEpochMs,
    );
    final sets = [...session.sets]..insert(afterIndex + 1, copy);
    training.updateSession(session.copyWith(sets: sets));
  }

  /// The secondary line under a set: its actual duration and the rest that
  /// followed it, each when recorded. Null when neither exists (legacy/manual
  /// sets) so no empty line renders.
  String? _meta(BuildContext context, SetLog set) {
    final parts = <String>[
      if (set.durationSecs != null)
        '${Locales.string(context, 'sport.logbook.duration')} ${_clock(set.durationSecs!)}',
      if (set.restSecs != null)
        '${Locales.string(context, 'sport.logbook.rest')} ${_clock(set.restSecs!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Seconds as `m:ss`.
  String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _value(SetLog set) {
    final core = set.seconds != null ? '${set.seconds} s' : '${set.reps ?? 0}';
    final weight = set.weightKg != null
        ? ' · ${sportDecimal(set.weightKg!, 1)} kg'
        : '';
    return '$core$weight';
  }
}
