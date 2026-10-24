import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/band/band_battery_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:provider/provider.dart';

/// The band's battery under the device head, drawn like the pod's reservoir
/// bar: muted title, value on the right, a 6 px bar that turns red once the
/// battery is low. Reads a fresh level when the page opens.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, state),
          const SizedBox(height: 8),
          _bar(context, state),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, BandBatteryState state) {
    return Row(
      children: [
        Text(
          Locales.string(context, 'google_health.band.battery'),
          style: InkText.label.copyWith(color: context.ink.muted),
        ),
        const Spacer(),
        Text(
          _value(context, state),
          style: InkText.row.copyWith(
            fontWeight: FontWeight.w700,
            color: state.low ? context.danger : context.ink.text,
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, BandBatteryState state) {
    final colors = context.ink;
    return LinearProgressIndicator(
      value: (state.battery?.percent ?? 0) / 100,
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
      color: state.low ? colors.low : colors.accent,
      backgroundColor: colors.line,
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
