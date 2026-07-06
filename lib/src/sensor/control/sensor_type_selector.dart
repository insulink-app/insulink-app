import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../cgm/cgm_connection.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locales.dart';

/// Segmented control for the CGM the pairing form should set up (Dexcom G7 vs
/// FreeStyle Libre 3). The selected segment slides/fades in via an
/// [AnimatedContainer]. Persists via [CgmController.setSensorType].
class SensorTypeSelector extends StatelessWidget {
  const SensorTypeSelector({super.key, required this.controller});

  final CgmController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              context,
              SensorType.dexcomG7,
              'sensor.type.g7',
              CupertinoIcons.drop_fill,
            ),
          ),
          Expanded(
            child: _segment(
              context,
              SensorType.abbottLibre3,
              'sensor.type.libre3',
              Icons.sensors_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    SensorType type,
    String labelKey,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller.sensorType == type;
    final foreground = selected
        ? scheme.onPrimary
        : scheme.onSurface.withValues(alpha: 0.65);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: selected ? null : () => controller.setSensorType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                Locales.string(context, labelKey),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
