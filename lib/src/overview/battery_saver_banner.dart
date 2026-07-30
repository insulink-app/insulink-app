import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_banner.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Shown on the overview while the battery saver holds background work back, so
/// the paused activity detection is never a silent surprise. Tapping it turns the
/// saver off.
class BatterySaverBanner extends StatelessWidget {
  const BatterySaverBanner(this.mode, {super.key});

  final BatteryMode mode;

  @override
  Widget build(BuildContext context) {
    return OverviewBanner(
      icon: PhosphorIconsBold.batteryLow,
      titleKey: 'overview.battery.${mode.name}.title',
      hint: _hint(context),
      onTap: () =>
          context.read<ProfileBatteryState>().setMode(BatteryMode.off),
    );
  }

  /// "what is paused · until 14:30 · tap to end". The middle part is dropped for
  /// a permanent saver, which has no time to name.
  String _hint(BuildContext context) {
    final until = context.watch<ProfileBatteryState>().until;
    final parts = [
      Locales.string(context, 'overview.battery.${mode.name}.hint'),
      if (until != ProfileBatteryState.permanent)
        Locales.string(
          context,
          'overview.battery.until',
          params: [_clock(DateTime.fromMillisecondsSinceEpoch(until))],
        ),
      Locales.string(context, 'overview.battery.end'),
    ];
    return parts.join(' · ');
  }

  String _clock(DateTime at) {
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}
