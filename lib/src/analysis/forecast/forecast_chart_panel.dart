import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/chart_key_entry.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy.dart';
import 'package:insulink/src/analysis/forecast/forecast_accuracy_chart.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// "Measured" against "forecast" in a panel, with the key above the chart.
class ForecastChartPanel extends StatelessWidget {
  const ForecastChartPanel({
    super.key,
    required this.score,
    required this.glucose,
  });

  final ForecastScore score;
  final ProfileGlucoseState glucose;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return InkPanel(
      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              spacing: 18,
              children: [
                ChartKeyEntry(
                  color: colors.text,
                  labelKey: 'analysis.forecast.measured',
                ),
                ChartKeyEntry(
                  color: colors.accent,
                  labelKey: 'analysis.forecast.predicted',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 220,
            child: ForecastAccuracyChart(
              outcomes: score.outcomes,
              glucose: glucose,
            ),
          ),
        ],
      ),
    );
  }
}
