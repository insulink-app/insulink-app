import 'package:flutter/material.dart';
import 'package:insulink/src/base/device_lifespan.dart';
import 'package:insulink/src/base/device_lifespan_bar.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_reservoir_level.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:provider/provider.dart';

/// Remaining pod life and reservoir on the overview, side by side in the
/// devices panel: the same day/hour segments the sensor uses, and the reservoir
/// as a fill bar.
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        Expanded(
          child: DeviceLifespanBar(
            start: start,
            sessionLengthSec: controller.store.expiryHours * 3600,
            overview: true,
            overviewTitleKey: 'pump.label',
            pageTitleKey: 'pump.life.title',
          ),
        ),
        Expanded(
          child: PodReservoirBar(controller: controller, overview: true),
        ),
      ],
    );
  }
}

/// The reservoir under the pod's life bar, as a bar of its own, on the overview
/// and in the pump page's status box.
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
class PodReservoirBar extends StatelessWidget {
  const PodReservoirBar({
    super.key,
    required this.controller,
    this.overview = false,
  });

  final PodController controller;

  /// The overview's panel look: bold title, muted value, a thin accent fill.
  final bool overview;

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
        SizedBox(height: overview ? 8 : 6),
        overview ? _overviewBar(context) : _bar(context, scheme),
      ],
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    final level = _level;
    return Row(
      children: [
        Text(
          Locales.string(context, 'pump.status.reservoir'),
          style: overview
              ? InkText.row
              : TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
        ),
        const Spacer(),
        Text(
          _value(context),
          style: TextStyle(
            fontSize: overview ? 14 : 12,
            fontWeight: level.isLow ? FontWeight.w600 : FontWeight.normal,
            color: level.isLow
                ? context.warning
                : scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _overviewBar(BuildContext context) {
    final colors = context.ink;
    return LinearProgressIndicator(
      value: _level.fraction,
      minHeight: 6,
      borderRadius: BorderRadius.circular(3),
      color: _level.isLow ? colors.high : colors.accent,
      backgroundColor: colors.line,
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
    return Locales.string(
      context,
      'pump.bolus.units',
      params: [sportDecimal(level.units!, 2)],
    );
  }
}
