import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/sleep/sleep_index_ring.dart';
import 'package:insulink/src/google_health/sleep/sleep_phase_strip.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The night at a glance: how long it was, against the average, its sleep
/// index as a ring, and underneath the night's phases in the order they came,
/// from falling asleep to waking up.
class SleepHeroCard extends StatelessWidget {
  const SleepHeroCard({
    super.key,
    required this.minutes,
    required this.averageMinutes,
    required this.index,
    required this.timeline,
  });

  final int minutes;
  final int averageMinutes;

  /// Null when the night carries no stage totals to compute it from.
  final int? index;

  /// Null or empty when the night carries no stage timeline; the strip and the
  /// two times are left out then rather than guessed.
  final List<SleepSegment>? timeline;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final phases = timeline;
    return InkPanel(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(child: _duration(context, colors)),
              if (index != null) SleepIndexRing(index: index!),
            ],
          ),
          if (phases != null && phases.isNotEmpty) ...[
            const SizedBox(height: 20),
            SleepPhaseStrip(segments: phases),
          ],
        ],
      ),
    );
  }

  Widget _duration(BuildContext context, InsulinkColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Locales.string(context, 'google_health.sleep_page.slept'),
          style: InkText.label.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(_durationSpan(colors)),
        ),
        const SizedBox(height: 8),
        Text(
          Locales.string(
            context,
            'google_health.sleep_page.average_per_night',
            params: [formatSleepDuration(averageMinutes)],
          ),
          style: InkText.caption.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  /// "7 h 53 min" with the numbers large and the units small and muted.
  TextSpan _durationSpan(InsulinkColors colors) {
    final number = InkText.bigValue.copyWith(
      fontSize: 50,
      letterSpacing: -2,
      color: colors.text,
    );
    final unit = InkText.row.copyWith(fontSize: 18, color: colors.muted);
    return TextSpan(
      children: [
        if (minutes >= 60) ...[
          TextSpan(text: '${minutes ~/ 60}', style: number),
          TextSpan(text: ' h  ', style: unit),
        ],
        TextSpan(text: '${minutes % 60}', style: number),
        TextSpan(text: ' min', style: unit),
      ],
    );
  }
}
