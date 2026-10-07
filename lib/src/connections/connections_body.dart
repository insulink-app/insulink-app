import 'package:flutter/material.dart';
import 'package:insulink/src/connections/connection_row.dart';
import 'package:insulink/src/connections/connections_summary.dart';
import 'package:insulink/src/connections/device_links.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/connections/history/device_history_page.dart';
import 'package:insulink/src/connections/history/device_history_sync.dart';
import 'package:insulink/src/google_health/google_health_body.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_delivery_log_page.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/pump/pump_body.dart';
import 'package:insulink/src/sensor/sensor_body.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Opens the connections page (Sensor + Pump + Google Health) on top of the current tab.
/// Reached from the header device button and the overview shortcuts, now that
/// connections is no longer a bottom-navigation tab.
void openConnectionsPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ConnectionsPage()));
}

/// Opens the sensor page directly (skipping the connections list), for shortcuts
/// that are specifically about the sensor — e.g. the overview's sensor section.
void openSensorPage(BuildContext context) {
  final title = Locales.string(context, 'sensor.label');
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConnectionSubPage(
        title: title,
        body: const SensorBodyContent(),
        actions: const [DeviceHistoryButton(kind: DeviceHistoryKind.sensors)],
      ),
    ),
  );
}

/// Opens the pump page directly (skipping the connections list), for shortcuts
/// that are specifically about the pump — e.g. the overview's pod section.
void openPumpPage(BuildContext context) {
  final title = Locales.string(context, 'pump.label');
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConnectionSubPage(
        title: title,
        body: const PumpBodyContent(),
        actions: const [
          PodTestBeepButton(),
          PodDeliveryLogButton(),
          DeviceHistoryButton(kind: DeviceHistoryKind.pumps),
        ],
      ),
    ),
  );
}

/// The connections page as a standalone route, with its own header + back button.
class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('connections.label'),
      ),
      body: const ConnectionsBodyContent(),
    );
  }
}

/// The overall state on top, then one plain card per connection.
class ConnectionsBodyContent extends StatelessWidget {
  const ConnectionsBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final links = DeviceLinks.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        18,
        InkSpace.panelMargin,
        24,
      ),
      children: [
        ConnectionsSummary(links: links),
        const SizedBox(height: 22),
        ConnectionRow(
          icon: PhosphorIconsBold.drop,
          labelKey: "sensor.label",
          page: const SensorBodyContent(),
          actions: const [DeviceHistoryButton(kind: DeviceHistoryKind.sensors)],
          link: links.sensor,
        ),
        const SizedBox(height: InkSpace.tileGap),
        ConnectionRow(
          icon: PhosphorIconsBold.syringe,
          labelKey: "pump.label",
          page: const PumpBodyContent(),
          actions: const [
            PodTestBeepButton(),
            PodDeliveryLogButton(),
            DeviceHistoryButton(kind: DeviceHistoryKind.pumps),
          ],
          link: links.pump,
        ),
        const SizedBox(height: InkSpace.tileGap),
        ConnectionRow(
          icon: PhosphorIconsBold.watch,
          labelKey: "google_health.label",
          page: const GoogleHealthBodyContent(),
          link: links.googleHealth,
        ),
      ],
    );
  }
}
