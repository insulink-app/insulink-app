import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../cgm/cgm_connection.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import 'libre3_pairing_fields.dart';
import 'pairing_qr_scanner.dart';
import 'sensor_type_selector.dart';

/// Box shown when no sensor is set up yet: enter the pairing code and connect.
class SensorPairingForm extends StatelessWidget {
  const SensorPairingForm({super.key, required this.controller});

  final CgmController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(scheme),
          const SizedBox(height: 16),
          SensorTypeSelector(controller: controller),
          const SizedBox(height: 16),
          ..._pairingFields(context),
        ],
      ),
    );
  }

  /// The fields for the selected sensor: the G7 pairing-code row + connect
  /// button, or the Libre 3 NFC activation fields.
  List<Widget> _pairingFields(BuildContext context) {
    if (controller.sensorType == SensorType.abbottLibre3) {
      return [Libre3PairingFields(controller: controller)];
    }
    return [
      _codeRow(context),
      const SizedBox(height: 12),
      _connectButton(),
    ];
  }

  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        _dropIcon(scheme),
        const SizedBox(width: 14),
        Expanded(child: _titles()),
      ],
    );
  }

  Widget _dropIcon(ColorScheme scheme) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.onSurface.withValues(alpha: 0.08),
      ),
      child: Icon(
        CupertinoIcons.drop,
        size: 32,
        color: scheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _titles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          'sensor.pair.title',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        LocaleText(
          'sensor.pair.hint',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _codeRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _codeField(context)),
        const SizedBox(width: 8),
        _scanButton(context),
      ],
    );
  }

  Widget _codeField(BuildContext context) {
    return TextField(
      controller: controller.code,
      decoration: InputDecoration(
        labelText: Locales.string(context, 'overview.pairing_code'),
        isDense: true,
      ),
    );
  }

  Widget _scanButton(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: Locales.string(context, 'sensor.pair.scan'),
      child: SizedBox(
        width: 52,
        height: 52,
        child: FilledButton(
          onPressed: () => _scan(context),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          ),
          child: const Icon(Icons.qr_code_scanner, size: 26),
        ),
      ),
    );
  }

  Future<void> _scan(BuildContext context) async {
    final code = await scanPairingCode(context);
    if (code != null) {
      controller.code.text = code;
    }
  }

  Widget _connectButton() {
    return FilledButton.icon(
      onPressed: controller.busy ? null : controller.start,
      icon: const Icon(Icons.bluetooth_searching, size: 20),
      label: LocaleText(
        controller.busy ? 'overview.connecting' : 'overview.connect',
      ),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }
}
