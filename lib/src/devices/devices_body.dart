import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/devices/device_row.dart';
import 'package:insulink/src/google_health/google_health_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';
import 'package:provider/provider.dart';

/// Opens the devices page (Sensor + Pump + Google Health) on top of the current tab.
/// Reached from the header device button and the overview shortcuts, now that
/// devices is no longer a bottom-navigation tab.
void openDevicesPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DevicesPage()));
}

/// The devices page as a standalone route, with its own header + back button.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('devices.label'),
      ),
      body: const DevicesBodyContent(),
    );
  }
}

class DevicesBodyContent extends StatelessWidget {
  const DevicesBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSensor = context.watch<CgmController>().hasSensor;
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
          labelKey: "google_health.label",
          page: const GoogleHealthBodyContent(),
        ),
      ],
    );
  }
}
