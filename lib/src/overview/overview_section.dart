import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

/// A panel on the overview: the devices, or a notice. Flat panel colour with
/// rounded corners and no rim, so the page reads as calm grouped areas; the
/// glucose area above it stays open without one.
class OverviewSection extends StatelessWidget {
  const OverviewSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.insulinkColors.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
