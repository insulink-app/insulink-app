import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_activation_page.dart';
import 'package:insulink/src/pump/pod_temp_basal_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_delivery_gate.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Starts an activation. Disabled while the delivery gate is locked, because
/// activating a pod primes it — it delivers insulin and binds the pod to this app
/// for good.
class PodActivateButton extends StatelessWidget {
  const PodActivateButton({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<PodDeliveryGate>();
    final controller = context.watch<PodController>();
    final unlocked = gate.allowsDelivery && !controller.isBusy;
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: unlocked ? () => openPodActivation(context) : null,
      icon: const Icon(PhosphorIconsBold.plus, size: 20),
      label: LocaleText('pump.action.activate'),
    );
  }
}

/// The pod-maintenance controls: read the status, acknowledge alerts, and end the
/// pod's life. None of these start a delivery, so none consult the gate.
class PodMaintenanceActions extends StatelessWidget {
  const PodMaintenanceActions({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final hasAlerts = controller.status?.activeAlerts.isNotEmpty ?? false;
    final temporary = controller.activeTemporaryBasal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (temporary == null)
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : () => openTempBasalSheet(context),
            icon: const Icon(PhosphorIconsBold.timer, size: 18),
            label: LocaleText('pump.temp.set'),
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: context.warning),
            onPressed: controller.isBusy ? null : controller.cancelTemporaryBasal,
            icon: const Icon(PhosphorIconsBold.prohibit, size: 18),
            label: Text(
              Locales.string(context, 'pump.temp.running')
                  .replaceFirst('#', temporary.unitsPerHour.toStringAsFixed(2)),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: controller.isBusy ? null : controller.refresh,
          icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
          label: LocaleText('pump.action.refresh'),
        ),
        if (hasAlerts) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: controller.isBusy ? null : controller.silenceAlerts,
            icon: const Icon(PhosphorIconsBold.bellSlash, size: 18),
            label: LocaleText('pump.action.silence'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: context.danger),
          onPressed: controller.isBusy ? null : () => _confirmDeactivate(context, controller),
          icon: const Icon(PhosphorIconsBold.trash, size: 18),
          label: LocaleText('pump.action.deactivate'),
        ),
      ],
    );
  }

  void _confirmDeactivate(BuildContext context, PodController controller) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocaleText('pump.action.deactivate',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LocaleText('pump.stop.body',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
      cancelButton: true,
      confirmButtonText: 'pump.action.deactivate',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: controller.deactivatePod,
    ).show(context);
  }
}
