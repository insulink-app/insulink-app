import 'package:flutter/material.dart';
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

  Widget _list(List<DeviceConnection> devices) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _windowNote(),
        const SizedBox(height: 16),
        for (final device in devices)
          ConnectionTimelineBar(device: device, timeline: _timeline),
      ],
    );
  }

  Widget _windowNote() {
    return LocaleText(
      'connections.status.window',
      params: ['${_timeline.window.inHours}'],
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
