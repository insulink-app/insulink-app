import 'package:flutter/material.dart';
import 'package:insulink/src/connections/device_links.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/connections/status/connection_status_reader.dart';
import 'package:insulink/src/connections/status/connection_timeline.dart';
import 'package:insulink/src/connections/status/connection_timeline_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Opens the connection page. Reached from the overview's "next reading" clock,
/// which is where the user already looks when they wonder whether anything is
/// still arriving.
Future<void> openConnectionStatus(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ConnectionStatusPage()));
}

/// Sensor, pump and band side by side: when each was last heard from, and where
/// the link was down over the past day.
class ConnectionStatusPage extends StatefulWidget {
  const ConnectionStatusPage({super.key});

  @override
  State<ConnectionStatusPage> createState() => _ConnectionStatusPageState();
}

class _ConnectionStatusPageState extends State<ConnectionStatusPage> {
  List<DeviceConnection>? _devices;
  ConnectionTimeline _timeline = ConnectionTimeline(now: DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Re-reads everything against a fresh clock, so pulling to refresh moves the
  /// window rather than redrawing the one the page opened with.
  Future<void> _load() async {
    final timeline = ConnectionTimeline(now: DateTime.now());
    final devices = await ConnectionStatusReader(context, timeline).read();
    if (!mounted) {
      return;
    }
    setState(() {
      _timeline = timeline;
      _devices = devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('connections.status.title'),
      ),
      body: _devices == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _list(_devices!)),
    );
  }

  /// The window and its key, every device as a block in one panel, and the
  /// time axis under it.
  Widget _list(List<DeviceConnection> devices) {
    final links = DeviceLinks.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        16,
        InkSpace.panelMargin,
        24,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _windowNote(),
        ),
        const SizedBox(height: 14),
        InkPanel.list(
          radius: InkRadius.tile,
          rows: [
            for (final device in devices)
              ConnectionTimelineBar(
                device: device,
                timeline: _timeline,
                detailKey: _detailKey(links, device.labelKey),
              ),
          ],
        ),
        _axis(),
      ],
    );
  }

  /// The paired device for a row, read where the connections page reads it.
  String? _detailKey(DeviceLinks links, String labelKey) => switch (labelKey) {
    'sensor.label' => links.sensor.detailKey,
    'pump.label' => links.pump.detailKey,
    'google_health.label' => links.googleHealth.detailKey,
    _ => null,
  };

  /// "vor 24 h" under the strips' left end, "jetzt" under their right.
  Widget _axis() {
    final style = InkText.caption.copyWith(color: context.ink.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LocaleText(
            'connections.status.axis_start',
            params: ['${_timeline.window.inHours}'],
            style: style,
          ),
          LocaleText('overview.chart.axis_now', style: style),
        ],
      ),
    );
  }

  /// "Letzte 24 Stunden" with the key of the cells beside it: received in
  /// the accent, no reception in the neutral line colour.
  Widget _windowNote() {
    final colors = context.ink;
    final style = TextStyle(fontSize: 13, color: colors.muted);
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: LocaleText(
              'connections.status.window',
              params: ['${_timeline.window.inHours}'],
              style: InkText.rowTitle.copyWith(fontSize: 17),
            ),
          ),
        ),
        _key(colors.accent, 'connections.status.received', style),
        _key(colors.line, 'connections.status.no_reception', style),
      ],
    );
  }

  Widget _key(Color color, String labelKey, TextStyle style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        LocaleText(labelKey, style: style),
      ],
    );
  }
}
