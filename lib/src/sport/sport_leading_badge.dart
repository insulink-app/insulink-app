import 'package:flutter/material.dart';

/// Circular tinted icon badge used as the leading element of routine and
/// activity tiles, so they all look uniform.
class SportLeadingBadge extends StatelessWidget {
  const SportLeadingBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }
}
