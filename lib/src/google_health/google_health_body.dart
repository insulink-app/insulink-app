import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_head.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/google_health_status_box.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The Google Health device page (screen 12): the device head open on the
/// page, then the latest values and the disconnect row, or, while not
/// connected, why and the button that connects. Connecting grants Health
/// Connect read access; the band itself is paired in the Google Health app.
class GoogleHealthBodyContent extends StatelessWidget {
  const GoogleHealthBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final health = context.watch<GoogleHealthState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        8,
        InkSpace.panelMargin,
        32,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _head(context, health),
        ),
        GoogleHealthStatusBox(health: health),
      ],
    );
  }

  Widget _head(BuildContext context, GoogleHealthState health) {
    final colors = context.ink;
    final failed = health.connectFailure != null;
    return DeviceHead(
      icon: PhosphorIconsBold.watch,
      title: Locales.string(
        context,
        health.connected
            ? 'google_health.status.connected'
            : 'google_health.status.disconnected',
      ),
      status: Locales.string(context, 'google_health.status.source'),
      statusColor: health.connected
          ? colors.range
          : (failed ? colors.low : colors.muted),
      busy: health.busy,
    );
  }
}
