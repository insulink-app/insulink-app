import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:provider/provider.dart';

/// Live-Durchführung einer Routine: Stoppuhr je Satz, Eingaben und der
/// Pausen-Countdown. Treibt einen [WorkoutRunner] und speichert die Session.
class WorkoutRunnerPage extends StatefulWidget {
  const WorkoutRunnerPage({super.key, required this.routine});

  final SportRoutine routine;

  @override
  State<WorkoutRunnerPage> createState() => _WorkoutRunnerPageState();
}

class _WorkoutRunnerPageState extends State<WorkoutRunnerPage> {
  late final WorkoutRunner _runner;
  final AudioPlayer _player = AudioPlayer(playerId: 'insulink_rest');

  @override
  void initState() {
    super.initState();
    final training = context.read<TrainingState>();
    _runner = WorkoutRunner(widget.routine, training.exercises)
      ..onRestFinished = _chime
      ..onFinished = (session) {
        training.addSession(session);
        if (mounted) {
          Navigator.of(context).pop();
        }
      };
  }

  Future<void> _chime() async {
    try {
      await _player.play(
        AssetSource('sounds/alarm_low.wav'),
        ctx: AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
    } catch (_) {
      // ponytail: Ton ist best-effort; der Countdown läuft auch ohne weiter.
    }
  }

  @override
  void dispose() {
    _runner.dispose();
    _player.dispose();
    super.dispose();
  }

  static String _clock(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(widget.routine.name),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _runner,
          builder: (context, _) => _runner.phase == WorkoutPhase.resting
              ? _resting(context)
              : _exercising(context),
        ),
      ),
    );
  }

  Widget _exercising(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${Locales.string(context, 'sport.workout.exercise')} '
            '${_runner.exerciseIndex + 1}/${_runner.totalExercises}  ·  '
            '${Locales.string(context, 'sport.workout.set')} '
            '${_runner.setNumber}/${_runner.totalSets}',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Text(
            _runner.currentExercise?.name ?? '—',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            _clock(_runner.elapsed),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_runner.isTimed)
            Text(
              Locales.string(context, 'sport.workout.target_time', params: ['${_runner.currentItem.target}']),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
            )
          else
            _repWeightControls(context),
          const Spacer(),
          FilledButton(
            onPressed: _runner.completeSet,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: LocaleText('sport.workout.complete_set'),
          ),
          TextButton(
            onPressed: _runner.finishEarly,
            child: LocaleText('sport.workout.finish'),
          ),
        ],
      ),
    );
  }

  Widget _repWeightControls(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        _stepperRow(
          'sport.routines.reps',
          '${_runner.currentReps}',
          accent,
          () => _runner.adjustReps(-1),
          () => _runner.adjustReps(1),
        ),
        if (_runner.isWeighted) ...[
          const SizedBox(height: 12),
          _stepperRow(
            'sport.routines.weight',
            '${_runner.currentWeight.toStringAsFixed(1)} kg',
            accent,
            () => _runner.adjustWeight(-2.5),
            () => _runner.adjustWeight(2.5),
          ),
        ],
      ],
    );
  }

  Widget _stepperRow(String labelKey, String value, Color accent, VoidCallback minus, VoidCallback plus) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleIconButton(icon: Icons.remove, accent: accent, onTap: minus),
        SizedBox(
          width: 120,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        CircleIconButton(icon: Icons.add, accent: accent, onTap: plus),
      ],
    );
  }

  Widget _resting(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          LocaleText(
            'sport.workout.rest',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          Text(
            _clock(_runner.restRemaining),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: scheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            '${Locales.string(context, 'sport.workout.next')} '
            '${_runner.currentExercise?.name ?? '—'}  ·  '
            '${Locales.string(context, 'sport.workout.set')} '
            '${_runner.setNumber}/${_runner.totalSets}',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _runner.skipRest,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: LocaleText('sport.workout.skip_rest'),
          ),
        ],
      ),
    );
  }
}
