import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/band/band_battery_state.dart';
import 'package:insulink/src/google_health/band/band_level_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:provider/provider.dart';

/// The band's battery under the device head, beside the time it should still
/// last; amber once it is low. Reads a fresh level when the page opens.
class BandBatteryBar extends StatefulWidget {
  const BandBatteryBar({super.key});

  @override
  State<BandBatteryBar> createState() => _BandBatteryBarState();
}

class _BandBatteryBarState extends State<BandBatteryBar> {
  @override
  void initState() {
    super.initState();
    context.read<BandBatteryState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BandBatteryState>();
    if (!state.paired) {
      return const SizedBox.shrink();
    }
    return BandLevelBar(
      labelKey: 'google_health.band.battery',
      value: _value(context, state),
      note: _remaining(context, state),
      fraction: (state.battery?.percent ?? 0) / 100,
      warn: state.low,
    );
  }

  /// The estimate in days, or in hours for the last two days.
  String? _remaining(BuildContext context, BandBatteryState state) {
    final remaining = state.remaining;
    if (remaining == null) {
      return null;
    }
    final inDays = remaining.inHours >= 48;
    return Locales.string(
      context,
      inDays
          ? 'google_health.band.remaining_days'
          : 'google_health.band.remaining_hours',
      params: ['${inDays ? remaining.inDays : remaining.inHours}'],
    );
  }

  String _value(BuildContext context, BandBatteryState state) {
    final battery = state.battery;
    if (battery == null) {
      return '–';
    }
    final charging = battery.charging == true
        ? ' ${Locales.string(context, 'google_health.band.charging')}'
        : '';
    return '${battery.percent} %$charging';
  }
}
