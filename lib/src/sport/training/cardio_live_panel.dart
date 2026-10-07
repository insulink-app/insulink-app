import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/sport_vitals_bar.dart';
import 'package:insulink/src/sport/training/cardio_metric.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The sheet at the foot of a live training (screen 30): glucose and pulse as
/// two chips, duration / distance / speed large and parted by thin lines, and
/// "Training beenden" as the soft danger button. Presentation only; the page
/// owns the values and what the button does.
class CardioLivePanel extends StatelessWidget {
  const CardioLivePanel({
    super.key,
    required this.duration,
    required this.distance,
    required this.speed,
    required this.paused,
    required this.onStop,
  });

  /// Formatted as the training's own formatters write them ("2,32 km"); the
  /// unit after the space is drawn smaller.
  final String duration, distance, speed;
  final bool paused;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        0,
        InkSpace.panelMargin,
        16,
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SportVitalsBar.chips(),
          const SizedBox(height: 18),
          _metrics(context, colors),
          if (paused) ...[
            const SizedBox(height: 8),
            LocaleText(
              'sport.trainings.paused',
              textAlign: TextAlign.center,
              style: InkText.label.copyWith(color: colors.muted),
            ),
          ],
          const SizedBox(height: 18),
          DangerActionButton(
            labelKey: 'sport.trainings.stop',
            icon: PhosphorIconsFill.stop,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }

  Widget _metrics(BuildContext context, InsulinkColors colors) {
    return CardioMetricRow(
      metrics: [
        CardioMetric(formatted: duration, labelKey: 'sport.trainings.duration'),
        CardioMetric(formatted: distance, labelKey: 'sport.trainings.distance'),
        CardioMetric(formatted: speed, labelKey: 'sport.trainings.speed'),
      ],
    );
  }
}
