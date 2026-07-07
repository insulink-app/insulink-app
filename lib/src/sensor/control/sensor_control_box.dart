import 'package:flutter/widgets.dart';

import '../../cgm/cgm_controller.dart';
import 'sensor_pairing_form.dart';
import 'sensor_status_box.dart';

/// Top-of-page connection box: the pairing form before a sensor is set up, or
/// the status + session controls once paired.
class SensorControlBox extends StatelessWidget {
  const SensorControlBox({super.key, required this.controller});

  final CgmController controller;

  bool get _unpaired =>
      !controller.hasSensor && !controller.connected && !controller.busy;

  /// Service running (or starting) but no reading has arrived yet.
  bool get _searching =>
      (controller.connected || controller.busy) &&
      controller.currentMgdl == null;

  @override
  Widget build(BuildContext context) {
    if (_unpaired) {
      return SensorPairingForm(controller: controller);
    }
    return SensorStatusBox(controller: controller, searching: _searching);
  }
}
