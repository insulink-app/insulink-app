import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/devices/device_row.dart';
import 'package:insulink/src/fitbit/fitbit_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';
import 'package:provider/provider.dart';

/// Aggregates the Sensor, Pump and Fitbit devices under one tab; each row opens
/// the respective device page as a sub-page (see [DeviceSubPage]).
class DevicesBody extends AppPageBody {
  DevicesBody({super.key})
    : super(
        name: "devices.label",
        unselectedIcon: CupertinoIcons.square_stack,
        selectedIcon: CupertinoIcons.square_stack_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const DevicesBodyContent();
  }

  @override
  Future<int> notifications(BuildContext context) async {
    final controller = Provider.of<G7Controller>(context, listen: false);
    // -1 renders as the red "no sensor" dot, same as the old Sensor tab.
    return controller.hasSensor ? 0 : -1;
  }
}

class DevicesBodyContent extends StatelessWidget {
  const DevicesBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSensor = context.watch<G7Controller>().hasSensor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        DeviceRow(
          icon: CupertinoIcons.drop_fill,
          labelKey: "sensor.label",
          page: const SensorBodyContent(),
          // The sensor's only notification is the "no sensor" attention dot,
          // mirrored here from the navigator badge.
          notify: !hasSensor,
        ),
        const SizedBox(height: 14),
        DeviceRow(
          icon: CupertinoIcons.today_fill,
          labelKey: "pump.label",
          page: const PumpBodyContent(),
        ),
        const SizedBox(height: 14),
        DeviceRow(
          icon: Icons.watch,
          labelKey: "fitbit.label",
          page: const FitbitBodyContent(),
        ),
      ],
    );
  }
}
