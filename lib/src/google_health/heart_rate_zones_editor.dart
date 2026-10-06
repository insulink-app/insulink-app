import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/glucose_stepper_row.dart';
import 'package:insulink/src/sport/sport_editable_number.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Edits the two pulse-zone thresholds (green→orange "elevated", orange→red
/// "high") with the same stepper rows the profile uses elsewhere, for the
/// profile "Pulse zones" topic. [HeartRateZones] self-persists to secure storage
/// (no provider), so this loads it on init and saves after every change; the
/// pulse page re-reads it on open.
class HeartRateZonesEditor extends StatefulWidget {
  const HeartRateZonesEditor({super.key});

  @override
  State<HeartRateZonesEditor> createState() => _HeartRateZonesEditorState();
}

class _HeartRateZonesEditorState extends State<HeartRateZonesEditor> {
  static const _step = 5;

  HeartRateZones? _zones;

  @override
  void initState() {
    super.initState();
    HeartRateZones.load().then((zones) {
      if (mounted) {
        setState(() => _zones = zones);
      }
    });
  }

  void _update(HeartRateZones next) {
    setState(() => _zones = next);
    next.save();
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zones;
    if (zones == null) {
      return const SizedBox(height: 96);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          'google_health.hr_zones.elevated',
          zones.elevated,
          context.ink.pulseHigh,
          (value) => _update(zones.copyWith(elevated: value)),
        ),
        const SizedBox(height: 16),
        _row(
          'google_health.hr_zones.high',
          zones.high,
          context.ink.pulseHigh,
          (value) => _update(zones.copyWith(high: value)),
        ),
        const SizedBox(height: 12),
        LocaleText(
          'google_health.hr_zones.note',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _row(
    String labelKey,
    int value,
    Color zoneColor,
    void Function(int) set,
  ) {
    return GlucoseStepperRow(
      labelKey: labelKey,
      valueText: '$value bpm',
      accent: zoneColor,
      onMinus: () => set(value - _step),
      onPlus: () => set(value + _step),
      valueChild: SportEditableNumber(
        valueText: '$value bpm',
        initial: value.toDouble(),
        min: HeartRateZones.minBpm.toDouble(),
        max: HeartRateZones.maxBpm.toDouble(),
        onSubmit: (entered) => set(entered.round()),
      ),
    );
  }
}
