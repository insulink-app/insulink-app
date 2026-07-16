import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Uniform "add" tile for the sport area: full width, rounded primary-tint
/// background, "+" icon + label. Stands out clearly from the grey data cards and
/// replaces the plain OutlinedButtons.
class SportAddTile extends StatelessWidget {
  const SportAddTile({
    super.key,
    required this.labelKey,
    required this.onTap,
    this.icon = PhosphorIconsBold.plus,
  });

  final String labelKey;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                Locales.string(context, labelKey),
                style: TextStyle(
                  fontSize: 15,
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
}
