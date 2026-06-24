import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../g7/g7_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';

/// Box shown when no sensor is set up yet: enter the pairing code and connect.
class SensorPairingForm extends StatelessWidget {
  const SensorPairingForm({super.key, required this.controller});

  final G7Controller controller;

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
          _codeField(context),
          const SizedBox(height: 12),
          _connectButton(),
        ],
      ),
    );
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

  Widget _codeField(BuildContext context) {
    return TextField(
      controller: controller.code,
      decoration: InputDecoration(
        labelText: Locales.string(context, 'overview.pairing_code'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
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
