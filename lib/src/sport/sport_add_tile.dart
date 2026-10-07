import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
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

  /// The primary pill: 54 px, accent with the content on it.
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: LocaleText(labelKey, maxLines: 1),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}
