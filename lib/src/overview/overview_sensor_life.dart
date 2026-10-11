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
      sessionLengthSec: controller.sessionLengthSec,
      overview: true,
    );
  }
}
