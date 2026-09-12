import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/workout_progress_ring.dart';
import 'package:insulink/src/sport/logbook/workout_summary.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// End-of-workout headline: one overall training value — each exercise's change
/// versus the previous session of the same routine, averaged so every exercise
/// counts the same — as a big progress ring, with the concrete figures
/// (exercises, sets, duration) small beneath it.
/// Reused on the finish screen and the logbook detail page. Reads the
/// predecessor from [TrainingState] (watched, so an in-place logbook edit
/// recomputes it).
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final training = context.watch<TrainingState>();
    final current = WorkoutSummary(session);
    final previousSession = training.previousSessionOf(session);
    final ratio = previousSession == null
        ? null
        : effortRatioVsPrevious(session, previousSession);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _ring(context, scheme, ratio),
          const SizedBox(height: 24),
          _concreteStats(context, scheme, current),
        ],
      ),
    );
  }

  /// The overall training value: [ratio] is the per-exercise change vs the
  /// previous session (see [effortRatioVsPrevious]), filling the ring by how it
  /// compares with last time. Shows the "first time" note only when there is
  /// genuinely nothing to compare against, never merely because a routine
  /// carries no weights.
  Widget _ring(BuildContext context, ColorScheme scheme, double? ratio) {
    if (ratio == null) {
      return WorkoutProgressRing(
        fraction: 1,
        color: context.accent,
        child: _ringCenter(
          context,
          scheme,
          icon: PhosphorIconsFill.flagCheckered,
          label: 'sport.summary.first_time',
        ),
      );
    }
    final percent = ((ratio - 1) * 100).round();
    final color = percent == 0
        ? scheme.onSurface.withValues(alpha: 0.6)
        : percent > 0
        ? context.positive
        : context.danger;
    return WorkoutProgressRing(
      fraction: ratio,
      color: color,
      child: _ringCenter(
        context,
        scheme,
        value:
            '${percent > 0
                ? '+'
                : percent < 0
                ? '−'
                : '±'}${percent.abs()} %',
        valueColor: color,
        label: 'sport.summary.vs_previous',
      ),
    );
  }

  Widget _ringCenter(
    BuildContext context,
    ColorScheme scheme, {
    String? value,
    Color? valueColor,
    IconData? icon,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 34, color: context.accent)
        else
          Text(
            value!,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        const SizedBox(height: 4),
        SizedBox(
          width: 96,
          child: Text(
            Locales.string(context, label),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.15,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  /// The concrete figures under the headline: exercises, sets, duration.
  Widget _concreteStats(
    BuildContext context,
    ColorScheme scheme,
    WorkoutSummary current,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stat(
          context,
          scheme,
          'sport.summary.exercises',
          sportInt(current.exercises),
        ),
        _stat(context, scheme, 'sport.routines.sets', sportInt(current.sets)),
        _stat(
          context,
          scheme,
          'sport.logbook.duration',
          sportClock(current.durationSecs),
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    ColorScheme scheme,
    String labelKey,
    String value,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          Locales.string(context, labelKey),
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
