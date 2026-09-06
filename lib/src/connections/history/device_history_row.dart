import 'package:flutter/material.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// One device in the log: which one it was, when it ran, and how long it was
/// actually worn against how long it was rated for.
///
/// Worn time is the number worth reading. `expiresAt` says when the device WOULD
/// have run out, and a sensor pulled off on day three still carries a full
/// ten-day expiry, so the rated life alone tells the user nothing about what
/// they got out of it.
class DeviceHistoryRow extends StatelessWidget {
  const DeviceHistoryRow({super.key, required this.entry});

  final DeviceHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LocaleText(
                    entry.typeKey,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _status(context),
              ],
            ),
            const SizedBox(height: 6),
            _line(scheme, _range(context)),
            const SizedBox(height: 2),
            _line(scheme, _worn(context)),
          ],
        ),
      ),
    );
  }

  Widget _line(ColorScheme scheme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }

  /// Running, taken off by the user, or simply finished. The three are worth
  /// telling apart: a device the user discarded ended earlier than its expiry,
  /// and the worn time next to it only makes sense with that said.
  Widget _status(BuildContext context) {
    final String labelKey;
    final Color color;
    if (entry.isActive) {
      labelKey = 'connections.history.active';
      color = context.positive;
    } else if (entry.wasDiscarded) {
      labelKey = 'connections.history.discarded';
      color = context.warning;
    } else {
      labelKey = 'connections.history.ended';
      color = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LocaleText(
        labelKey,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _range(BuildContext context) {
    final endedAt = entry.endedAt;
    return Locales.string(
      context,
      'connections.history.range',
      params: [
        _day(entry.start),
        endedAt == null
            ? Locales.string(context, 'connections.history.now')
            : _day(endedAt),
      ],
    );
  }

  String _worn(BuildContext context) {
    return Locales.string(
      context,
      'connections.history.worn',
      params: [
        formatSensorDuration(entry.worn().inSeconds),
        '${entry.ratedDays}',
      ],
    );
  }

  String _day(DateTime time) =>
      '${twoDigits(time.day)}.${twoDigits(time.month)}.${twoDigits(time.year % 100)}';
}
