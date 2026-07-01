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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
        const SizedBox(height: 14),
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

  /// A large, card-styled device row: tinted icon badge, bold label, an
  /// attention dot when needed, and a chevron. More prominent than a plain
  /// ListTile since there are only two devices.
  Widget _deviceRow(
    BuildContext context, {
    required IconData icon,
    required String labelKey,
    required Widget page,
    required bool notify,
  }) {
    final label = Locales.string(context, labelKey);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _DeviceSubPage(title: label, body: page),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              if (notify) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
              ],
              Icon(CupertinoIcons.chevron_right, size: 18, color: scheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
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
