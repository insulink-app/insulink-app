import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/editor_sheet.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Edit a single logged set of a completed session: reps or seconds (per the
/// exercise kind) and — for weighted exercises — the weight. Each value steps
/// with +/- or by tapping it. Applies live via [onChanged].
Future<void> showSetEditorSheet(
  BuildContext context, {
  required SetLog set,
  required ExerciseKind kind,
  required ValueChanged<SetLog> onChanged,
}) {
  return showInkSheet(
    context: context,
    builder: (_) => _SetEditorSheet(set: set, kind: kind, onChanged: onChanged),
  );
}

class _SetEditorSheet extends StatefulWidget {
  const _SetEditorSheet({
    required this.set,
    required this.kind,
    required this.onChanged,
  });

  final SetLog set;
  final ExerciseKind kind;
  final ValueChanged<SetLog> onChanged;

  @override
  State<_SetEditorSheet> createState() => _SetEditorSheetState();
}

class _SetEditorSheetState extends State<_SetEditorSheet> {
  late SetLog _set = widget.set;

  void _apply(SetLog next) {
    HapticFeedback.selectionClick();
    setState(() => _set = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final isTimed = widget.kind == ExerciseKind.timed;
    final isWeighted = widget.kind == ExerciseKind.weighted;
    final accent = Theme.of(context).colorScheme.primary;
    final amount = isTimed ? (_set.seconds ?? 0) : (_set.reps ?? 0);
    return EditorSheet(
      titleKey: 'sport.logbook.edit_set',
      valueText: '',
      accent: accent,
      children: [
        _stepper(
          labelKey: isTimed ? 'sport.routines.seconds' : 'sport.routines.reps',
          valueText: isTimed ? '$amount s' : '$amount',
          accent: accent,
          current: amount.toDouble(),
          min: 0,
          max: 600,
          step: isTimed ? 5 : 1,
          apply: (value) => isTimed
              ? _set.copyWith(seconds: value.round())
              : _set.copyWith(reps: value.round()),
        ),
        if (isWeighted) ...[
          const SizedBox(height: 8),
          _stepper(
            labelKey: 'sport.routines.weight',
            valueText: '${sportDecimal(_set.weightKg ?? 0, 1)} kg',
            accent: accent,
            current: _set.weightKg ?? 0,
            min: 0,
            max: 500,
            step: 2.5,
            decimal: true,
            apply: (value) => _set.copyWith(weightKg: value),
          ),
        ],
      ],
    );
  }

  Widget _stepper({
    required String labelKey,
    required String valueText,
    required Color accent,
    required double current,
    required double min,
    required double max,
    required double step,
    bool decimal = false,
    required SetLog Function(double value) apply,
  }) {
    void set(double value) => _apply(apply(value.clamp(min, max).toDouble()));
    return GlucoseStepperRow(
      labelKey: labelKey,
      valueText: valueText,
      accent: accent,
      onMinus: () => set(current - step),
      onPlus: () => set(current + step),
      valueChild: SportEditableNumber(
        key: ValueKey('$labelKey-$valueText'),
        valueText: valueText,
        initial: current,
        min: min,
        max: max,
        decimal: decimal,
        onSubmit: set,
      ),
    );
  }
}
