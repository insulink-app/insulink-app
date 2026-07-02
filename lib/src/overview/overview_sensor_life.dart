import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/sensor/control/sensor_life_bar.dart';
import 'package:provider/provider.dart';

/// Remaining sensor lifetime on the overview — the same day/hour segment bar as
/// the sensor page. Renders nothing until a sensor start is known.
class OverviewSensorLife extends StatelessWidget {
  const OverviewSensorLife({super.key});

  /// Standard G7 session length (~10.5 d incl. grace) — the last-resort default.
  static const int _defaultSessionLengthSec = 907200;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<G7Controller>();
    final start = controller.sensorStart;
    if (start == null) {
      return const SizedBox.shrink();
    }
    return SensorLifeBar(
      start: start,
      sessionLengthSec: _sessionLength(controller),
    );
  }

  /// Best-effort session length: the sensor's reported value, else its max
  /// lifetime, else the standard G7 lifetime — so the bar always renders.
  int _sessionLength(G7Controller controller) {
    final info = controller.info;
    if (info.sessionLengthSec != null) {
      return info.sessionLengthSec!;
    }
    if (info.maxLifetimeDays != null) {
      return info.maxLifetimeDays! * 86400;
    }
    return _defaultSessionLengthSec;
  }
}
