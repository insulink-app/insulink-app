import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/chart/glucose_chart_bounds.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';
import 'package:insulink/src/overview/chart/overview_chart_page.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The overview's 24 h glucose chart: a tappable "Glucose · 24 h ›" row over a
/// non-interactive chart as wide as the panels below it; the title row keeps
/// the glucose area's inset. Tapping either opens the full-screen chart page.
class OverviewChartPreview extends StatelessWidget {
  const OverviewChartPreview({
    super.key,
    required this.controller,
    required this.byTime,
  });

  final CgmController controller;

  /// The chart series for this build, read once by the overview and handed
  /// down (every `byTime` read rebuilds it out of the archive).
  final SplayTreeMap<int, int> byTime;

  @override
  Widget build(BuildContext context) {
    final bounds = GlucoseChartBounds(byTime.values);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OverviewChartPage()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context),
          SizedBox(
            height: math.max(200.0, (bounds.maxMgdl - bounds.minMgdl) * 0.9),
            child: OverviewChart(
              byTime: byTime,
              sensorStart: controller.sensorStart,
              preview: true,
              minYmgdl: bounds.minMgdl,
              maxYmgdl: bounds.maxMgdl,
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final muted = context.ink.muted;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            Locales.string(context, 'overview.glucose'),
            style: InkText.section,
          ),
          const Spacer(),
          Text(
            Locales.string(context, 'overview.chart_window'),
            style: InkText.label.copyWith(color: muted),
          ),
          const SizedBox(width: 2),
          Icon(PhosphorIconsRegular.caretRight, size: 18, color: muted),
        ],
      ),
    );
  }
}
