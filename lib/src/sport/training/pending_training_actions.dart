import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:provider/provider.dart';

/// Reject / Confirm for an auto-detected training, wherever one is put in front
/// of the user: the prompt card on the Sport page, and the detail page a tap on
/// the detection notification opens. The two live in one widget so a decision
/// looks and behaves the same in both.
///
/// [onDecided] runs after either choice, for a caller that has to leave the
/// screen the training was on.
class PendingTrainingActions extends StatelessWidget {
  const PendingTrainingActions(this.trainingId, {super.key, this.onDecided});

  final String trainingId;
  final VoidCallback? onDecided;

  void _decide(Future<void> Function(String) decision) {
    decision(trainingId);
    onDecided?.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CardioTrainingState>();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => _decide(state.rejectDetected),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurface.withValues(alpha: 0.75),
              backgroundColor: scheme.onSurface.withValues(alpha: 0.06),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: LocaleText('sport.detect_notification.reject'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => _decide(state.confirmDetected),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: LocaleText('sport.detect_notification.confirm'),
          ),
        ),
      ],
    );
  }
}
