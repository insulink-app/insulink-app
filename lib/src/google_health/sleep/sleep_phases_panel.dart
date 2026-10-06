import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep/sleep_stage_style.dart';
import 'package:insulink/src/google_health/sleep_hypnogram.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The night's phases in one panel: the hypnogram on top (when the night
/// carries a timeline), and under a line one row per stage with its colour,
/// its share of the night as a bar, and its length.
class SleepPhasesPanel extends StatelessWidget {
  const SleepPhasesPanel({
    super.key,
    required this.stages,
    required this.timeline,
  });

  final SleepStages stages;
  final List<SleepSegment>? timeline;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final phases = timeline;
    final rows = [
      for (final stage in sleepStageListOrder)
        if (stage.minutesIn(stages) > 0) stage,
    ];
    final total = rows.fold<int>(
      0,
      (sum, stage) => sum + stage.minutesIn(stages),
    );
    return InkPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phases != null && phases.isNotEmpty) ...[
            _hypnogram(context, colors, phases),
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: colors.line),
            const SizedBox(height: 12),
          ],
          for (final stage in rows) _row(context, colors, stage, total),
        ],
      ),
    );
  }

  Widget _hypnogram(
    BuildContext context,
    InsulinkColors colors,
    List<SleepSegment> phases,
  ) {
    return SleepHypnogram(
      segments: phases,
      colors: {
        for (final stage in SleepStage.values) stage: stage.colorIn(colors),
      },
      labels: {
        for (final stage in SleepStage.values)
          stage: Locales.string(context, stage.shortKey),
      },
      axisColor: colors.muted,
      lineColor: colors.panelRaised,
    );
  }

  Widget _row(
    BuildContext context,
    InsulinkColors colors,
    SleepStage stage,
    int total,
  ) {
    final minutes = stage.minutesIn(stages);
    final color = stage.colorIn(colors);
    return SizedBox(
      height: 36,
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: 112,
            child: Row(
              spacing: 9,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Flexible(
                  child: Text(
                    Locales.string(context, stage.nameKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: InkText.body.copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _share(colors, color, minutes / total)),
          SizedBox(
            width: 92,
            child: Text(
              formatSleepDuration(minutes),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.end,
              style: InkText.row,
            ),
          ),
        ],
      ),
    );
  }

  /// The stage's share of the night on a 6 px track.
  Widget _share(InsulinkColors colors, Color color, double share) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: colors.line,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: share.clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
