import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/base/long_press_reorder.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/routines/routine_item_editor_sheet.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// A routine's exercises on its editing page (screen 32).
class RoutineItemsPanel extends StatelessWidget {
  const RoutineItemsPanel({
    super.key,
    required this.routine,
    required this.onAdd,
  });

  final SportRoutine routine;
  final VoidCallback onAdd;

  /// The exercises as rows in one panel, reordered by holding a row, closed by
  /// "+ Übung hinzufügen". The rows paint the panel themselves, so a row being
  /// dragged carries its look with it.
  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final training = context.read<TrainingState>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(InkRadius.panel),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(InkRadius.panel),
          border: Border.all(color: colors.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            footer: _addRow(colors, routine.items.isNotEmpty),
            proxyDecorator: (child, index, animation) =>
                _transparentDrag(context, child, index, animation),
            onReorderItem: (oldIndex, newIndex) =>
                training.reorderRoutineItems(routine.id, oldIndex, newIndex),
            buildDefaultDragHandles: false,
            children: [
              for (var index = 0; index < routine.items.length; index++)
                _itemRow(context, training, index),
            ].pickedUpByLongPress(),
          ),
        ),
      ),
    );
  }

  Widget _addRow(InsulinkColors colors, bool afterItems) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: afterItems ? Border(top: BorderSide(color: colors.line)) : null,
      ),
      child: InkWell(
        onTap: onAdd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 14,
              children: [
                Icon(PhosphorIconsBold.plus, size: 20, color: colors.accent),
                LocaleText(
                  'sport.routines.add_exercise',
                  style: InkText.rowTitle.copyWith(color: colors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Drag proxy without the default elevated shadow, in the panel's colour so
  /// the lifted row keeps its face while it moves.
  Widget _transparentDrag(
    BuildContext context,
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return Material(color: context.ink.panelRaised, child: child);
  }

  /// One exercise: grip, name over "2 Sätze × 18, 120 s Pause", bin. A tap
  /// edits its targets. A line parts it from the row above.
  Widget _itemRow(BuildContext context, TrainingState training, int index) {
    final colors = context.ink;
    final item = routine.items[index];
    final exercise = training.exerciseById(item.exerciseId);
    return DecoratedBox(
      key: ValueKey(item.id),
      decoration: BoxDecoration(
        border: index > 0 ? Border(top: BorderSide(color: colors.line)) : null,
      ),
      child: InkWell(
        onTap: () => showRoutineItemEditorSheet(
          context,
          routineId: routine.id,
          index: index,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            spacing: 14,
            children: [
              Icon(
                PhosphorIconsBold.dotsSixVertical,
                size: 20,
                color: colors.muted,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(exercise?.name ?? '—', style: InkText.rowTitle),
                    Text(
                      _summary(context, item, exercise),
                      style: InkText.label.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  PhosphorIconsBold.trash,
                  size: 20,
                  color: colors.muted,
                ),
                tooltip: Locales.string(context, 'sport.routines.remove_item'),
                onPressed: () => confirmDelete(
                  context,
                  messageKey: 'sport.routines.item_delete_confirm',
                  onConfirm: () =>
                      training.removeRoutineItem(routine.id, index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "2 Sätze × 18, 120 s Pause"; seconds for a timed exercise, the weight
  /// after the count for a weighted one.
  String _summary(
    BuildContext context,
    RoutineItem item,
    SportExercise? exercise,
  ) {
    final timed = exercise?.kind == ExerciseKind.timed;
    final weight = exercise?.kind == ExerciseKind.weighted
        ? ' · ${sportDecimal(item.targetWeight, 1)} kg'
        : '';
    return Locales.string(
      context,
      item.targetSets == 1
          ? 'sport.routines.item_summary_one'
          : 'sport.routines.item_summary',
      params: [
        '${item.targetSets}',
        '${item.target}${timed ? ' s' : ''}$weight',
        '${item.restSeconds}',
      ],
    );
  }
}
