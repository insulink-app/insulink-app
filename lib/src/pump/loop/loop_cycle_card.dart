import 'package:flutter/material.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/loop/loop_cycle_badge.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// One decision the automation made: what it did, what it was looking at, and
/// what held it back.
///
/// Leads with the direction against the user's schedule ([PodLoopCycleBadge]),
/// then the rate and the reason, then what it was computed from, then only what
/// is wrong: a ceiling that cut it short, or a cycle that never reached the pod.
class PodLoopCycleCard extends StatelessWidget {
  const PodLoopCycleCard({super.key, required this.cycle});

  final PodLoopCycle cycle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = _note(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PodLoopCycleBadge(cycle: cycle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headline(context, scheme),
                const SizedBox(height: 3),
                Text(
                  _inputs(context),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: TextStyle(fontSize: 12, color: context.warning),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The rate and why, with the clock at the far end so the times line up down
  /// the list instead of being buried in a sentence.
  Widget _headline(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        Text(
          '${cycle.unitsPerHour.toStringAsFixed(2)} U/h',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            Locales.string(
              context,
              'pump.loop.reason.${cycle.reason.localeKey}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_two(cycle.at.hour)}:${_two(cycle.at.minute)}',
          style: TextStyle(
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// What the decision was computed from. Without these the rate is a number
  /// nobody can check.
  String _inputs(BuildContext context) {
    return [
      if (cycle.mgdl != null)
        Locales.string(context, 'pump.loop.at_glucose')
            .replaceFirst('#', '${cycle.mgdl}')
            .replaceFirst('#', _trend()),
      Locales.string(context, 'pump.loop.on_board')
          .replaceFirst('#', cycle.iobUnits.toStringAsFixed(2)),
      Locales.string(context, 'pump.loop.schedule_was')
          .replaceFirst('#', cycle.scheduledUnitsPerHour.toStringAsFixed(2)),
    ].join(' · ');
  }

  /// The two things that mean the rate is not the whole story: a ceiling that
  /// cut it short, and a cycle that never reached the pod. Observation mode and
  /// a failed command both land in the second, and neither may look like a
  /// delivery.
  String? _note(BuildContext context) {
    final parts = <String>[
      if (!cycle.delivered) Locales.string(context, 'pump.loop.not_sent'),
      if (cycle.boundBy != null)
        Locales.string(
          context,
          'pump.loop.bound.${cycle.boundBy!.localeKey}',
        ),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _trend() {
    final trend = cycle.trendPerMinute;
    if (trend == null) {
      return '0.0';
    }
    return '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
