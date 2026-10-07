import 'package:flutter/material.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/connections/history/device_wear_bar.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One earlier device in the log, a row of the history panel: when it ran
/// ("26.08. bis 05.09.", the year only when it is not this one), which device
/// with its code, how long it was worn, and a thin bar of worn against rated
/// time. Worn under 90 % of its rated life reads "früh entfernt" with the bar
/// in the high colour.
///
/// Worn time is the number worth reading. `expiresAt` says when the device
/// WOULD have run out, and a sensor pulled off on day three still carries a
/// full ten-day expiry, so the rated life alone says nothing about what the
/// user got out of it.
class DeviceHistoryRow extends StatelessWidget {
  const DeviceHistoryRow({super.key, required this.entry});

  final DeviceHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final wear = DeviceWear(entry);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _what(context, colors)),
              _howLong(context, colors, wear),
            ],
          ),
          DeviceWearBar(fraction: wear.fraction, early: wear.early, height: 4),
        ],
      ),
    );
  }

  Widget _what(BuildContext context, InsulinkColors colors) {
    final code = entry.sensorCode;
    final device = Locales.string(context, entry.typeKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Text(_range(context), style: InkText.row),
        Text(
          code == null
              ? device
              : '$device, ${Locales.string(context, 'connections.history.code', params: [code])}',
          style: InkText.label.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  Widget _howLong(
    BuildContext context,
    InsulinkColors colors,
    DeviceWear wear,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 3,
      children: [
        Text(formatSensorDuration(entry.worn().inSeconds), style: InkText.row),
        if (wear.early)
          LocaleText(
            'connections.history.early',
            style: InkText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.high,
            ),
          ),
      ],
    );
  }

  /// One day when it started and ended on the same day, else start "bis" end.
  String _range(BuildContext context) {
    final end = entry.endedAt ?? DateTime.now();
    final from = _day(entry.start);
    final to = _day(end);
    if (from == to) {
      return from;
    }
    return Locales.string(
      context,
      'connections.history.range',
      params: [from, to],
    );
  }

  String _day(DateTime time) {
    final day = '${twoDigits(time.day)}.${twoDigits(time.month)}.';
    return time.year == DateTime.now().year ? day : '$day${time.year}';
  }
}
