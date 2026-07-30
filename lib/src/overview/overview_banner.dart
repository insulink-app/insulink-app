import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Prominent, tappable strip above the overview's content that says a global
/// mode is holding something back, and clears that mode when tapped.
///
/// Shared by the silent-mode and battery-saver banners: both are the same amber
/// "this is not the normal state" affordance, and the point of putting it on the
/// main screen is that one tap ends it.
class OverviewBanner extends StatelessWidget {
  const OverviewBanner({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.hint,
    required this.onTap,
  });

  /// Amber: not an error, but not the resting state either. Deliberately one
  /// fixed tone for every banner so they read as one kind of thing.
  static const accent = Color(0xFFE8A13A);

  final IconData icon;
  final String titleKey;

  /// Already-resolved hint line — the battery banner interpolates a time into
  /// it, so this takes text rather than a key.
  final String hint;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: _text(Theme.of(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          titleKey,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
