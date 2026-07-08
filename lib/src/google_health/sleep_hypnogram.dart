import 'package:flutter/material.dart';

import 'google_health_models.dart';

/// A hypnogram: the night's sleep stages drawn on a time axis — one lane per
/// stage (awake on top, deep at the bottom, the conventional depth order) with a
/// coloured block for every stretch, so you read off when each phase began and
/// ended. Pure presentation; the segments come from the Health archive.
class SleepHypnogram extends StatelessWidget {
  const SleepHypnogram({
    super.key,
    required this.segments,
    required this.colors,
    required this.labels,
    required this.axisColor,
  });

  final List<SleepSegment> segments;

  /// Fill colour and lane label for each stage, resolved (and localized) by the
  /// caller so this widget stays context-free.
  final Map<SleepStage, Color> colors;
  final Map<SleepStage, String> labels;
  final Color axisColor;

  /// Top-to-bottom lane order: shallowest (awake) to deepest (deep).
  static const _lanes = [
    SleepStage.awake,
    SleepStage.rem,
    SleepStage.light,
    SleepStage.deep,
  ];

  static const _laneHeight = 26.0;

  @override
  Widget build(BuildContext context) {
    final start = segments.first.startMs;
    // Max end, not last.endMs — segments are sorted by START, so an
    // earlier-starting but longer stretch could otherwise clip past the axis.
    final end = segments.map((s) => s.endMs).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _lanes.length * _laneHeight,
          child: Row(
            // Stretch so the childless CustomPaint gets a TIGHT height (a
            // loosely-constrained CustomPaint without a child collapses to 0).
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    for (final stage in _lanes)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[stage] ?? '',
                            style: TextStyle(fontSize: 12, color: axisColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: CustomPaint(
                  painter: _HypnogramPainter(
                    segments: segments,
                    lanes: _lanes,
                    colors: colors,
                    start: start,
                    end: end,
                    laneColor: axisColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 70),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_hhmm(start), style: TextStyle(fontSize: 11, color: axisColor)),
              Text(_hhmm(end), style: TextStyle(fontSize: 11, color: axisColor)),
            ],
          ),
        ),
      ],
    );
  }

  String _hhmm(int ms) {
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _HypnogramPainter extends CustomPainter {
  _HypnogramPainter({
    required this.segments,
    required this.lanes,
    required this.colors,
    required this.start,
    required this.end,
    required this.laneColor,
  });

  final List<SleepSegment> segments;
  final List<SleepStage> lanes;
  final Map<SleepStage, Color> colors;
  final int start;
  final int end;
  final Color laneColor;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (end - start).toDouble();
    if (span <= 0) {
      return;
    }
    final laneHeight = size.height / lanes.length;
    final divider = Paint()..color = laneColor;
    for (var lane = 1; lane < lanes.length; lane++) {
      final y = lane * laneHeight;
      canvas.drawRect(Rect.fromLTWH(0, y - 0.5, size.width, 1), divider);
    }
    for (final segment in segments) {
      final lane = lanes.indexOf(segment.stage);
      if (lane < 0) {
        continue;
      }
      final left = (segment.startMs - start) / span * size.width;
      final right = (segment.endMs - start) / span * size.width;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, lane * laneHeight + 3, right, (lane + 1) * laneHeight - 3),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = colors[segment.stage]!);
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) => old.segments != segments;
}
