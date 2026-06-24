import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_range_bar.dart';
import 'package:insulink/src/profile/glucose/glucose_range_editor_sheet.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';

/// A tappable summary of one low/high range — label, current values and a band
/// visualization. Opens [GlucoseRangeEditorSheet] on tap.
class GlucoseRangeCard extends StatelessWidget {
  const GlucoseRangeCard({
    super.key,
    required this.state,
    required this.accent,
    required this.labelKey,
    required this.lowLabelKey,
    required this.highLabelKey,
    required this.low,
    required this.high,
    required this.onChanged,
    this.onTest,
  });

  final ProfileGlucoseState state;
  final Color accent;
  final String labelKey, lowLabelKey, highLabelKey;
  final int low, high;
  final void Function(int low, int high) onChanged;

  /// Optional alarm-preview callback, forwarded to the editor sheet's test
  /// button. Null for the (non-alarm) target range.
  final VoidCallback? onTest;

  void _openEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GlucoseRangeEditorSheet(
        state: state,
        accent: accent,
        titleKey: labelKey,
        lowLabelKey: lowLabelKey,
        highLabelKey: highLabelKey,
        low: low,
        high: high,
        onChanged: onChanged,
        onTest: onTest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              _header(theme),
              const SizedBox(height: 12),
              GlucoseRangeBar(low: low, high: high, color: accent, height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
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
          '${state.format(low)} – ${state.formatWithUnit(high)}',
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
