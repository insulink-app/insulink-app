import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_mode_window.dart';

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
    required this.hintKey,
    required this.until,
    required this.onTap,
  });

  /// Amber: not an error, but not the resting state either. Deliberately one
  /// fixed tone for every banner so they read as one kind of thing.
  static const accent = Color(0xFFE8A13A);

  final IconData icon;
  final String titleKey;

  /// What the mode is holding back, in the mode's own words.
  final String hintKey;

  /// When the mode ends (epoch ms), or [ProfileModeWindow.permanent] — a
  /// time-limited mode names its end time so the user knows whether to act.
  final int until;

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
              Expanded(child: _text(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(BuildContext context) {
    final theme = Theme.of(context);
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
          _hint(context),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  /// "what is held back · until 14:30 · tap to end". The middle part is dropped
  /// for a mode with no time limit, which has no end to name.
  String _hint(BuildContext context) {
    final parts = [
      Locales.string(context, hintKey),
      if (until != ProfileModeWindow.permanent)
        Locales.string(
          context,
          'overview.mode.until',
          params: [_clock(DateTime.fromMillisecondsSinceEpoch(until))],
        ),
      Locales.string(context, 'overview.mode.end'),
    ];
    return parts.join(' · ');
  }

  String _clock(DateTime at) {
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}
