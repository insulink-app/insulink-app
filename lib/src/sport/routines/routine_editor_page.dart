import 'package:flutter/material.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:insulink/src/base/page_primary_button.dart';
import 'package:insulink/src/base/labeled_field.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/routines/routine_duration.dart';
import 'package:insulink/src/sport/routines/routine_items_panel.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Edit a routine: name, ordered exercise list (reorder by holding), add
/// exercise, and start the workout.
class RoutineEditorPage extends StatefulWidget {
  const RoutineEditorPage({super.key, required this.routineId});

  final String routineId;

  @override
  State<RoutineEditorPage> createState() => _RoutineEditorPageState();
}

class _RoutineEditorPageState extends State<RoutineEditorPage> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final routine = context.read<TrainingState>().routineById(widget.routineId);
    _name = TextEditingController(text: routine?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  TrainingState get _training => context.read<TrainingState>();

  void _addExercise() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExercisesPage(
          onPick: (exercise) =>
              _training.addRoutineItem(widget.routineId, exercise.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routine = context.watch<TrainingState>().routineById(
      widget.routineId,
    );
    if (routine == null) {
      return const Scaffold();
    }
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.routines.edit'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.trash),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.routines.delete_confirm',
              onConfirm: () {
                _training.removeRoutine(routine.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: routine.items.isEmpty ? null : _startBar(routine),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          16,
          InkSpace.panelMargin,
          24,
        ),
        children: [
          LabeledField(
            labelKey: 'sport.routines.name',
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) =>
                  _training.renameRoutine(routine.id, value.trim()),
            ),
          ),
          _itemsHeader(routine),
          if (routine.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: LocaleText(
                'sport.routines.no_items',
                style: InkText.label.copyWith(color: context.ink.muted),
              ),
            ),
          RoutineItemsPanel(routine: routine, onAdd: _addExercise),
        ],
      ),
    );
  }

  /// "Übungen" with the estimated total on the right ("ca. 1 h 8 min").
  Widget _itemsHeader(SportRoutine routine) {
    final colors = context.ink;
    final seconds = estimatedRoutineSeconds(
      routine,
      _training.exercises,
      _training.sessions,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: LocaleText(
              'sport.summary.exercises',
              style: InkText.section,
            ),
          ),
          if (routine.items.isNotEmpty) ...[
            Icon(PhosphorIconsBold.clock, size: 18, color: colors.muted),
            const SizedBox(width: 6),
            Text(
              Locales.string(
                context,
                'sport.routines.est_duration',
                params: [formatSensorDuration(seconds)],
              ),
              style: InkText.label.copyWith(color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// "Routine starten", pinned under the list.
  Widget _startBar(SportRoutine routine) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        8,
        InkSpace.panelMargin,
        16,
      ),
      child: PagePrimaryButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutRunnerPage(routine: routine),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const Icon(PhosphorIconsFill.play, size: 20),
            LocaleText('sport.routines.start'),
          ],
        ),
      ),
    );
  }
}
