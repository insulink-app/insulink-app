import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// The standing notice that delivery is locked, with the switch that unlocks it.
///
/// Shown as a persistent part of the page rather than a one-time dialog: it is a
/// standing condition of this build, not an event, and the user should be able to
/// see at a glance whether the lock is on.
class PodGateCard extends StatelessWidget {
  const PodGateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<PodDeliveryGate>();
    final scheme = Theme.of(context).colorScheme;
    final accent = gate.allowsDelivery ? context.danger : context.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(accent),
          const SizedBox(height: 6),
          LocaleText(
            gate.allowsDelivery ? 'pump.gate.warning' : 'pump.gate.body',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: gate.allowsDelivery,
            onChanged: (value) => gate.setEnabled(value),
            title: LocaleText(
              'pump.gate.enable',
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Color accent) {
    return Row(
      children: [
        Icon(PhosphorIconsFill.warning, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: LocaleText(
            'pump.gate._',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}
