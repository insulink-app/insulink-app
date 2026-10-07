import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/ink_panel.dart';
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
/// (exercises, sets, duration) as rows beside it, all in one panel.
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
    return InkPanel(
      radius: InkRadius.tile,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        spacing: 24,
        children: [
          _ring(context, scheme, ratio),
          Expanded(child: _concreteStats(context, scheme, current)),
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
        ? context.ink.muted
        : percent > 0
        ? context.ink.range
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
            style: InkText.bigValue.copyWith(fontSize: 26, color: valueColor),
          ),
        const SizedBox(height: 4),
        SizedBox(
          width: 96,
          child: Text(
            Locales.string(context, label),
            textAlign: TextAlign.center,
            style: InkText.caption.copyWith(color: context.ink.muted),
          ),
        ),
      ],
    );
  }

  /// The concrete figures beside the ring: exercises, sets, duration, as
  /// label / value rows parted by thin lines.
  Widget _concreteStats(
    BuildContext context,
    ColorScheme scheme,
    WorkoutSummary current,
  ) {
    final rows = [
      _stat(context, 'sport.summary.exercises', sportInt(current.exercises)),
      _stat(context, 'sport.routines.sets', sportInt(current.sets)),
      _stat(
        context,
        'sport.logbook.duration',
        sportClock(current.durationSecs),
      ),
    ];
    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            Divider(height: 1, thickness: 1, color: context.ink.line),
          rows[index],
        ],
      ],
    );
  }

  Widget _stat(BuildContext context, String labelKey, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              Locales.string(context, labelKey),
              style: InkText.body.copyWith(
                fontWeight: FontWeight.w400,
                color: context.ink.muted,
              ),
            ),
          ),
          Text(value, style: InkText.bigValue.copyWith(fontSize: 20)),
        ],
      ),
    );
  }
}
