import 'package:flutter/material.dart';
import 'package:insulink/src/fitbit/fitbit_models.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Read-only list of the latest Fitbit metrics (device page, when connected):
/// label on the left, value on the right.
class FitbitMetricList extends StatelessWidget {
  const FitbitMetricList({super.key, required this.fitbit});

  final FitbitState fitbit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row('fitbit.resting_hr', _fmt(fitbit.todayRestingHr, 'bpm')),
        _row('fitbit.heart_rate', _fmt(fitbit.latestHr, 'bpm')),
        _row('fitbit.spo2', _fmt(fitbit.latestSpo2, '%')),
        _row('fitbit.sleep', formatSleepMinutes(fitbit.lastSleepMinutes)),
      ],
    );
  }

  String _fmt(int? value, String unit) => value == null ? '–' : '$value $unit';

  Widget _row(String labelKey, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LocaleText(labelKey, style: TextStyle(color: Colors.grey[500])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
