import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_detail_page.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_recording_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:provider/provider.dart';

/// "Trainings" section of the sport home page: three start buttons
/// (walk/jog/cycle) and the most recently recorded trainings.
class CardioSection extends StatelessWidget {
  const CardioSection({super.key});

  @override
  Widget build(BuildContext context) {
    final trainings = context.watch<CardioTrainingState>().trainings;
    final recent = trainings.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'sport.trainings',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final type in CardioType.values) ...[
              Expanded(child: _startButton(context, type)),
              if (type != CardioType.values.last) const SizedBox(width: 12),
            ],
          ],
        ),
        for (final training in recent) _trainingCard(context, training),
      ],
    );
  }

  Widget _startButton(BuildContext context, CardioType type) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CardioRecordingPage(type: type),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(type.icon, color: scheme.primary, size: 26),
              const SizedBox(height: 6),
              Text(
                Locales.string(context, type.labelKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trainingCard(BuildContext context, CardioTraining training) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        leading: Icon(training.type.icon, color: scheme.primary),
        title: Text(
          Locales.string(context, training.type.labelKey),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${locale.formatMediumDate(started)} · ${formatDistanceKm(training.distanceM)}',
        ),
        trailing: Text(formatDuration(training.duration)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CardioDetailPage(training: training),
          ),
        ),
      ),
    );
  }
}
