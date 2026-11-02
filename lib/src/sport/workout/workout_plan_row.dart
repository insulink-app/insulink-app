import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/workout/workout_runner.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Plans ahead while a set runs: how many sets the current exercise gets, and
/// an exercise queued up behind it. Both change this session only.
class WorkoutPlanRow extends StatelessWidget {
  const WorkoutPlanRow({super.key, required this.runner, required this.onAdd});

  final WorkoutRunner runner;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _setsStepper(context),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(PhosphorIconsBold.plus),
          label: LocaleText('sport.workout.queue_exercise'),
        ),
      ],
    );
  }

  Widget _setsStepper(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _step(context, PhosphorIconsBold.minus, 'sets_down', -1),
        SizedBox(
          width: 120,
          child: Text(
            Locales.string(
              context,
              'sport.workout.planned_sets',
              params: ['${runner.totalSets}'],
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        _step(context, PhosphorIconsBold.plus, 'sets_up', 1),
      ],
    );
  }

  Widget _step(BuildContext context, IconData icon, String key, int delta) {
    return Semantics(
      button: true,
      label: Locales.string(context, 'sport.workout.$key'),
      child: CircleIconButton(
        icon: icon,
        accent: context.ink.accent,
        onTap: () => runner.changeTargetSets(delta),
      ),
    );
  }
}
