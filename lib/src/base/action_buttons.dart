import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// The secondary control under a primary one: a step back, not a deletion.
///
/// Filled tonally rather than outlined, so it reads as a real control without
/// competing with the filled primary above it. Ending a session and stopping a
/// search both look like this, because neither loses anything.
class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.labelKey,
    required this.icon,
    required this.onPressed,
  });

  final String labelKey;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: LocaleText(labelKey),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        foregroundColor: scheme.onSurface.withValues(alpha: 0.8),
      ),
    );
  }
}

/// The control that throws something away: forgetting a sensor, discarding a pod.
///
/// Outlined rather than filled, in the danger tone with a matching rim. Outlined
/// on purpose — a filled red button next to a filled primary reads as the thing
/// to press, and this never is.
class DangerActionButton extends StatelessWidget {
  const DangerActionButton({
    super.key,
    required this.labelKey,
    required this.icon,
    required this.onPressed,
  });

  final String labelKey;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: LocaleText(labelKey),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.danger,
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
