import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Read-only list of the latest Google Health metrics (device page, when connected):
/// label on the left, value on the right.
class GoogleHealthMetricList extends StatelessWidget {
  const GoogleHealthMetricList({super.key, required this.health});

  final GoogleHealthState health;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row('google_health.resting_hr', _fmt(health.todayRestingHr, 'bpm')),
        _row('google_health.heart_rate', _fmt(health.latestHr, 'bpm')),
        _row('google_health.spo2', _fmt(health.latestSpo2, '%')),
        _row('google_health.respiratory_rate',
            _fmt(health.latestRespiratoryRate, 'rpm')),
        _row('google_health.sleep', formatSleepMinutes(health.lastSleepMinutes)),
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
