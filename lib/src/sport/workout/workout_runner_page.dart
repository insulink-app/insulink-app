import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/exercises/exercises_page.dart';
import 'package:insulink/src/sport/logbook/workout_summary_page.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_empty_view.dart';
import 'package:insulink/src/sport/workout/workout_exercise_view.dart';
import 'package:insulink/src/sport/workout/workout_rest_view.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';
import 'package:insulink/src/sport/sport_vitals_bar.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Live execution of a routine: total time, progress, pause, per-set stopwatch
/// and the rest countdown. Drives a [WorkoutRunner], persists a resumable
/// snapshot and saves the finished session. Opens fresh or [resume]s a snapshot.
class WorkoutRunnerPage extends StatefulWidget {
  const WorkoutRunnerPage({super.key, required this.routine, this.resume});

  final SportRoutine routine;
  final WorkoutSnapshot? resume;

  @override
  State<WorkoutRunnerPage> createState() => _WorkoutRunnerPageState();
}

class _WorkoutRunnerPageState extends State<WorkoutRunnerPage> {
  late WorkoutRunner _runner;

  /// The snapshot this page's runner is showing, compared by IDENTITY against
  /// the shared state. The runner's own saves put THIS object there, so anything
  /// else sitting in `activeWorkout` was written by another device and has to be
  /// adopted. A counter of adoptions cannot say that: it is consumed whether or
  /// not the snapshot behind it was applied, and a signal dropped once is a
  /// screen that never catches up again.
  WorkoutSnapshot? _shown;

  /// The routine the runner is on. Follows the driver's embedded copy when a
  /// snapshot is adopted, so the jump sheet and the pointers agree with it.
  late SportRoutine _routine;

  @override
  void initState() {
    super.initState();
    // Keep the screen on during the workout (timer/rests stay readable).
    WakelockPlus.enable();
    // Make sure the foreground service is up for the whole workout, even one
    // opened straight from the web panel without visiting the Sport page: it is
    // what relays live bpm to the panel while the app is backgrounded or the
    // screen is off (see CgmTaskHandler._maybePollHeartRate). Idempotent, and a
    // no-op when a CGM sensor already runs the service.
    context.read<CgmController>().ensureDetectionService();
    final training = context.read<TrainingState>();
    // This page shows the workout; it does not own it. The account's copy is
    // adopted while it is up, so a set logged in the panel appears here too.
    training.driveActiveWorkout(true);
    training.addListener(_onTrainingChanged);
    _shown = widget.resume;
    _routine = widget.routine;
    _runner = _buildRunner(widget.resume);
  }

  /// A runner over [resume] (null starts a fresh workout), wired to persist into
  /// the shared state and to hand its finished session to the summary.
  WorkoutRunner _buildRunner(WorkoutSnapshot? resume) {
    final training = context.read<TrainingState>();
    return WorkoutRunner(
      _routine,
      training.exercises,
      resume: resume,
      findLastSet: training.lastSetFor,
      onPersist: _onPersist,
    )..onFinished = _onFinished;
  }

  /// The runner moved: remember what it published — that is what this page is
  /// showing — and hand it to the shared state. A null snapshot ends the workout.
  void _onPersist(WorkoutSnapshot? snapshot) {
    _shown = snapshot;
    final training = context.read<TrainingState>();
    if (snapshot == null) {
      training.clearActiveWorkout();
      return;
    }
    training.saveActiveWorkout(snapshot);
  }

  /// Swaps the runner for the summary so "back" from it lands on the sport page,
  /// not a finished workout. A workout ended with nothing logged has nothing to
  /// summarise — just close.
  void _onFinished(WorkoutSession session) {
    context.read<TrainingState>().addSession(session);
    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    if (session.sets.isEmpty) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryPage(session: session),
      ),
    );
  }

  /// The shared workout changed: it was either ended somewhere else, or moved on
  /// by the device that is driving it.
  void _onTrainingChanged() {
    if (!mounted) {
      return;
    }
    final training = context.read<TrainingState>();
    if (training.endedElsewhere) {
      _closeEndedElsewhere(training);
      return;
    }
    if (!identical(training.activeWorkout, _shown)) {
      _adoptRemote(training);
    }
  }

  /// Another device moved the workout on. Rebuild the runner from its snapshot —
  /// the same path a resume takes — so this screen shows the set that device is
  /// on instead of ticking on state only this one still believes in.
  void _adoptRemote(TrainingState training) {
    final snapshot = training.activeWorkout;
    if (snapshot == null) {
      return;
    }
    _shown = snapshot;
    final replaced = _runner;
    setState(() {
      _routine = training.routineForSnapshot(snapshot) ?? widget.routine;
      _runner = _buildRunner(snapshot);
    });
    replaced.dispose();
  }

  /// The workout was ended somewhere else (the web panel, another phone). Say so
  /// and close — carrying on would log a session the user already finished.
  ///
  /// Closes first and tells afterwards, against the navigator's own context: the
  /// alert is itself a route, so popping while it is up would only dismiss the
  /// alert and leave the runner sitting on a workout that no longer exists.
  void _closeEndedElsewhere(TrainingState training) {
    training.acknowledgeEndedElsewhere();
    final navigator = Navigator.of(context);
    final iconColor = Theme.of(context).colorScheme.primary;
    navigator.pop();
    Alert(
      icon: PhosphorIconsFill.flag,
      iconColor: iconColor,
      description: 'sport.workout.ended_elsewhere',
      confirmButtonText: 'sport.workout.ended_elsewhere_confirm',
    ).show(navigator.context);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    context.read<TrainingState>()
      ..removeListener(_onTrainingChanged)
      ..driveActiveWorkout(false);
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _runner,
      builder: (context, _) => Scaffold(
        appBar: _appBar(context),
        body: SafeArea(
          child: Column(
            children: [
              const SportVitalsBar(),
              Expanded(child: _phaseView(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// The view for what the workout is doing right now: performing a set, resting
  /// between two, or — a free workout before its first pick — waiting for an
  /// exercise to be chosen.
  Widget _phaseView(BuildContext context) {
    if (!_runner.hasExercises) {
      return WorkoutEmptyView(
        onAdd: _addExercise,
        onFinish: () => _confirmFinish(context),
      );
    }
    if (_runner.phase == WorkoutPhase.resting) {
      return WorkoutRestView(
        runner: _runner,
        onJump: _showJump,
        onAdd: _addExercise,
        onFinish: () => _confirmFinish(context),
      );
    }
    return WorkoutExerciseView(
      runner: _runner,
      onJump: _showJump,
      onFinish: () => _confirmFinish(context),
    );
  }

  /// Pick an exercise for the running workout. It joins THIS session only — the
  /// stored routine is left as it is, so a spontaneous extra exercise does not
  /// rewrite the plan for next time.
  void _addExercise() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExercisesPage(
          onPick: (exercise) => _runner.addExercise(exercise.id),
        ),
      ),
    );
  }

  /// Confirm before ending the workout — leaving otherwise loses the remaining
  /// sets. Reachable from both the exercising and resting phases.
  void _confirmFinish(BuildContext context) {
    Alert(
      icon: PhosphorIconsFill.flag,
      iconColor: Theme.of(context).colorScheme.primary,
      description: 'sport.workout.finish_confirm',
      cancelButton: true,
      confirmButtonText: 'sport.workout.finish',
      callback: _runner.finishEarly,
    ).show(context);
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      surfaceTintColor: Colors.transparent,
      title: Text(_runner.routine.name),
      actions: [
        IconButton(
          icon: Icon(
            _runner.isPaused
                ? PhosphorIconsFill.play
                : PhosphorIconsBold.pause,
          ),
          tooltip: Locales.string(
            context,
            _runner.isPaused ? 'sport.workout.resume' : 'sport.workout.pause',
          ),
          onPressed: () =>
              _runner.isPaused ? _runner.resume() : _runner.pause(),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(28),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${Locales.string(context, 'sport.workout.total')} '
                '${formatDuration(_runner.sessionElapsed)}'
                '${_runner.isPaused ? ' · ${Locales.string(context, 'sport.workout.paused')}' : ''}'
                '${_expectedEnd(context)}',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            LinearProgressIndicator(
              value: _runner.progress,
              minHeight: 4,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }

  /// " · ends ~18:45" for a workout that can be predicted, empty for one that
  /// cannot (a free workout has no plan to run out of).
  String _expectedEnd(BuildContext context) {
    final end = _runner.expectedEnd;
    if (end == null) {
      return '';
    }
    final clock = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(end));
    return ' · ${Locales.string(context, 'sport.workout.eta', params: [clock])}';
  }

  /// Bottom sheet to jump to any exercise of the running workout, or to add one
  /// to it on the spot.
  void _showJump() {
    final training = context.read<TrainingState>();
    final items = _runner.routine.items;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var index = 0; index < items.length; index++)
              ListTile(
                leading: index == _runner.exerciseIndex
                    ? const Icon(PhosphorIconsFill.play)
                    : const SizedBox(width: 24),
                title: Text(
                  training.exerciseById(items[index].exerciseId)?.name ?? '—',
                ),
                onTap: () {
                  _runner.jumpTo(index);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              leading: const Icon(PhosphorIconsBold.plus),
              title: LocaleText('sport.workout.add_exercise'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addExercise();
              },
            ),
          ],
        ),
      ),
    );
  }
}
