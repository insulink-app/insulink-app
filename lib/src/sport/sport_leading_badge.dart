import 'package:flutter/material.dart';

/// Circular icon badge used as the leading element of routine and activity
/// tiles, so they all look uniform. Neutral, never the brand colour: the app
/// reserves colour and a square face for things you can press, and this badge
/// only says what the row IS. The same badge the empty states and food cards use.
class SportLeadingBadge extends StatelessWidget {
  const SportLeadingBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
    );
  }
}
