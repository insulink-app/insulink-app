import 'package:flutter/material.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A cycle's rate against the user's own basal schedule, as one glyph.
///
/// This is the question a reader scrolling a day of decisions actually has: was
/// the automation adding insulin, holding the schedule, or backing off. A column
/// of rates in U/h all look alike, and which of them counts as high depends on a
/// schedule that changes through the day, so the comparison is done here rather
/// than left to the reader.
///
/// Neutral-faced like every other identity badge in the app. The colour that
/// matters sits on the note under the row, which is the part worth acting on.
class PodLoopCycleBadge extends StatelessWidget {
  const PodLoopCycleBadge({super.key, required this.cycle});

  final PodLoopCycle cycle;

  /// Below this the rate counts as the schedule itself. Rates are stored to
  /// hundredths, so anything smaller is a rounding artefact, not a decision.
  static const double sameRate = 0.005;

  /// Up, down, or level against the schedule.
  @visibleForTesting
  static IconData iconFor(double unitsPerHour, double scheduledUnitsPerHour) {
    final difference = unitsPerHour - scheduledUnitsPerHour;
    if (difference > sameRate) {
      return PhosphorIconsBold.arrowUp;
    }
    if (difference < -sameRate) {
      return PhosphorIconsBold.arrowDown;
    }
    return PhosphorIconsBold.equals;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconFor(cycle.unitsPerHour, cycle.scheduledUnitsPerHour),
        size: 16,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
