import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/workout_summary_page.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_exercise_view.dart';
import 'package:insulink/src/sport/workout/workout_rest_view.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/sport/workout/workout_snapshot.dart';
import 'package:insulink/src/sport/workout/workout_vitals_bar.dart';
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
  late final WorkoutRunner _runner;

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
    // This device drives the workout for as long as this page is up: the
    // account's copy is only watched for the workout ENDING elsewhere, never
    // applied over the set in progress.
    training.driveActiveWorkout(true);
    training.addListener(_onTrainingChanged);
    _runner =
        WorkoutRunner(
            widget.routine,
            training.exercises,
            resume: widget.resume,
            findLastSet: training.lastSetFor,
            onPersist: (snapshot) => snapshot == null
                ? training.clearActiveWorkout()
                : training.saveActiveWorkout(snapshot),
          )
          ..onFinished = (session) {
            training.addSession(session);
            if (!mounted) {
              return;
            }
            // Swap the runner for the summary so "back" from it lands on the
            // sport page, not a finished workout. A workout ended with nothing
            // logged has nothing to summarise — just close.
            final navigator = Navigator.of(context);
            if (session.sets.isEmpty) {
              navigator.pop();
            } else {
              navigator.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => WorkoutSummaryPage(session: session),
                ),
              );
            }
          };
  }

  /// The workout was ended somewhere else (the web panel, another phone). Say so
  /// and close — carrying on would log a session the user already finished.
  ///
  /// Closes first and tells afterwards, against the navigator's own context: the
  /// alert is itself a route, so popping while it is up would only dismiss the
  /// alert and leave the runner sitting on a workout that no longer exists.
  void _onTrainingChanged() {
    final training = context.read<TrainingState>();
    if (!mounted || !training.endedElsewhere) {
      return;
    }
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
              const WorkoutVitalsBar(),
              Expanded(
                child: _runner.phase == WorkoutPhase.resting
                    ? WorkoutRestView(
                        runner: _runner,
                        onJump: _showJump,
                        onFinish: () => _confirmFinish(context),
                      )
                    : WorkoutExerciseView(
                        runner: _runner,
                        onJump: _showJump,
                        onFinish: () => _confirmFinish(context),
                      ),
              ),
            ],
          ),
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
      title: Text(widget.routine.name),
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
                '${_runner.isPaused ? ' · ${Locales.string(context, 'sport.workout.paused')}' : ''}',
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

  /// Bottom sheet to jump to any exercise in the routine.
  void _showJump() {
    final training = context.read<TrainingState>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var index = 0; index < widget.routine.items.length; index++)
              ListTile(
                leading: index == _runner.exerciseIndex
                    ? const Icon(PhosphorIconsFill.play)
                    : const SizedBox(width: 24),
                title: Text(
                  training
                          .exerciseById(widget.routine.items[index].exerciseId)
                          ?.name ??
                      '—',
                ),
                onTap: () {
                  _runner.jumpTo(index);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
