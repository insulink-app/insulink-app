import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:provider/provider.dart';

/// Detail view of a training: the route as a framed map window plus stat tiles
/// (distance, duration, average speed) and the start/end times.
class CardioDetailPage extends StatelessWidget {
  const CardioDetailPage({super.key, required this.training});

  final CardioTraining training;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(training.type.labelKey),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.trainings.delete_confirm',
              onConfirm: () {
                context.read<CardioTrainingState>().removeTraining(training.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _mapWindow(context),
          const SizedBox(height: 20),
          _tiles(context),
          const SizedBox(height: 12),
          _times(context),
        ],
      ),
    );
  }

  Widget _mapWindow(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 500,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
        ),
        child: training.track.length >= 2
            ? CardioMap(points: training.track)
            : Center(child: LocaleText('sport.trainings.no_route')),
      ),
    );
  }

  Widget _tiles(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            context,
            Icons.straighten_rounded,
            'sport.trainings.distance',
            formatDistanceKm(training.distanceM),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(
            context,
            Icons.timer_outlined,
            'sport.trainings.duration',
            formatDuration(training.duration),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tile(
            context,
            Icons.speed_rounded,
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
          Icon(icon, color: scheme.primary, size: 22),
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
