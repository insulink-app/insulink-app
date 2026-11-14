import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/sensor/control/libre3_scan_flow.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// "Pair again" under a sensor in the history: adopts that sensor's stored
/// identity, the way the overview's restore offer does. Meant for a sensor that
/// was stopped in the app but is still on the body.
///
/// Shown only while the sensor has not run out and no sensor is set up on the
/// phone, since a paired one would have to be stopped first. The account
/// clears the sensor's discard stamp on the first update the app sends for it.
class SensorRepairButton extends StatelessWidget {
  const SensorRepairButton({super.key, required this.entry});

  final DeviceHistoryEntry entry;

  bool _offered(CgmController controller) {
    return (entry.record.restore?.isAdoptable ?? false) &&
        entry.record.expiresAt.isAfter(DateTime.now()) &&
        !controller.hasSensor;
  }

  /// A G7 reconnects from the restored identity; a Libre 3 needs a fresh NFC
  /// scan for its PIN. Either way the user lands back on the sensor page.
  Future<void> _pairAgain(
    BuildContext context,
    CgmController controller,
  ) async {
    final navigator = Navigator.of(context);
    final reading = await controller.restoreSensor(entry.record.restore!);
    if (!reading && context.mounted) {
      await Libre3ScanFlow(controller: controller).run(context);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    if (!_offered(controller)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SecondaryActionButton(
        labelKey: 'connections.history.pair_again',
        icon: PhosphorIconsBold.arrowsClockwise,
        onPressed: () => _pairAgain(context, controller),
      ),
    );
  }
}
