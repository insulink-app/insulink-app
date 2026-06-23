import 'package:flutter/material.dart';

import '../base/confirm_dialog.dart';
import '../g7/g7_controller.dart';
import '../localization/locale_text.dart';

/// The two session buttons under the status header: end the current reading
/// session, or fully forget the sensor. Both are guarded by a confirmation
/// dialog so they can't fire by accident.
class SensorSessionControls extends StatelessWidget {
  const SensorSessionControls({super.key, required this.controller});

  final G7Controller controller;

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
      icon: const Icon(Icons.stop_circle_outlined, size: 20),
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
      icon: const Icon(Icons.link_off, size: 20),
      label: LocaleText('sensor.control.stop_sensor'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
    );
  }

  Future<void> _endSession(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      titleKey: 'sensor.control.end_session_title',
      bodyKey: 'sensor.control.end_session_body',
      confirmKey: 'sensor.control.end_session',
    );
    if (confirmed) {
      await controller.disconnect();
    }
  }

  Future<void> _stopSensor(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      titleKey: 'sensor.control.stop_sensor_title',
      bodyKey: 'sensor.control.stop_sensor_body',
      confirmKey: 'sensor.control.stop_sensor',
      destructive: true,
    );
    if (confirmed) {
      await controller.forgetSensor();
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required String confirmKey,
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        titleKey: titleKey,
        bodyKey: bodyKey,
        confirmKey: confirmKey,
        destructive: destructive,
      ),
    );
    return confirmed ?? false;
  }
}
