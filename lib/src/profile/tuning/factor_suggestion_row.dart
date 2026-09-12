import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/tuning/factor_suggestion.dart';
import 'package:insulink/src/theme/accent_colors.dart';
import 'package:insulink/src/theme/brand_tints.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One proposed setting, next to the one in use.
///
/// Both numbers are shown in the same words the setting itself uses, so the
/// proposal can be read against the card above it without translating anything
/// in your head. Adopting it is a tap of its own: nothing here changes a setting
/// by being displayed.
class FactorSuggestionRow extends StatelessWidget {
  const FactorSuggestionRow({
    super.key,
    required this.labelKey,
    required this.valueKey,
    required this.suggestion,
    required this.onApply,
  });

  /// The setting's own label and value format, e.g. `profile.bolus.correction`
  /// and `profile.bolus.correction.value`.
  final String labelKey, valueKey;

  final FactorSuggestion suggestion;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.tintPanel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _numbers(context, scheme)),
          TextButton(
            onPressed: onApply,
            child: LocaleText('profile.tuning.factors.apply'),
          ),
        ],
      ),
    );
  }

  Widget _numbers(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          labelKey,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _formatted(context, suggestion.current),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Icon(
              PhosphorIconsBold.arrowRight,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              _formatted(context, suggestion.suggested),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          Locales.string(
            context,
            _samplesKey,
          ).replaceFirst('#', '${suggestion.samples}'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Says how the number was arrived at, because a value read off a correction
  /// dose and one inferred across a month of meals are not equally strong
  /// evidence, and the person tapping "adopt" is the one who should weigh that.
  String get _samplesKey => suggestion.measured
      ? 'profile.tuning.factors.samples'
      : 'profile.tuning.factors.samples_inferred';

  String _formatted(BuildContext context, int value) =>
      Locales.string(context, valueKey).replaceFirst('#', '$value');
}
