import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/pump/pump_actions.dart';
import 'package:insulink/src/pump/pump_delivery_controls.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Top-of-page box on the pump page: what the pod is doing, how much life it has
/// left, and the control that stops it.
///
/// Deliberately the same shape as [SensorStatusBox] — same rounded panel, same
/// 58 px status disc, same headline-over-subtitle, same life bar underneath — so
/// the two device pages read as one design rather than two.
class PodStatusBox extends StatelessWidget {
  const PodStatusBox({super.key, required this.controller});

  final PodController controller;

  /// Whether the pod is delivering something. The neutral accent follows this the
  /// way the sensor's follows its connection.
  bool get _delivering {
    final delivery = controller.status?.delivery;
    return delivery != null && !delivery.isSuspended;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = controller.store.activatedAt;
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
          _header(context, scheme),
          if (start != null) ...[
            const SizedBox(height: 18),
            DeviceLifespanBar(
              start: start,
              sessionLengthSec: controller.store.expiryHours * 3600,
              pageTitleKey: 'pump.life.title',
            ),
          ],
          const SizedBox(height: 16),
          // Ordered by urgency, not by frequency: the control that stops
          // delivery is first because it is the one that has to be found without
          // looking, and the one that ends the pod is last because it throws it
          // away.
          const PodStopButton(),
          const PodSilenceAlertsButton(),
          const SizedBox(height: 10),
          const PodTempBasalButton(),
          const SizedBox(height: 10),
          const PodDeactivateButton(),
          const SizedBox(height: 10),
          // Last, because it is the answer to a pod that is already gone rather
          // than a way of ending one. Deactivating is what a working pod gets.
          const PodForgetButton(),
        ],
      ),
    );
  }

  /// Neutral status accent: strong onSurface while delivering, dimmed otherwise —
  /// the same rule the sensor box uses for connected/offline.
  Color _accent(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: _delivering ? 0.8 : 0.35);

  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        _statusIcon(scheme),
        const SizedBox(width: 14),
        Expanded(child: _titles(context)),
      ],
    );
  }

  Widget _statusIcon(ColorScheme scheme) {
    final accent = _accent(scheme);
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.15),
      ),
      child: controller.isBusy
          ? _spinner(accent)
          : Icon(PhosphorIconsBold.syringe, size: 32, color: accent),
    );
  }

  Widget _spinner(Color accent) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: CircularProgressIndicator(strokeWidth: 3, color: accent),
    );
  }

  /// The pump is the headline, with what it is doing on the dimmed line below —
  /// mirroring the sensor's type-over-status pairing.
  Widget _titles(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          'pump.type.dash',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          _subtitle(context),
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// What the pod is doing, plus the reservoir when it reported a number, in the
  /// same "state · value" shape the sensor line uses for its glucose.
  String _subtitle(BuildContext context) {
    final status = controller.status;
    if (status == null) {
      return Locales.string(context, 'pump.status.never_read');
    }
    final state = Locales.string(context, _deliveryKey(status.delivery));
    final units = status.reservoirUnits;
    if (units == null) {
      return state;
    }
    return '$state · ${units.toStringAsFixed(2)} U';
  }

  String _deliveryKey(PodDeliveryStatus delivery) => switch (delivery) {
    PodDeliveryStatus.suspended => 'pump.delivery.suspended',
    PodDeliveryStatus.basalActive => 'pump.delivery.basal',
    PodDeliveryStatus.tempBasalActive => 'pump.delivery.temp_basal',
    PodDeliveryStatus.priming => 'pump.delivery.priming',
    PodDeliveryStatus.bolusAndBasalActive => 'pump.delivery.bolus_basal',
    PodDeliveryStatus.bolusAndTempBasalActive => 'pump.delivery.bolus_temp',
    PodDeliveryStatus.unknown => 'pump.delivery.unknown',
  };
}
