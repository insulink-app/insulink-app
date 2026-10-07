import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/sensor/control/sensor_control_box.dart';
import 'package:insulink/src/sensor/info/libre3_sensor_info.dart';
import 'package:insulink/src/sensor/info/sensor_info.dart';
import 'package:provider/provider.dart';

/// The sensor device page, shown inside the Devices tab (see [DevicesBody]).
///
/// The connection box stays pinned at the top; the attribute list scrolls
/// underneath it and the box fades out to free up the room it occupies. The pump
/// page is built the same way, from the same [PinnedHeaderScroll].
class SensorBodyContent extends StatelessWidget {
  const SensorBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          SensorControlBox(
            controller: controller,
            details: _sensorInfo(controller),
          ),
        ],
      ),
    );
  }

  /// The G7 info page reads a [G7DeviceInfo]; the Libre 3 has its own builder
  /// (activation MAC, session clock, plus the one-minute reading's predicted
  /// glucose / trend / temperature).
  Widget _sensorInfo(CgmController controller) {
    if (controller.sensorType == SensorType.abbottLibre3) {
      return Libre3SensorInfo(
        mac: controller.libreMac,
        sensorStart: controller.sensorStart,
        lastUpdate: controller.lastUpdate,
        latest: controller.latest,
      );
    }
    return SensorInfo(
      info: controller.info,
      sensorStart: controller.sensorStart,
      state: controller.latest?.state,
      age: controller.latest?.secsSinceStart,
      lastUpdate: controller.lastUpdate,
    );
  }
}
