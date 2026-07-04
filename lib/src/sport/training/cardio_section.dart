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
    final state = context.watch<CardioTrainingState>();
    final trainings = state.trainings;
    final recent = trainings.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'sport.trainings',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (state.activeTraining != null) ...[
          _resumeBanner(context, state.activeTraining!.type),
          const SizedBox(height: 12),
        ],
        for (final pending in state.pendingTrainings)
          _pendingCard(context, state, pending),
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

  /// Banner to jump back into a training that is still recording (e.g. left via
  /// the back button) — the service keeps recording in the meantime.
  Widget _resumeBanner(BuildContext context, CardioType type) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CardioRecordingPage(resume: true),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(type.icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: LocaleText(
                  'sport.trainings.resume_active',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
              Icon(Icons.play_arrow_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// Confirmation prompt for an auto-detected training: what was detected, with
  /// Confirm / Reject actions (also offered as buttons on the notification).
  Widget _pendingCard(
    BuildContext context,
    CardioTrainingState state,
    CardioTraining training,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(training.type.icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocaleText(
                      'sport.trainings.detected_prompt',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Locales.string(context, training.type.labelKey)} · '
                      '${locale.formatMediumDate(started)} · '
                      '${formatDistanceKm(training.distanceM)}',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => state.rejectDetected(training.id),
                  child: LocaleText('sport.detect_notification.reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => state.confirmDetected(training.id),
                  child: LocaleText('sport.detect_notification.confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _startButton(BuildContext context, CardioType type) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
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
              Icon(type.icon, color: scheme.onPrimary, size: 26),
              const SizedBox(height: 6),
              Text(
                Locales.string(context, type.labelKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
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
          '${locale.formatMediumDate(started)} · ${formatDistanceKm(training.distanceM)}'
          '${training.detected ? ' · ${Locales.string(context, 'sport.trainings.detected')}' : ''}',
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
