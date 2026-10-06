import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_head.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/overview_pod_life.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The top of the pump page, open on the page without a card: the pod as a
/// device head with what it is doing, then its remaining life and its reservoir.
///
/// The same shape as the sensor page's top, so the two device pages read as one
/// design. The controls that change delivery sit in their own section below.
class PodHeadSection extends StatelessWidget {
  const PodHeadSection({super.key, required this.controller});

  final PodController controller;

  /// Whether the pod is delivering something; the status dot follows it.
  bool get _delivering {
    final delivery = controller.status?.delivery;
    return delivery != null && !delivery.isSuspended;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final start = controller.store.activatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceHead(
          icon: PhosphorIconsBold.syringe,
          title: Locales.string(context, 'pump.type.dash'),
          status: _status(context),
          statusColor: _delivering ? colors.range : colors.high,
          busy: controller.isBusy,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (start != null) ...[
                DeviceLifespanBar(
                  start: start,
                  sessionLengthSec: controller.store.expiryHours * 3600,
                  pageTitleKey: 'pump.life.title',
                ),
                const SizedBox(height: 18),
              ],
              PodReservoirBar(controller: controller),
            ],
          ),
        ),
      ],
    );
  }

  /// What the pod is doing, or that it has not been read yet.
  String _status(BuildContext context) {
    final status = controller.status;
    if (status == null) {
      return Locales.string(context, 'pump.status.never_read');
    }
    return Locales.string(context, _deliveryKey(status.delivery));
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
