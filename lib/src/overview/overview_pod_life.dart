import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/loop/loop_overview_line.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_reservoir_level.dart';
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
        const PodLoopOverviewLine(),
      ],
    );
  }
}

/// The reservoir under the pod's life bar, as a bar of its own.
///
/// Shaped like the life bar above it — same header row, same 9 px track, same
/// rounded ends — because they answer the same question about the same pod: how
/// much is left. Continuous rather than segmented, since insulin is not counted
/// in days.
///
/// The pod cannot measure its reservoir above roughly [measurableUnits] and
/// reports a sentinel instead. That case reads as a full bar and is worded rather
/// than shown as a number: a precise figure the pod did not give would invite
/// decisions it cannot support. The same applies while no status has been read.
class OverviewPodReservoir extends StatelessWidget {
  const OverviewPodReservoir({super.key, required this.controller});

  final PodController controller;

  PodReservoirLevel get _level => PodReservoirLevel(
    hasStatus: controller.status != null,
    units: controller.status?.reservoirUnits,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme),
        const SizedBox(height: 6),
        _bar(context, scheme),
      ],
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    final level = _level;
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
            fontWeight: level.isLow ? FontWeight.w600 : FontWeight.normal,
            color: level.isLow
                ? context.warning
                : scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, ColorScheme scheme) {
    final level = _level;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 9, color: scheme.onSurface.withValues(alpha: 0.12)),
          FractionallySizedBox(
            widthFactor: level.fraction,
            child: Container(
              height: 9,
              color: level.isLow ? context.warning : scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _value(BuildContext context) {
    final level = _level;
    if (!level.hasStatus) {
      return Locales.string(context, 'pump.status.never_read');
    }
    if (level.isAboveRange) {
      return Locales.string(context, 'pump.status.reservoir_plenty');
    }
    return '${level.units!.toStringAsFixed(2)} U';
  }
}
