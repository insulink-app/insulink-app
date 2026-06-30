import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Einheitliche „Hinzufügen"-Kachel für den Sport-Bereich: volle Breite, runder
/// Primary-Tint-Hintergrund, „+"-Icon + Label. Hebt sich klar von den grauen
/// Daten-Karten ab und ersetzt die schlichten OutlinedButtons.
class SportAddTile extends StatelessWidget {
  const SportAddTile({
    super.key,
    required this.labelKey,
    required this.onTap,
    this.icon = Icons.add,
  });

  final String labelKey;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: primary),
              const SizedBox(width: 8),
              Text(
                Locales.string(context, labelKey),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
