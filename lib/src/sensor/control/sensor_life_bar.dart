import 'package:flutter/material.dart';

import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import 'sensor_lifespan.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final life = SensorLifespan(
      start: start,
      sessionLengthSec: sessionLengthSec,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme, life),
        const SizedBox(height: 6),
        _segmentBar(scheme, life),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    SensorLifespan life,
  ) {
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
        _remainingLabel(context, scheme, life),
      ],
    );
  }

  Widget _remainingLabel(
    BuildContext context,
    ColorScheme scheme,
    SensorLifespan life,
  ) {
    return Text(
      _remainingText(context, life),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: life.expired
            ? Colors.redAccent
            : life.inGrace
            ? Colors.orangeAccent
            : scheme.onSurface,
      ),
    );
  }

  String _remainingText(BuildContext context, SensorLifespan life) {
    if (life.expired) {
      return Locales.string(context, 'sensor.value.expired');
    }
    if (life.inGrace) {
      return Locales.string(
        context,
        'sensor.life.grace',
        params: ['${life.graceHoursLeft}'],
      );
    }
    final key = life.hoursMode
        ? 'sensor.life.remaining_hours'
        : 'sensor.life.remaining';
    return Locales.string(context, key, params: ['${life.filledSegments}']);
  }

  Widget _segmentBar(ColorScheme scheme, SensorLifespan life) {
    final gap = life.hoursMode ? 2.0 : 4.0;
    return Row(
      children: [
        for (var index = 0; index < life.totalSegments; index++) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(
            child: _segment(scheme, filled: index < life.filledSegments),
          ),
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
