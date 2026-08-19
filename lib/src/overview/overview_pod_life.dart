import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:provider/provider.dart';

/// Remaining pod life and reservoir on the overview — the same day/hour segment
/// bar the sensor uses, with the reservoir added underneath.
///
/// Renders nothing while no pod is paired, so a user without one sees no empty
/// section.
class OverviewPodLife extends StatelessWidget {
  const OverviewPodLife({super.key});

  /// A pod runs 72 rated hours plus up to 8 hours of grace before it stops on its
  /// own. Feeding the full 80 h to [DeviceLifespan] makes it show three rated days
  /// and treat the tail as grace, which is what the pod actually does.
  static const int podLifetimeSeconds = 80 * 3600;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PodController>();
    final start = controller.store.activatedAt;
    if (!controller.hasPod || start == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeviceLifespanBar(
          start: start,
          sessionLengthSec: controller.store.expiryHours * 3600,
          overview: true,
          overviewTitleKey: 'pump.label',
          pageTitleKey: 'pump.life.title',
        ),
        const SizedBox(height: 8),
        OverviewPodReservoir(controller: controller),
      ],
    );
  }
}

/// The reservoir line under the pod's life bar.
///
/// The pod cannot measure its reservoir above roughly 50 U and reports a sentinel
/// instead, so that case is worded rather than shown as a number — a precise
/// figure the pod did not give would invite decisions it cannot support. The same
/// applies while no status has been read yet.
class OverviewPodReservoir extends StatelessWidget {
  const OverviewPodReservoir({super.key, required this.controller});

  /// Units at or below which the reservoir is called out in the warning colour.
  static const double lowUnits = 10.0;

  final PodController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          Locales.string(context, 'pump.status.reservoir'),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const Spacer(),
        Text(
          _value(context),
          style: TextStyle(
            fontSize: 12,
            fontWeight: _isLow ? FontWeight.w600 : FontWeight.normal,
            color: _isLow
                ? context.warning
                : scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  double? get _units => controller.status?.reservoirUnits;

  bool get _isLow {
    final units = _units;
    return units != null && units <= lowUnits;
  }

  String _value(BuildContext context) {
    final status = controller.status;
    if (status == null) {
      return Locales.string(context, 'pump.status.never_read');
    }
    final units = _units;
    if (units == null) {
      return Locales.string(context, 'pump.status.reservoir_plenty');
    }
    return '${units.toStringAsFixed(2)} U';
  }
}
