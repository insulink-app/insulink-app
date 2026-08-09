import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/sport_add_tile.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A free workout before its first exercise is picked: the clock already runs
/// (the workout has started), there is just nothing to perform yet.
class WorkoutEmptyView extends StatelessWidget {
  const WorkoutEmptyView({
    super.key,
    required this.onAdd,
    required this.onFinish,
  });

  final VoidCallback onAdd;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsBold.barbell,
            size: 48,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          LocaleText(
            'sport.workout.no_exercise',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),
          SportAddTile(labelKey: 'sport.workout.add_exercise', onTap: onAdd),
          TextButton(
            onPressed: onFinish,
            child: LocaleText('sport.workout.finish'),
          ),
        ],
      ),
    );
  }
}
