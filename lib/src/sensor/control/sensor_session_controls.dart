import 'package:flutter/material.dart';

import '../../alert/alert.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The two session buttons under the status header: end the current reading
/// session, or fully forget the sensor. Both are guarded by a confirmation
/// alert so they can't fire by accident.
class SensorSessionControls extends StatelessWidget {
  const SensorSessionControls({super.key, required this.controller});

  final CgmController controller;

  bool get _connected => controller.connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _endSessionButton(context, scheme),
        const SizedBox(height: 10),
        _stopSensorButton(context),
      ],
    );
  }

  Widget _endSessionButton(BuildContext context, ColorScheme scheme) {
    return FilledButton.tonalIcon(
      onPressed: _connected ? () => _endSession(context) : null,
      icon: const Icon(PhosphorIconsRegular.stopCircle, size: 20),
      label: LocaleText('sensor.control.end_session'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        foregroundColor: scheme.onSurface.withValues(alpha: 0.8),
      ),
    );
  }

  Widget _stopSensorButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: (_connected || controller.hasSensor)
          ? () => _stopSensor(context)
          : null,
      icon: const Icon(PhosphorIconsRegular.linkBreak, size: 20),
      label: LocaleText('sensor.control.stop_sensor'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
    );
  }

  void _endSession(BuildContext context) {
    _confirm(
      context,
      titleKey: 'sensor.control.end_session_title',
      bodyKey: 'sensor.control.end_session_body',
      confirmKey: 'sensor.control.end_session_confirm',
      onConfirm: () => controller.disconnect(),
    );
  }

  void _stopSensor(BuildContext context) {
    _confirm(
      context,
      titleKey: 'sensor.control.stop_sensor_title',
      bodyKey: 'sensor.control.stop_sensor_body',
      confirmKey: 'sensor.control.stop_sensor_confirm',
      destructive: true,
      onConfirm: () => controller.forgetSensor(),
    );
  }

  void _confirm(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required String confirmKey,
    required VoidCallback onConfirm,
    bool destructive = false,
  }) {
    Alert(
      icon: PhosphorIconsRegular.warning,
      iconColor: destructive ? Colors.redAccent : null,
      content: _confirmContent(titleKey, bodyKey),
      cancelButton: true,
      confirmButtonText: confirmKey,
      confirmButtonColor: destructive ? Colors.redAccent : null,
      callback: onConfirm,
    ).show(context);
  }

  Widget _confirmContent(String titleKey, String bodyKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocaleText(
            titleKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LocaleText(
            bodyKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ],
      ),
    );
  }
}
