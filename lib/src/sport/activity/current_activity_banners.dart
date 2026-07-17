import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/training/cardio_recording_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/sport/workout/workout_runner_page.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/brand_tints.dart';

/// Resume banners shown at the top of the "Activities" list for anything still
/// in progress (a paused strength workout, a recording cardio training) so the
/// user can jump back in without relaunching the app. Collapses to nothing when
/// neither is running.
class CurrentActivityBanners extends StatelessWidget {
  const CurrentActivityBanners({super.key});

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final cardio = context.watch<CardioTrainingState>();
    final workout = training.activeWorkout;
    final routine = workout == null
        ? null
        : training.routineForSnapshot(workout);
    final active = cardio.activeTraining;
    if (routine == null && active == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (routine != null)
          _banner(
            context,
            PhosphorIconsBold.barbell,
            'sport.workout.resume_active',
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    WorkoutRunnerPage(routine: routine, resume: workout),
              ),
            ),
          ),
        if (active != null)
          _banner(
            context,
            active.type.icon,
            'sport.trainings.resume_active',
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CardioRecordingPage(resume: true),
              ),
            ),
          ),
      ],
    );
  }

  Widget _banner(
    BuildContext context,
    IconData icon,
    String labelKey,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: context.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: LocaleText(
                    labelKey,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.accent,
                    ),
                  ),
                ),
                Icon(PhosphorIconsFill.play, color: context.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
