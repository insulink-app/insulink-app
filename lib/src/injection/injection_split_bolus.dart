import 'package:flutter/material.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/injection/split_bolus_choice.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_toggle_row.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The split-bolus controls under the bolus field: a switch, then how much
/// goes out now and over how long the rest is spread, and what that makes of
/// the dose in the field.
class InjectionSplitBolus extends StatelessWidget {
  const InjectionSplitBolus({
    super.key,
    required this.choice,
    required this.bolus,
    required this.onChanged,
  });

  final SplitBolusChoice choice;

  /// The dose in the field, for the summary line.
  final double bolus;

  final ValueChanged<SplitBolusChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          ProfileToggleRow(
            labelKey: 'injection.split._',
            infoKey: 'injection.split.info',
            value: choice.enabled,
            onChanged: (enabled) =>
                onChanged(choice.copyWith(enabled: enabled)),
          ),
          if (choice.enabled) ..._details(context),
        ],
      ),
    );
  }

  List<Widget> _details(BuildContext context) {
    final muted = InkText.label.copyWith(color: context.ink.muted);
    return [
      LocaleText('injection.split.now', style: muted),
      SegmentedToggle<int>(
        selected: choice.nowPercent,
        onChanged: (percent) => onChanged(choice.copyWith(nowPercent: percent)),
        options: [
          for (final percent in SplitBolusChoice.nowPercents)
            (value: percent, label: '$percent %'),
        ],
      ),
      LocaleText('injection.split.over', style: muted),
      SegmentedToggle<int>(
        selected: choice.overMinutes,
        onChanged: (minutes) =>
            onChanged(choice.copyWith(overMinutes: minutes)),
        options: [
          for (final minutes in SplitBolusChoice.overMinuteOptions)
            (value: minutes, label: '$minutes min'),
        ],
      ),
      Text(_summary(context), style: muted),
    ];
  }

  String _summary(BuildContext context) => Locales.string(
    context,
    'injection.split.summary',
    params: [
      sportDecimal(choice.nowUnits(bolus), 2),
      sportDecimal(choice.laterUnits(bolus), 2),
      '${choice.overMinutes}',
    ],
  );
}
