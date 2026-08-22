import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/profile_segments.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The window picker and the generate button, shared by both suggestions.
///
/// Generated on demand rather than on a schedule: the person asking has a reason
/// to ask, and a proposal that appears by itself is one nobody reads. The longer
/// windows are also the answer when a short one found too little, which after a
/// busy week it usually does.
class TuningControls extends StatelessWidget {
  const TuningControls({
    super.key,
    required this.descriptionKey,
    required this.days,
    required this.onDays,
    required this.onGenerate,
  });

  /// Seven days is one week of nights, ninety is long enough to average out a
  /// season.
  static const List<int> windows = [7, 30, 90];

  final String descriptionKey;
  final int days;
  final ValueChanged<int> onDays;
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
        ProfileSegments([
          for (final window in windows)
            (
              labelKey: 'profile.tuning.window.d$window',
              selected: window == days,
              fill: null,
              onTap: () => onDays(window),
            ),
        ]),
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
