import 'package:flutter/material.dart';

import '../../cgm/cgm_connection.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locales.dart';

/// Two-way toggle for the CGM the pairing form should set up (Dexcom G7 vs
/// FreeStyle Libre 3). Persists via [CgmController.setSensorType].
class SensorTypeSelector extends StatelessWidget {
  const SensorTypeSelector({super.key, required this.controller});

  final CgmController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _button(context, SensorType.dexcomG7, 'sensor.type.g7')),
        const SizedBox(width: 8),
        Expanded(
          child: _button(context, SensorType.abbottLibre3, 'sensor.type.libre3'),
        ),
      ],
    );
  }

  Widget _button(BuildContext context, SensorType type, String labelKey) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller.sensorType == type;
    return FilledButton(
      onPressed: selected ? null : () => controller.setSensorType(type),
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.08),
        foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
      ),
      child: Text(Locales.string(context, labelKey)),
    );
  }
}
