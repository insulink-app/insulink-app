import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_head.dart';
import 'package:insulink/src/google_health/band/band_battery_bar.dart';
import 'package:insulink/src/google_health/band/band_battery_state.dart';
import 'package:insulink/src/google_health/band/band_signal.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/google_health_status_box.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The Google Health device page (screen 12), shaped like the pump page: the
/// device head named after the band, its status led by signal bars, the
/// battery bar, then the latest values, the band's details and the disconnect row,
/// or, while not connected, why and the button that connects. Connecting grants Health
/// Connect read access; the band itself is paired in the Google Health app.
/// Pulling the page down re-imports the metrics and re-reads the band battery.
class GoogleHealthBodyContent extends StatelessWidget {
  const GoogleHealthBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<GoogleHealthState>();
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          8,
          InkSpace.panelMargin,
          32,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _head(context, health),
                const SizedBox(height: 24),
                const BandBatteryBar(),
              ],
            ),
          ),
          GoogleHealthStatusBox(health: health),
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final battery = context.read<BandBatteryState>();
    await context.read<GoogleHealthState>().refreshIfConnected(force: true);
    await battery.refresh();
  }

  /// Named after the band once one is paired, like the pump page names the
  /// pod. While the band's live link reports a signal, the status line says
  /// how good the connection is, led by signal bars in place of the dot;
  /// otherwise the dot and where the data comes from.
  Widget _head(BuildContext context, GoogleHealthState health) {
    final colors = context.ink;
    final failed = health.connectFailure != null;
    final paired = context.watch<BandBatteryState>().paired;
    final connection = health.connected
        ? 'google_health.status.connected'
        : 'google_health.status.disconnected';
    final rssi = health.connected ? health.bandRssi : null;
    final signal = rssi == null ? null : BandSignal.of(rssi);
    return DeviceHead(
      icon: PhosphorIconsBold.watch,
      title: Locales.string(
        context,
        paired ? 'google_health.band._' : connection,
      ),
      status: Locales.string(
        context,
        signal?.localeKey ?? _statusKey(health, paired, connection),
      ),
      statusColor: health.connected
          ? colors.range
          : (failed ? colors.low : colors.muted),
      busy: health.busy,
      statusLeading: signal == null
          ? null
          : BandSignalBars(signal: signal, rssi: rssi!),
    );
  }

  String _statusKey(GoogleHealthState health, bool paired, String connection) {
    return paired && !health.connected
        ? connection
        : 'google_health.status.source';
  }
}
