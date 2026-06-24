import 'package:flutter/material.dart';

import '../../localization/locale_text.dart';
import '../../localization/locales.dart';

/// Sensor durability shown as one rectangle per remaining unit: one per day
/// normally, switching to one per HOUR over the final 24 h so the last day
/// stays meaningful. Remaining units are filled with the accent colour, elapsed
/// ones greyed out.
class SensorLifeBar extends StatelessWidget {
  const SensorLifeBar({
    super.key,
    required this.start,
    required this.sessionLengthSec,
  });

  final DateTime start;
  final int sessionLengthSec;

  int get _remainingSecs =>
      sessionLengthSec - DateTime.now().difference(start).inSeconds;

  /// Switch to hour-granularity once a single day or less remains (and the
  /// sensor hasn't expired) — the final day matters most, so show it in hours.
  bool get _hoursMode => _remainingSecs > 0 && _remainingSecs <= 86400;

  /// Whole rated days. The reported session length includes a ~12 h grace
  /// period past the rated lifetime (10 d → 907200 s = 10.5 d), so floor — not
  /// round — to avoid showing an extra day (a 10-day sensor as "11").
  int get _totalDays => (sessionLengthSec / 86400).floor().clamp(1, 30);

  /// Total bars to draw: 24 (one per hour) in the final day, else one per day.
  int get _totalSegments => _hoursMode ? 24 : _totalDays;

  /// Filled bars, rounding a partial unit UP so the current hour/day still
  /// counts as remaining.
  int get _filledSegments => _hoursMode
      ? (_remainingSecs / 3600).ceil().clamp(0, 24)
      : (_remainingSecs / 86400).ceil().clamp(0, _totalDays);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme),
        const SizedBox(height: 6),
        _segmentBar(scheme),
      ],
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        LocaleText(
          'sensor.life.title',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const Spacer(),
        _remainingLabel(context, scheme),
      ],
    );
  }

  Widget _remainingLabel(BuildContext context, ColorScheme scheme) {
    final expired = _remainingSecs <= 0;
    return Text(
      _remainingText(context, expired),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: expired ? Colors.redAccent : scheme.onSurface,
      ),
    );
  }

  String _remainingText(BuildContext context, bool expired) {
    if (expired) {
      return Locales.string(context, 'sensor.value.expired');
    }
    final key = _hoursMode
        ? 'sensor.life.remaining_hours'
        : 'sensor.life.remaining';
    return Locales.string(context, key, params: ['$_filledSegments']);
  }

  Widget _segmentBar(ColorScheme scheme) {
    final gap = _hoursMode ? 2.0 : 4.0;
    return Row(
      children: [
        for (var index = 0; index < _totalSegments; index++) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(child: _segment(scheme, filled: index < _filledSegments)),
        ],
      ],
    );
  }

  Widget _segment(ColorScheme scheme, {required bool filled}) {
    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: filled
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
