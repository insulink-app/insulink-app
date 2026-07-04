import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_models.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/sport_summary_tile.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:provider/provider.dart';

/// Fitbit section of the Sport home page: a header + 2×2 grid of the most
/// important metrics (resting HR, sleep, latest HR, SpO2). Renders **nothing**
/// when no Fitbit is connected, so the page looks exactly as before. Carries its
/// own bottom gap so the surrounding ListView spacing is unchanged when absent.
class FitbitSection extends StatelessWidget {
  const FitbitSection({super.key});

  @override
  Widget build(BuildContext context) {
    final fitbit = context.watch<FitbitState>();
    if (!fitbit.connected) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocaleText(
            'fitbit.label',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _row(
            SportSummaryTile(
              icon: Icons.favorite,
              labelKey: 'fitbit.resting_hr',
              value: _int(fitbit.todayRestingHr),
              unit: fitbit.todayRestingHr == null ? null : 'bpm',
            ),
            SportSummaryTile(
              icon: Icons.bedtime,
              labelKey: 'fitbit.sleep',
              value: formatSleepMinutes(fitbit.lastSleepMinutes),
            ),
          ),
          const SizedBox(height: 12),
          _row(
            SportSummaryTile(
              icon: Icons.monitor_heart,
              labelKey: 'fitbit.heart_rate',
              value: _int(fitbit.latestHr),
              unit: fitbit.latestHr == null ? null : 'bpm',
            ),
            SportSummaryTile(
              icon: Icons.air,
              labelKey: 'fitbit.spo2',
              value: _int(fitbit.latestSpo2),
              unit: fitbit.latestSpo2 == null ? null : '%',
            ),
          ),
        ],
      ),
    );
  }

  String _int(int? value) => value == null ? '–' : sportInt(value);

  Widget _row(Widget left, Widget right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }
}
