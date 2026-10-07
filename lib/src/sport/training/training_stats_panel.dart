import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_metric.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The numeric summary under the route map (screen 29): the day on the left
/// and the clock span on the right, then distance, duration and average
/// speed in one panel, parted by lines, with muted glyphs.
class TrainingStatsPanel extends StatelessWidget {
  const TrainingStatsPanel({super.key, required this.training});

  final CardioTraining training;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _when(context),
        const SizedBox(height: 14),
        InkPanel(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: CardioMetricRow(
            metrics: [
              CardioMetric(
                icon: PhosphorIconsBold.ruler,
                formatted: formatDistanceKm(training.distanceM),
                labelKey: 'sport.trainings.distance',
                size: 26,
              ),
              CardioMetric(
                icon: PhosphorIconsBold.timer,
                formatted: formatDuration(training.duration),
                labelKey: 'sport.trainings.duration',
                size: 26,
              ),
              CardioMetric(
                icon: PhosphorIconsBold.gauge,
                formatted: formatSpeed(training.avgSpeedKmh),
                labelKey: 'sport.trainings.avg_speed',
                size: 26,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The day as the lists name it, and the clock span in bold ("16:21 bis
  /// 16:40": the design's dash is no punctuation the app's strings use).
  Widget _when(BuildContext context) {
    final colors = context.ink;
    final locale = MaterialLocalizations.of(context);
    final start = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(training.endMs);
    String clock(DateTime time) => locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              RelativeDay(start).label(context),
              style: InkText.label.copyWith(fontSize: 15, color: colors.muted),
            ),
          ),
          Text(
            Locales.string(
              context,
              'connections.history.range',
              params: [clock(start), clock(end)],
            ),
            style: InkText.row.copyWith(color: colors.text),
          ),
        ],
      ),
    );
  }
}
