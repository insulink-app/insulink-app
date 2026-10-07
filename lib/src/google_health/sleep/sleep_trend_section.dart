import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_bar_chart.dart';
import 'package:insulink/src/sport/sport_range_selector.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// How the nights have gone over the chosen window: the range picker, and in a
/// panel the nights as bars in hours with the average as a dashed line and the
/// latest night in the full accent.
class SleepTrendSection extends StatelessWidget {
  const SleepTrendSection({
    super.key,
    required this.range,
    required this.onRange,
    required this.nights,
    required this.averageMinutes,
  });

  final SportRange range;
  final ValueChanged<SportRange> onRange;

  /// The nights inside [range], ascending.
  final List<GoogleHealthDay> nights;
  final int averageMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SportRangeSelector(value: range, onChanged: onRange),
        const SizedBox(height: 10),
        InkPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _averageKey(context, colors),
              const SizedBox(height: 14),
              SizedBox(height: 178, child: _chart(colors)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _averageKey(BuildContext context, InsulinkColors colors) {
    return Row(
      spacing: 8,
      children: [
        CustomPaint(
          size: const Size(16, 2),
          painter: _DashPainter(colors.text.withValues(alpha: 0.6)),
        ),
        Text(
          Locales.string(
            context,
            'google_health.sleep_page.average',
            params: [formatSleepDuration(averageMinutes)],
          ),
          style: InkText.caption.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  Widget _chart(InsulinkColors colors) {
    int minutes(GoogleHealthDay night) =>
        night.value(GoogleHealthMetric.sleep)!.round();
    return ActivityBarChart<GoogleHealthDay>(
      days: nights,
      date: (night) => night.date,
      value: (night) => minutes(night) / 60,
      label: (night) => formatSleepDuration(minutes(night)),
      color: colors.accent,
      average: averageMinutes / 60,
      highlightLast: true,
      axisSuffix: ' h',
    );
  }
}

/// The dashed swatch in front of "Average", drawn like the line it explains.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 3).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
