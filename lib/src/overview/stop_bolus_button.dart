import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The quiet way out of a running bolus, in the corner of the card.
///
/// A text button, not a bar the width of the card: it is there for the rare case,
/// and a control that size would read as the thing to press.
class StopBolusButton extends StatelessWidget {
  const StopBolusButton({super.key, required this.controller});

  final PodController controller;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        // Grey, not red. Stopping a bolus is a correction, not an emergency, and
        // the red on this screen belongs to the glucose alarms.
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () => _confirmStop(context),
      child: LocaleText('pump.bolus.stop'),
    );
  }

  /// Asked before the bolus is cut short. Not a formality: the dose the user
  /// calculated is about to be only partly given, and the meal on file will need
  /// correcting afterwards.
  void _confirmStop(BuildContext context) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText(
              'pump.bolus.stop_title',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            LocaleText(
              'pump.bolus.stop_body',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.bolus.stop',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: controller.cancelBolus,
    ).show(context);
  }
}
