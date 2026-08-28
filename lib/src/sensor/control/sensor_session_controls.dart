import 'package:flutter/material.dart';
import 'package:insulink/src/base/action_buttons.dart';

import '../../alert/alert.dart';
import '../../cgm/cgm_controller.dart';
import '../../injection/biometric_auth.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// The two session buttons under the status header: end the current reading
/// session, or fully forget the sensor. Both are guarded by a confirmation
/// alert so they can't fire by accident.
class SensorSessionControls extends StatelessWidget {
  const SensorSessionControls({super.key, required this.controller});

  final CgmController controller;

  bool get _connected => controller.connected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecondaryActionButton(
          labelKey: 'sensor.control.end_session',
          icon: PhosphorIconsBold.stopCircle,
          onPressed: _connected ? () => _endSession(context) : null,
        ),
        const SizedBox(height: 10),
        DangerActionButton(
          labelKey: 'sensor.control.stop_sensor',
          icon: PhosphorIconsBold.linkBreak,
          onPressed: (_connected || controller.hasSensor)
              ? () => _stopSensor(context)
              : null,
        ),
      ],
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
      onConfirm: () => _authThenForget(context),
    );
  }

  /// Forgetting a sensor permanently deletes its key and history, so after the
  /// confirmation it requires the device fingerprint (PIN fallback when none is
  /// enrolled). A failed/declined check leaves the pairing untouched.
  Future<void> _authThenForget(BuildContext context) async {
    final ok = await BiometricAuth().confirm(
      Locales.string(context, 'sensor.control.forget_auth_reason'),
      allowDeviceCredential: true,
    );
    if (ok) {
      await controller.forgetSensor();
    }
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
      icon: PhosphorIconsBold.warning,
      iconColor: destructive ? context.danger : null,
      content: _confirmContent(titleKey, bodyKey),
      cancelButton: true,
      confirmButtonText: confirmKey,
      confirmButtonColor: destructive
          ? Theme.of(context).colorScheme.error
          : null,
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
