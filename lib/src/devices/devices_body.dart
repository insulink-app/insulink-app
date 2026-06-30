import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';
import 'package:provider/provider.dart';

/// Aggregates the Sensor and Pump devices under one tab; each row opens the
/// respective device page as a sub-page (see [_DeviceSubPage]).
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _deviceRow(
          context,
          icon: CupertinoIcons.drop_fill,
          labelKey: "sensor.label",
          page: const SensorBodyContent(),
          // The sensor's only notification is the "no sensor" attention dot,
          // mirrored here from the navigator badge.
          notify: !hasSensor,
        ),
        _deviceRow(
          context,
          icon: CupertinoIcons.today_fill,
          labelKey: "pump.label",
          page: const PumpBodyContent(),
          notify: false,
        ),
      ],
    );
  }

  Widget _deviceRow(
    BuildContext context, {
    required IconData icon,
    required String labelKey,
    required Widget page,
    required bool notify,
  }) {
    final label = Locales.string(context, labelKey);
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notify) ...[
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
          ],
          const Icon(CupertinoIcons.chevron_right, size: 18),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DeviceSubPage(title: label, body: page),
        ),
      ),
    );
  }
}

/// A device page shown on top of the Devices tab, with a back button.
class _DeviceSubPage extends StatelessWidget {
  final String title;
  final Widget body;

  const _DeviceSubPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(title),
      ),
      body: body,
    );
  }
}
