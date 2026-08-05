import 'package:flutter/material.dart';
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
    final state = context.watch<ProfileBatteryState>();
    return OverviewBanner(
      icon: PhosphorIconsBold.batteryLow,
      titleKey: 'overview.battery.${mode.name}.title',
      hintKey: 'overview.battery.${mode.name}.hint',
      until: state.window.until,
      onTap: () =>
          context.read<ProfileBatteryState>().setMode(BatteryMode.off),
    );
  }
}
