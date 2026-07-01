import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/routines/routine_item_editor_sheet.dart';
import 'package:insulink/src/sport/sport_add_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:provider/provider.dart';

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
            icon: const Icon(Icons.delete_outline),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: Locales.string(context, 'sport.routines.name'),
              ),
              onChanged: (value) =>
                  _training.renameRoutine(routine.id, value.trim()),
            ),
          ),
          Expanded(child: _itemsList(routine)),
        ],
      ),
    );
  }

  /// Large, prominent "Start" button in the bottom bar — unlike the old FAB, it
  /// does not collide with the "Add exercise" tile.
  Widget _startBar(SportRoutine routine) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: 64,
        child: FilledButton.icon(
          icon: const Icon(Icons.play_arrow_rounded, size: 34),
          label: LocaleText(
            'sport.routines.start',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorkoutRunnerPage(routine: routine),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemsList(SportRoutine routine) {
    final addTile = SportAddTile(
      labelKey: 'sport.routines.add_exercise',
      onTap: _addExercise,
    );
    if (routine.items.isEmpty) {
      return ListView(
        physics: _bouncy,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Center(child: LocaleText('sport.routines.no_items')),
          const SizedBox(height: 20),
          addTile,
        ],
      );
    }
    return ReorderableListView(
      physics: _bouncy,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      footer: Padding(padding: const EdgeInsets.only(top: 2), child: addTile),
      onReorderItem: (oldIndex, newIndex) =>
          _training.reorderRoutineItems(routine.id, oldIndex, newIndex),
      children: [
        for (var index = 0; index < routine.items.length; index++)
          _itemRow(routine, index),
      ],
    );
  }

  static const _bouncy = BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  Widget _itemRow(SportRoutine routine, int index) {
    final item = routine.items[index];
    final exercise = _training.exerciseById(item.exerciseId);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        leading: const Icon(Icons.drag_handle),
        title: Text(
          exercise?.name ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_summary(item, exercise)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => confirmDelete(
            context,
            messageKey: 'sport.routines.item_delete_confirm',
            onConfirm: () => _training.removeRoutineItem(routine.id, index),
          ),
        ),
        onTap: () => showRoutineItemEditorSheet(
          context,
          routineId: routine.id,
          index: index,
        ),
      ),
    );
  }

  String _summary(RoutineItem item, SportExercise? exercise) {
    final timed = exercise?.kind == ExerciseKind.timed;
    final core = '${item.targetSets} × ${item.target}${timed ? ' s' : ''}';
    final weight = exercise?.kind == ExerciseKind.weighted
        ? ' · ${sportDecimal(item.targetWeight, 1)} kg'
        : '';
    return '$core$weight · ${item.restSeconds}s';
  }
}
