import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

/// A panel on the overview: the devices, or a notice. Flat panel colour with
/// rounded corners and no rim, so the page reads as calm grouped areas; the
/// glucose area above it stays open without one.
class OverviewSection extends StatelessWidget {
  const OverviewSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;

  /// Inner spacing; a panel ending in a row that brings its own height (the
  /// automation row) trims the bottom.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.insulinkColors.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
