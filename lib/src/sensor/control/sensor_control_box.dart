import 'package:flutter/widgets.dart';

import '../../cgm/cgm_controller.dart';
import 'sensor_pairing_form.dart';
import 'sensor_status_box.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/sensor/control/sensor_session_controls.dart';

/// Top-of-page connection box: the pairing form before a sensor is set up, or
/// the status + session controls once paired.
class SensorControlBox extends StatelessWidget {
  const SensorControlBox({
    super.key,
    required this.controller,
    required this.details,
  });

  final CgmController controller;

  /// The sensor's data sections, shown under the head once paired.
  final Widget details;

  bool get _unpaired =>
      !controller.hasSensor && !controller.connected && !controller.busy;

  /// Service running (or starting) but no reading has arrived yet.
  bool get _searching =>
      (controller.connected || controller.busy) &&
      controller.currentMgdl == null;

  /// Before pairing only the form; after it the head, the data, and at the
  /// bottom the actions that end the session or the sensor.
  @override
  Widget build(BuildContext context) {
    if (_unpaired) {
      return SensorPairingForm(controller: controller);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SensorStatusBox(controller: controller, searching: _searching),
        details,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SectionHeader(titleKey: 'sensor.manage'),
        ),
        SensorSessionControls(controller: controller),
      ],
    );
  }
}
