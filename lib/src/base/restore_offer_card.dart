import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// An offer to take over a device the account still holds (the sensor, the
/// pod): the device glyph in an accent disc, a short title over the device and
/// its state, an optional one-line hint, and two equal buttons, the quiet
/// answer left and the takeover right. Both offers look the same on purpose.
class RestoreOfferCard extends StatelessWidget {
  const RestoreOfferCard({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.detail,
    required this.secondaryLabelKey,
    required this.onSecondary,
    required this.primaryLabelKey,
    required this.onPrimary,
    this.hintKey,
  });

  final IconData icon;
  final String titleKey;

  /// The device and its state, e.g. "Dexcom G7 · gestartet 05.10. 08:00".
  final String detail;

  final String? hintKey;
  final String secondaryLabelKey;
  final VoidCallback? onSecondary;
  final String primaryLabelKey;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: InkSpace.tileGap),
      child: InkPanel(
        radius: InkRadius.tile,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(colors),
            if (hintKey != null) ...[
              const SizedBox(height: 12),
              LocaleText(
                hintKey!,
                style: InkText.label.copyWith(color: colors.muted),
              ),
            ],
            const SizedBox(height: 16),
            _actions(colors),
          ],
        ),
      ),
    );
  }

  Widget _head(InsulinkColors colors) {
    return Row(
      spacing: 14,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.14),
          ),
          child: Icon(icon, size: 20, color: colors.accent),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              LocaleText(titleKey, style: InkText.rowTitle),
              Text(detail, style: InkText.label.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(InsulinkColors colors) {
    const size = Size.fromHeight(48);
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: FilledButton(
            onPressed: onSecondary,
            style: FilledButton.styleFrom(
              minimumSize: size,
              backgroundColor: colors.panelRaised,
              foregroundColor: colors.text,
            ),
            child: LocaleText(secondaryLabelKey),
          ),
        ),
        Expanded(
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(minimumSize: size),
            child: LocaleText(primaryLabelKey),
          ),
        ),
      ],
    );
  }
}
