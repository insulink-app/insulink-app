import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/bolus/bolus_factor_editor_sheet.dart';
import 'package:insulink/src/profile/bolus/bolus_fill_bar.dart';

/// A tappable summary of one bolus factor — label, current value and a fill
/// visualization. Opens [BolusFactorEditorSheet] on tap.
class BolusFactorCard extends StatelessWidget {
  const BolusFactorCard({
    super.key,
    required this.labelKey,
    required this.valueKey,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String labelKey, valueKey;
  final int value, min, max, step;
  final void Function(int) onChanged;

  void _openEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BolusFactorEditorSheet(
        labelKey: labelKey,
        valueKey: valueKey,
        value: value,
        min: min,
        max: max,
        step: step,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEditor(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, theme, accent),
              const SizedBox(height: 12),
              BolusFillBar(value: value, min: min, max: max, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme, Color accent) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LocaleText(
            labelKey,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          Locales.string(context, valueKey, params: ['$value']),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Icon(
          Icons.chevron_right,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}
