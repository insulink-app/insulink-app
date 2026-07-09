import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';

/// Full-screen glucose chart, opened by tapping the overview preview. Shows the
/// interactive chart (range selector + scrub tooltip) with room to breathe.
class OverviewChartPage extends StatelessWidget {
  const OverviewChartPage({
    super.key,
    required this.byTime,
    this.sensorStart,
  });

  final SplayTreeMap<int, int> byTime;
  final DateTime? sensorStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: LocaleText('overview.glucose')),
      // The full chart (all Y labels + grid lines) sits near the top and takes
      // about two-thirds of the height rather than the whole page.
      body: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: 0.65,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OverviewChart(
              byTime: byTime,
              sensorStart: sensorStart,
              navigable: true,
            ),
          ),
        ),
      ),
    );
  }
}
