import 'package:flutter/material.dart';

/// A boxed section on the overview: rounded surface card with a subtle border,
/// so the page reads as distinct grouped sections.
class OverviewSection extends StatelessWidget {
  const OverviewSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }
}
