import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The stat tiles (distance / duration / average speed) and the start/end times
/// of a completed training — the numeric summary under the route map.
class TrainingStatsPanel extends StatelessWidget {
  const TrainingStatsPanel({super.key, required this.training});

  final CardioTraining training;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [_tiles(context), const SizedBox(height: 12), _times(context)],
    );
  }

  Widget _tiles(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            context,
            PhosphorIconsBold.ruler,
            'sport.trainings.distance',
            formatDistanceKm(training.distanceM),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(
            context,
            PhosphorIconsBold.timer,
            'sport.trainings.duration',
            formatDuration(training.duration),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(
            context,
            PhosphorIconsBold.gauge,
            'sport.trainings.avg_speed',
            formatSpeed(training.avgSpeedKmh),
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String labelKey,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            Locales.string(context, labelKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _times(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final start = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(training.endMs);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _timeRow(context, 'sport.trainings.start', locale, start),
          Divider(color: scheme.onSurface.withValues(alpha: 0.08), height: 1),
          _timeRow(context, 'sport.trainings.end', locale, end),
        ],
      ),
    );
  }

  Widget _timeRow(
    BuildContext context,
    String labelKey,
    MaterialLocalizations locale,
    DateTime time,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            Locales.string(context, labelKey),
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          Text(
            '${locale.formatMediumDate(time)} · '
            '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(time))}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
