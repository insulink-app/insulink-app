import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:provider/provider.dart';

/// Detail view of a training: route on the map plus start/end time, distance and
/// average speed.
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
      body: Column(
        children: [
          Expanded(
            child: training.track.length >= 2
                ? CardioMap(points: training.track)
                : Center(child: LocaleText('sport.trainings.no_route')),
          ),
          _summary(context),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final start = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(training.endMs);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(
            context,
            'sport.trainings.start',
            '${locale.formatMediumDate(start)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
          ),
          _line(
            context,
            'sport.trainings.end',
            '${locale.formatMediumDate(end)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(end))}',
          ),
          _line(
            context,
            'sport.trainings.duration',
            formatDuration(training.duration),
          ),
          _line(
            context,
            'sport.trainings.distance',
            formatDistanceKm(training.distanceM),
          ),
          _line(
            context,
            'sport.trainings.avg_speed',
            formatSpeed(training.avgSpeedKmh),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String labelKey, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            Locales.string(context, labelKey),
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
