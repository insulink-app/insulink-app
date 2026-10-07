import 'package:flutter/material.dart';
import 'package:insulink/src/base/track_bar.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// How much of its rated life a device was worn: the share, and whether it
/// came off early (under 90 % of the rated days). A running device is never
/// early.
class DeviceWear {
  DeviceWear(this.entry);

  final DeviceHistoryEntry entry;

  static const double _earlyBelow = 0.9;

  double get fraction {
    final rated = entry.ratedDays * 86400;
    if (rated <= 0) {
      return 1;
    }
    return (entry.worn().inSeconds / rated).clamp(0.0, 1.0);
  }

  bool get early => !entry.isActive && fraction < _earlyBelow;
}

/// The worn share as a bar: accent, or the high colour for a device that came
/// off early.
class DeviceWearBar extends StatelessWidget {
  const DeviceWearBar({
    super.key,
    required this.fraction,
    required this.early,
    required this.height,
  });

  final double fraction;
  final bool early;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return TrackBar(
      startFraction: 0,
      endFraction: fraction,
      color: early ? colors.high : colors.accent,
      height: height,
    );
  }
}
