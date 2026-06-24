import 'package:flutter/material.dart';

import '../localization/locale_text.dart';
import '../localization/locales.dart';

/// Sensor durability shown as one rectangle per day: the remaining days are
/// filled with the accent colour, elapsed days are greyed out.
class SensorLifeBar extends StatelessWidget {
  const SensorLifeBar({
    super.key,
    required this.start,
    required this.sessionLengthSec,
  });

  final DateTime start;
  final int sessionLengthSec;

  /// Whole rated days. The reported session length includes a ~12 h grace
  /// period past the rated lifetime (10 d → 907200 s = 10.5 d), so floor — not
  /// round — to avoid showing an extra day (a 10-day sensor as "11").
  int get _totalDays => (sessionLengthSec / 86400).floor().clamp(1, 30);

  int get _remainingSecs =>
      sessionLengthSec - DateTime.now().difference(start).inSeconds;

  /// Days still left, rounding a partial day UP so today still counts as left.
  int get _filledDays => (_remainingSecs / 86400).ceil().clamp(0, _totalDays);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme),
        const SizedBox(height: 6),
        _dayBar(scheme),
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
    final text = expired
        ? Locales.string(context, 'sensor.value.expired')
        : Locales.string(
            context,
            'sensor.life.remaining',
            params: ['$_filledDays'],
          );
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: expired ? Colors.redAccent : scheme.onSurface,
      ),
    );
  }

  Widget _dayBar(ColorScheme scheme) {
    return Row(
      children: [
        for (var day = 0; day < _totalDays; day++) ...[
          if (day > 0) const SizedBox(width: 4),
          Expanded(child: _daySegment(scheme, filled: day < _filledDays)),
        ],
      ],
    );
  }

  Widget _daySegment(ColorScheme scheme, {required bool filled}) {
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
