import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
        minimumSize: const Size.fromHeight(54),
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        foregroundColor: scheme.onSurface.withValues(alpha: 0.8),
      ),
    );
  }
}

/// The control that throws something away or stops something: forgetting a
/// sensor, discarding a pod, stopping delivery.
///
/// A soft danger fill with the label in the danger colour, never an outline
/// (`docs/redesign/DESIGN.md`, "Buttons"). Soft rather than a solid red, so next
/// to a filled primary it does not read as the thing to press.
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
    final colors = context.ink;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: LocaleText(labelKey),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: colors.lowSoft,
        foregroundColor: colors.low,
      ),
    );
  }
}
