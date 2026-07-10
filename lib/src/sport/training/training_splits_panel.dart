import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training/km_splits.dart';

/// Per-kilometre pace list for a completed run/walk: one row per km with a bar
/// scaled to that km's pace relative to the run's fastest/slowest, so the
/// splits read at a glance. Hidden by the caller when there are no splits.
class TrainingSplitsPanel extends StatelessWidget {
  const TrainingSplitsPanel({super.key, required this.splits});

  final List<KmSplit> splits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paces = splits.map((split) => split.paceSecPerKm);
    final fastest = paces.reduce((a, b) => a < b ? a : b);
    final slowest = paces.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: LocaleText(
              'sport.trainings.splits',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          for (final split in splits)
            _row(context, scheme, split, _fraction(split, fastest, slowest)),
        ],
      ),
    );
  }

  /// Bar fill 0.35..1.0, longest for the fastest km (shortest pace). A single
  /// split (or an all-equal pace) fills fully.
  double _fraction(KmSplit split, double fastest, double slowest) {
    final span = slowest - fastest;
    if (span == 0) {
      return 1.0;
    }
    return 0.35 + 0.65 * (1 - (split.paceSecPerKm - fastest) / span);
  }

  Widget _row(
    BuildContext context,
    ColorScheme scheme,
    KmSplit split,
    double fraction,
  ) {
    final label = split.km < 1
        ? formatDistanceKm(split.km * 1000)
        : Locales.string(context, 'sport.trainings.km_label',
            params: ['${split.index}']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatPace(split.paceSecPerKm),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
