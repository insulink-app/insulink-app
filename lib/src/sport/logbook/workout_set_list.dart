import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/set_editor_sheet.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The logged sets of a workout grouped by exercise, as small editable cards
/// (tap to change values, delete, or add a set per exercise). Reused by the
/// logbook detail page and the end-of-workout summary. Re-reads the live session
/// from [TrainingState] by id so in-place edits reflect immediately (the passed
/// [session] is a snapshot from the log list).
class WorkoutSetList extends StatelessWidget {
  const WorkoutSetList({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final current = training.sessions.firstWhere(
      (other) => other.id == session.id,
      orElse: () => session,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _setRows(context, training, current),
    );
  }

  /// The sets grouped by exercise (in log order), each group closed by an
  /// "add set" button.
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
