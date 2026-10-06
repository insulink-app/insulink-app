import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep/sleep_target_scale.dart';
import 'package:insulink/src/google_health/sleep_metrics.dart';
import 'package:insulink/src/google_health/sleep_targets_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The three figures the sleep index is read against (time to deep sleep, deep
/// sleep, interruptions), each on a scale with its target window, in one panel
/// with a small key for the window at its foot.
class SleepIndexPanel extends StatelessWidget {
  const SleepIndexPanel({
    super.key,
    required this.metrics,
    required this.targets,
  });

  final SleepMetrics metrics;
  final SleepTargets targets;

  @override
  Widget build(BuildContext context) {
    final timeToSolid = metrics.timeToSolidMinutes;
    return InkPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          SleepTargetScale(
            label: _label(context, 'time_to_solid'),
            valueText: timeToSolid == null
                ? '–'
                : formatSleepDuration(timeToSolid),
            value: timeToSolid,
            target: targets.timeToSolid,
          ),
          SleepTargetScale(
            label: _label(context, 'deep'),
            valueText: formatSleepDuration(metrics.deepMinutes),
            value: metrics.deepMinutes,
            target: targets.deep,
          ),
          SleepTargetScale(
            label: _label(context, 'interruption'),
            valueText: formatSleepDuration(metrics.interruptionMinutes),
            value: metrics.interruptionMinutes,
            target: targets.interruption,
          ),
          _key(context),
        ],
      ),
    );
  }

  String _label(BuildContext context, String key) =>
      Locales.string(context, 'google_health.sleep_stats.$key');

  Widget _key(BuildContext context) {
    final colors = context.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          spacing: 8,
          children: [
            Container(
              width: 18,
              height: 6,
              decoration: BoxDecoration(
                color: colors.range.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Text(
              Locales.string(context, 'google_health.sleep_page.target_range'),
              style: InkText.caption.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "all in target range" note beside the section title, shown only when it
/// is true.
class SleepAllInTargetHint extends StatelessWidget {
  const SleepAllInTargetHint({super.key});

  @override
  Widget build(BuildContext context) {
    final range = context.ink.range;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(PhosphorIconsBold.check, size: 14, color: range),
          Text(
            Locales.string(context, 'google_health.sleep_page.all_in_target'),
            style: InkText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: range,
            ),
          ),
        ],
      ),
    );
  }
}
