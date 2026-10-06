import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../cgm/cgm_connection.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locales.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/device_head.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The top of the sensor page once paired, open on the page without a card:
/// the sensor as a device head with its connection state, then its remaining
/// life. While [searching] (connected but no reading yet) the head spins.
class SensorStatusBox extends StatelessWidget {
  const SensorStatusBox({
    super.key,
    required this.controller,
    required this.searching,
  });

  final CgmController controller;
  final bool searching;

  bool get _connected => controller.connected;

  /// Best-effort session length: the sensor's reported value, else its max
  /// lifetime, else the active sensor's nominal lifetime (G7 ~10 d, Libre 3
  /// 14 d) — so the life bar always renders with the right total.
  int get _sessionLengthSec {
    final info = controller.info;
    if (info.sessionLengthSec != null) {
      return info.sessionLengthSec!;
    }
    if (info.maxLifetimeDays != null) {
      return info.maxLifetimeDays! * 86400;
    }
    return controller.sensorType.sessionLengthSec;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceHead(
          icon: PhosphorIconsBold.broadcast,
          title: Locales.string(context, _typeKey),
          status: _status(context),
          statusColor: _connected ? colors.range : colors.high,
          busy: searching,
        ),
        if (controller.sensorStart != null) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DeviceLifespanBar(
              start: controller.sensorStart!,
              sessionLengthSec: _sessionLengthSec,
            ),
          ),
        ],
      ],
    );
  }

  String get _typeKey => controller.sensorType == SensorType.abbottLibre3
      ? 'sensor.type.libre3'
      : 'sensor.type.g7';

  String get _statusKey {
    if (searching) {
      return 'sensor.status.searching';
    }
    return _connected
        ? 'sensor.status.connected'
        : 'sensor.status.disconnected';
  }

  /// Connection state, with the live value once there is one.
  String _status(BuildContext context) {
    final status = Locales.string(context, _statusKey);
    if (_connected && controller.currentMgdl != null) {
      final glucose = context.watch<ProfileGlucoseState>();
      return '$status, ${glucose.formatWithUnit(controller.currentMgdl!)}';
    }
    return status;
  }
}
