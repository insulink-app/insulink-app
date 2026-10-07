import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_detail_page.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_recording_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training/pending_training_actions.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// "Trainings" section of the sport home page: three start buttons
/// (walk/jog/cycle), a resume banner and any pending auto-detected trainings.
class CardioSection extends StatelessWidget {
  const CardioSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CardioTrainingState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'sport.trainings',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final pending in state.pendingTrainings)
          _pendingCard(context, pending),
        Row(
          children: [
            for (final type in CardioType.values) ...[
              Expanded(child: _startButton(context, type)),
              if (type != CardioType.values.last) const SizedBox(width: 12),
            ],
          ],
        ),
      ],
    );
  }

  /// Confirmation prompt for an auto-detected training: what was detected, with
  /// Confirm / Reject actions (also offered as buttons on the notification).
  /// Tapping the card itself opens the detection, the same view a tap on the
  /// notification lands on, so nobody has to decide on it unseen.
  Widget _pendingCard(BuildContext context, CardioTraining training) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.tintLine),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CardioDetailPage(training: training),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(training.type.icon, color: scheme.onSurfaceVariant),
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
                PendingTrainingActions(training.id),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A soft accent tile per training type, its glyph over its name.
  Widget _startButton(BuildContext context, CardioType type) {
    final colors = context.ink;
    return Material(
      color: colors.accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InkRadius.tile),
        side: BorderSide(color: colors.accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CardioRecordingPage(type: type),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(type.icon, color: colors.accent, size: 26),
              const SizedBox(height: 8),
              Text(
                Locales.string(context, type.labelKey),
                style: InkText.row.copyWith(color: colors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
