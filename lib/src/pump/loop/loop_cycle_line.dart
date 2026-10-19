import 'package:insulink/src/activity_mode/activity_mode.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/localization/enum_locale_key.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:provider/provider.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/sport/sport_format.dart';

/// What the automation last decided, in one line.
///
/// The rate on its own says nothing that can be checked. Shown next to the
/// glucose it was computed from and the ceiling that held it back, it can be:
/// a user who sees a rate lower than expected can read why in the same line
/// instead of trusting that something sensible happened.
class PodLoopCycleLine extends StatelessWidget {
  const PodLoopCycleLine({super.key});

  @override
  Widget build(BuildContext context) {
    final style = InkText.caption.copyWith(color: context.ink.muted);
    final cycles = context.watch<PodController>().store.loopCycles;
    if (cycles.isEmpty) {
      return LocaleText('pump.loop.no_cycle', style: style);
    }
    return Text(_describe(context, cycles.first), style: style);
  }

  String _describe(BuildContext context, PodLoopCycle cycle) {
    final line = Locales.string(context, 'pump.loop.last')
        .replaceFirst('#', _clock(cycle.at))
        .replaceFirst('#', sportDecimal(cycle.unitsPerHour, 2))
        .replaceFirst(
          '#',
          Locales.string(context, 'pump.loop.reason.${cycle.reason.localeKey}'),
        );
    final bound = cycle.boundBy;
    final held = bound == null
        ? line
        : '$line ${Locales.string(context, 'pump.loop.bound.${bound.localeKey}')}';
    final withActivity = '$held${_activity(context, cycle.activity)}';
    return cycle.microBolusUnits > 0
        ? '$withActivity · ${_microBolus(context, cycle)}'
        : withActivity;
  }

  /// The activity mode the cycle ran under, so a rate below the schedule during
  /// a walk reads as the mode working. Nothing for normal.
  String _activity(BuildContext context, ActivityMode mode) {
    if (mode == ActivityMode.normal) {
      return '';
    }
    final name = Locales.string(context, 'activity_mode.${mode.name}');
    return ' ${Locales.string(context, 'pump.loop.activity').replaceFirst('#', name)}';
  }

  String _microBolus(BuildContext context, PodLoopCycle cycle) {
    return Locales.string(
      context,
      'pump.loop.micro_bolus',
    ).replaceFirst('#', sportDecimal(cycle.microBolusUnits, 2));
  }

  String _clock(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}
