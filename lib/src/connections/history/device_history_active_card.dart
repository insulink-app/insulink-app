import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/key_value_row.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/connections/history/device_wear_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The device in use, at the top of its history: glyph, name, "Aktiv seit
/// 30.09." in green, the time worn so far large against its rated days, the
/// bar, and the sensor code when there is one.
class DeviceHistoryActiveCard extends StatelessWidget {
  const DeviceHistoryActiveCard({
    super.key,
    required this.entry,
    required this.icon,
  });

  final DeviceHistoryEntry entry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final code = entry.sensorCode;
    return InkPanel.list(
      radius: InkRadius.tile,
      rows: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(context, colors),
              const SizedBox(height: 20),
              _worn(context, colors),
              const SizedBox(height: 12),
              DeviceWearBar(
                fraction: DeviceWear(entry).fraction,
                early: false,
                height: 8,
              ),
            ],
          ),
        ),
        if (code != null)
          KeyValueRow(
            label: Locales.string(context, 'connections.history.code_label'),
            value: code,
          ),
      ],
    );
  }

  Widget _head(BuildContext context, InsulinkColors colors) {
    final since =
        '${twoDigits(entry.start.day)}.${twoDigits(entry.start.month)}.';
    return Row(
      spacing: 14,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 20, color: colors.accent),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              LocaleText(
                entry.typeKey,
                style: InkText.rowTitle.copyWith(fontSize: 17),
              ),
              Row(
                spacing: 8,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.range,
                      shape: BoxShape.circle,
                    ),
                  ),
                  LocaleText(
                    'connections.history.active_since',
                    params: [since],
                    style: InkText.label.copyWith(color: colors.range),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "6 d 21 h" large, "von 10 d" muted, "getragen" on the right.
  Widget _worn(BuildContext context, InsulinkColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatSensorDuration(entry.worn().inSeconds),
          style: InkText.bigValue.copyWith(fontSize: 26),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: LocaleText(
            'connections.history.of_days',
            params: ['${entry.ratedDays}'],
            style: InkText.label.copyWith(color: colors.muted),
          ),
        ),
        LocaleText(
          'connections.history.worn_label',
          style: InkText.label.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}
