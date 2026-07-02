import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// A single summary "box": icon badge + label + big value (optional unit),
/// tappable. Used both in the Sport tab's activity card and on the overview.
class SportSummaryTile extends StatelessWidget {
  const SportSummaryTile({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.value,
    this.unit,
    this.onTap,
  });

  final IconData icon;
  final String labelKey;
  final String value;
  final String? unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _iconBadge(scheme),
              const SizedBox(width: 12),
              Expanded(child: _text(context, scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(ColorScheme scheme) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: scheme.onPrimary),
    );
  }

  Widget _text(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Locales.string(context, labelKey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
