import 'package:flutter/material.dart';
import 'package:insulink/src/base/circle_icon_button.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

import 'heart_rate_zones.dart';

/// Bottom sheet to adjust the two pulse-zone thresholds (green→orange,
/// orange→red) with – / + steppers. Returns the saved [HeartRateZones], or null
/// if dismissed.
Future<HeartRateZones?> showHeartRateZonesSheet(
  BuildContext context,
  HeartRateZones current,
) {
  return showModalBottomSheet<HeartRateZones>(
    context: context,
    showDragHandle: true,
    builder: (_) => _HeartRateZonesSheet(current: current),
  );
}

class _HeartRateZonesSheet extends StatefulWidget {
  const _HeartRateZonesSheet({required this.current});

  final HeartRateZones current;

  @override
  State<_HeartRateZonesSheet> createState() => _HeartRateZonesSheetState();
}

class _HeartRateZonesSheetState extends State<_HeartRateZonesSheet> {
  late HeartRateZones _zones = widget.current;

  static const _step = 5;

  void _bump({int? elevated, int? high}) {
    setState(() => _zones = _zones.copyWith(elevated: elevated, high: high));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocaleText(
            'google_health.hr_zones.title',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _row(
            'google_health.hr_zones.elevated',
            HeartRateZones.orange,
            _zones.elevated,
            (delta) => _bump(elevated: _zones.elevated + delta),
          ),
          const SizedBox(height: 16),
          _row(
            'google_health.hr_zones.high',
            HeartRateZones.red,
            _zones.high,
            (delta) => _bump(high: _zones.high + delta),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                _zones.save();
                Navigator.pop(context, _zones);
              },
              child: LocaleText('google_health.hr_zones.save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String labelKey, Color accent, int value, void Function(int) step) {
    return Row(
      children: [
        Expanded(
          child: Text(
            Locales.string(context, labelKey),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        CircleIconButton(
          icon: Icons.remove,
          accent: accent,
          onTap: () => step(-_step),
        ),
        SizedBox(
          width: 84,
          child: Text(
            '$value bpm',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        CircleIconButton(
          icon: Icons.add,
          accent: accent,
          onTap: () => step(_step),
        ),
      ],
    );
  }
}
