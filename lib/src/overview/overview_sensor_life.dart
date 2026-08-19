import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:provider/provider.dart';

/// Remaining sensor lifetime on the overview — the same day/hour segment bar as
/// the sensor page. Renders nothing until a sensor start is known.
class OverviewSensorLife extends StatelessWidget {
  const OverviewSensorLife({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final start = controller.sensorStart;
    if (start == null) {
      return const SizedBox.shrink();
    }
    return DeviceLifespanBar(
      start: start,
      sessionLengthSec: _sessionLength(controller),
      overview: true,
    );
  }

  /// Best-effort session length: the sensor's reported value, else its max
  /// lifetime, else the active sensor's nominal lifetime (G7 ~10 d, Libre 3
  /// 14 d) — so the bar always renders with the right total.
  int _sessionLength(CgmController controller) {
    final info = controller.info;
    if (info.sessionLengthSec != null) {
      return info.sessionLengthSec!;
    }
    if (info.maxLifetimeDays != null) {
      return info.maxLifetimeDays! * 86400;
    }
    return controller.sensorType.sessionLengthSec;
  }
}
