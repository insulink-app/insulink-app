import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/set_editor_sheet.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The logged sets of a workout grouped by exercise, one panel of editable
/// rows per exercise (tap to change values, delete, or add a set). Reused by the
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _setRows(context, training, current),
    );
  }

  /// The sets grouped by exercise (in log order): the exercise's name as a
  /// section title, then its sets as rows in one panel, closed by an "add
  /// set" row.
  List<Widget> _setRows(
    BuildContext context,
    TrainingState training,
    WorkoutSession session,
  ) {
    final groups = <Widget>[];
    var rows = <Widget>[];
    String? exerciseId;
    var setNumber = 0;
    void close(int lastIndex) {
      rows.add(_addSetRow(context, training, session, lastIndex));
      groups.add(_group(context, training, exerciseId!, rows, groups.isEmpty));
      rows = <Widget>[];
    }

    for (var index = 0; index < session.sets.length; index += 1) {
      final set = session.sets[index];
      if (set.exerciseId != exerciseId) {
        if (exerciseId != null) {
          close(index - 1);
        }
        exerciseId = set.exerciseId;
        setNumber = 0;
      }
      setNumber += 1;
      rows.add(_setLine(context, training, session, index, setNumber));
    }
    if (exerciseId != null) {
      close(session.sets.length - 1);
    }
    return groups;
  }

  Widget _group(
    BuildContext context,
    TrainingState training,
    String exerciseId,
    List<Widget> rows,
    bool first,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, first ? 8 : 28, 8, 12),
          child: Text(
            training.exerciseById(exerciseId)?.name ?? '—',
            style: InkText.section,
          ),
        ),
        InkPanel.list(rows: rows),
      ],
    );
  }

  /// One set: "Satz n" over its duration and rest, the count on the right,
  /// and × to delete it. A tap edits it.
  Widget _setLine(
    BuildContext context,
    TrainingState training,
    WorkoutSession session,
    int index,
    int number,
  ) {
    final colors = context.ink;
    final set = session.sets[index];
    final kind =
        training.exerciseById(set.exerciseId)?.kind ?? ExerciseKind.reps;
    return InkWell(
      onTap: () => showSetEditorSheet(
        context,
        set: set,
        kind: kind,
        onChanged: (edited) => _replaceSet(training, session, index, edited),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    Locales.string(
                      context,
                      'sport.logbook.set_n',
                      params: ['$number'],
                    ),
                    style: InkText.rowTitle,
                  ),
                  if (_meta(context, set) case final meta?)
                    Text(
                      meta,
                      style: InkText.label.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
            _value(context, set),
            IconButton(
              icon: Icon(PhosphorIconsBold.x, size: 18, color: colors.muted),
              tooltip: Locales.string(context, 'sport.logbook.delete_set'),
              onPressed: () => confirmDelete(
                context,
                messageKey: 'sport.logbook.delete_set_confirm',
                onConfirm: () => _deleteSet(training, session, index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The panel's last row: "+ Satz hinzufügen" in the accent.
  Widget _addSetRow(
    BuildContext context,
    TrainingState training,
    WorkoutSession session,
    int afterIndex,
  ) {
    final accent = context.ink.accent;
    return InkWell(
      onTap: () => _addSet(training, session, afterIndex),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 14,
            children: [
              Icon(PhosphorIconsBold.plus, size: 20, color: accent),
              LocaleText(
                'sport.logbook.add_set',
                style: InkText.rowTitle.copyWith(color: accent),
              ),
            ],
          ),
        ),
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

  /// The count large with its unit small: "45 Wdh.", "30 s", and the weight
  /// after it when one was used.
  Widget _value(BuildContext context, SetLog set) {
    final colors = context.ink;
    final seconds = set.seconds;
    final number = seconds != null ? '$seconds' : '${set.reps ?? 0}';
    final unitKey = seconds != null
        ? 'sport.stats.seconds'
        : 'sport.stats.reps';
    final unit = Locales.string(context, unitKey).replaceFirst('# ', '');
    final weight = set.weightKg;
    return Text.rich(
      TextSpan(
        text: number,
        style: InkText.bigValue.copyWith(fontSize: 18),
        children: [
          TextSpan(
            text: ' $unit',
            style: InkText.label.copyWith(color: colors.muted),
          ),
          if (weight != null)
            TextSpan(
              text: ' · ${sportDecimal(weight, 1)} kg',
              style: InkText.label.copyWith(color: colors.muted),
            ),
        ],
      ),
    );
  }
}
