import 'package:flutter/material.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

/// Create or edit an exercise: name + kind (reps / weight / time).
Future<void> showExerciseEditorSheet(
  BuildContext context, {
  SportExercise? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<TrainingState>(),
      child: _ExerciseEditorSheet(existing: existing),
    ),
  );
}

class _ExerciseEditorSheet extends StatefulWidget {
  const _ExerciseEditorSheet({this.existing});

  final SportExercise? existing;

  @override
  State<_ExerciseEditorSheet> createState() => _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends State<_ExerciseEditorSheet> {
  late final TextEditingController _name;
  late ExerciseKind _kind;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '')
      ..addListener(() => setState(() {}));
    _kind = widget.existing?.kind ?? ExerciseKind.reps;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final training = context.read<TrainingState>();
    final name = _name.text.trim();
    final existing = widget.existing;
    if (existing == null) {
      training.addExercise(name, _kind);
    } else {
      training.updateExercise(existing.copyWith(name: name, kind: _kind));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GrabHandle(),
          const SizedBox(height: 20),
          LocaleText(
            widget.existing == null
                ? 'sport.exercises.add'
                : 'sport.exercises.edit',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: Locales.string(context, 'sport.exercises.name'),
            ),
          ),
          const SizedBox(height: 20),
          _KindSelector(
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: LocaleText('alert.done'),
          ),
        ],
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onChanged});

  final ExerciseKind selected;
  final ValueChanged<ExerciseKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          for (final kind in ExerciseKind.values)
            Expanded(child: _segment(context, kind, scheme)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, ExerciseKind kind, ColorScheme scheme) {
    final isSelected = kind == selected;
    return GestureDetector(
      onTap: () => onChanged(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.onSurface.withValues(alpha: 0.85)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          Locales.string(context, 'sport.exercises.kind.${kind.name}'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? scheme.surface : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
