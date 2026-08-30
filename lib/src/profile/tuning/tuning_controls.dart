import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The generate button, shared by both suggestions.
///
/// Generated on demand rather than on a schedule: the person asking has a reason
/// to ask, and a proposal that appears by itself is one nobody reads.
///
/// The period is fixed at [windowDays] and there is no picker. Three lengths to
/// choose from is a decision the user has no basis for making, and the answer
/// was the same one every time: a month is long enough to average out a bad week
/// and short enough to still describe the person you are now.
class TuningControls extends StatelessWidget {
  const TuningControls({
    super.key,
    required this.descriptionKey,
    required this.onGenerate,
  });

  /// The period every suggestion is computed over.
  static const int windowDays = 30;

  final String descriptionKey;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          descriptionKey,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SecondaryActionButton(
          labelKey: 'profile.tuning.generate',
          icon: PhosphorIconsBold.trendUp,
          onPressed: onGenerate,
        ),
      ],
    );
  }
}
