import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// A settings toggle row: localized label on the left, switch flush right.
///
/// Shared by every profile toggle so the switches line up in a column no matter
/// how long each label is (the label takes the remaining width via [Expanded]
/// and wraps; the switch stays at the right edge).
///
/// A null [onChanged] renders the switch disabled — for a setting that only
/// means something while another one is on.
class ProfileToggleRow extends StatelessWidget {
  const ProfileToggleRow({
    super.key,
    required this.labelKey,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final String labelKey;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Thumb colour when on (defaults to the theme primary).
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = activeColor ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: LocaleText(labelKey, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: active,
            activeTrackColor: active.withValues(alpha: 0.45),
            inactiveThumbColor: Colors.grey,
          ),
        ],
      ),
    );
  }
}
