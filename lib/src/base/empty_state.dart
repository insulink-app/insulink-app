import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// A friendly empty-state placeholder: a filled icon badge, a title and an
/// optional hint. Shared by every "nothing here yet" screen so they look uniform
/// instead of a bare line of centered text.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.titleKey,
    this.subtitleKey,
  });

  final IconData icon;
  final String titleKey;
  final String? subtitleKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            LocaleText(
              titleKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            if (subtitleKey != null) ...[
              const SizedBox(height: 6),
              LocaleText(
                subtitleKey!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
