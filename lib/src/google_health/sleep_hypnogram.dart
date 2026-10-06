import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

import 'google_health_models.dart';
import 'sleep_hypnogram_tooltip.dart';

/// Folds stretches shorter than [minMs] into the preceding stage, then coalesces
/// adjacent same-stage stretches — so a night's hypnogram reads as a few clear
/// phases instead of many tiny jumps. Display-only; segment totals are computed
/// separately from the raw data and are unaffected.
List<SleepSegment> mergeShortSleepSegments(
  List<SleepSegment> segments, {
  required int minMs,
}) {
  if (segments.length < 2) {
    return segments;
  }
  final absorbed = <SleepSegment>[];
  for (final segment in segments) {
    final isShort = segment.endMs - segment.startMs < minMs;
    if (isShort && absorbed.isNotEmpty) {
      absorbed.add(_extendedTo(absorbed.removeLast(), segment.endMs));
    } else {
      absorbed.add(segment);
    }
  }
  final merged = <SleepSegment>[];
  for (final segment in absorbed) {
    if (merged.isNotEmpty && merged.last.stage == segment.stage) {
      merged.add(_extendedTo(merged.removeLast(), segment.endMs));
    } else {
      merged.add(segment);
    }
  }
  return merged;
}

SleepSegment _extendedTo(SleepSegment segment, int endMs) =>
    SleepSegment(stage: segment.stage, startMs: segment.startMs, endMs: endMs);

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
    required this.lineColor,
  });

  final List<SleepSegment> segments;

  /// Fill colour and lane label for each stage, resolved (and localized) by the
  /// caller so this widget stays context-free.
  final Map<SleepStage, Color> colors;
  final Map<SleepStage, String> labels;
  final Color axisColor;

  /// The faint line through each lane and the risers between lanes.
  final Color lineColor;

  /// Top-to-bottom lane order: shallowest (awake) to deepest (deep). Only lanes
  /// with segments this night are shown, so a stage with no time (e.g. restless)
  /// drops out instead of leaving an empty row.
  static const _allLanes = [
    SleepStage.awake,
    SleepStage.restless,
    SleepStage.rem,
    SleepStage.light,
    SleepStage.deep,
  ];

  static const _laneHeight = 33.0;

  /// Width of the lane labels on the left.
  static const _labelWidth = 54.0;

  /// Clock labels under the plot land on every second full hour.
  static const _tickHours = 2;

  /// Stretches shorter than this are folded into the surrounding stage so the
  /// hypnogram doesn't jitter with tiny blips.
  // ponytail: 5 min heuristic — bump if the trace is still too busy.
  static const mergeBelowMs = 5 * 60 * 1000;

  List<SleepStage> _lanesOf(List<SleepSegment> shown) {
    final present = shown.map((segment) => segment.stage).toSet();
    return [
      for (final stage in _allLanes)
        if (present.contains(stage)) stage,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shown = mergeShortSleepSegments(segments, minMs: mergeBelowMs);
    final lanes = _lanesOf(shown);
    final start = shown.first.startMs;
    // Max end, not last.endMs — segments are sorted by START, so an
    // earlier-starting but longer stretch could otherwise clip past the axis.
    final end = shown.map((s) => s.endMs).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: lanes.length * _laneHeight,
          child: Row(
            // Stretch so the childless CustomPaint gets a TIGHT height (a
            // loosely-constrained CustomPaint without a child collapses to 0).
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Column(
                  children: [
                    for (final stage in lanes)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[stage] ?? '',
                            style: InkText.axis.copyWith(
                              fontSize: 12,
                              color: axisColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveHypnogram(
                  painter: _HypnogramPainter(
                    segments: shown,
                    lanes: lanes,
                    colors: colors,
                    start: start,
                    end: end,
                    lineColor: lineColor,
                    riserColor: axisColor.withValues(alpha: 0.35),
                  ),
                  segments: shown,
                  colors: colors,
                  labels: labels,
                  start: start,
                  end: end,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: _labelWidth),
          child: SizedBox(height: 16, child: _ticks(start, end)),
        ),
      ],
    );
  }

  /// "00:00", "02:00", … on the full hours inside the night, each centred on
  /// its time and kept inside the plot at both ends.
  Widget _ticks(int start, int end) {
    final style = InkText.axis.copyWith(fontSize: 12, color: axisColor);
    final first = DateTime.fromMillisecondsSinceEpoch(start);
    var tick = DateTime(first.year, first.month, first.day, first.hour + 1);
    while (tick.hour % _tickHours != 0) {
      tick = tick.add(const Duration(hours: 1));
    }
    final ticks = <int>[];
    for (
      ;
      tick.millisecondsSinceEpoch < end;
      tick = tick.add(const Duration(hours: _tickHours))
    ) {
      ticks.add(tick.millisecondsSinceEpoch);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final ms in ticks)
            Positioned(
              left: (ms - start) / (end - start) * constraints.maxWidth - 18,
              width: 36,
              child: Text(_hhmm(ms), style: style, textAlign: TextAlign.center),
            ),
        ],
      ),
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
    required this.lineColor,
    required this.riserColor,
  });

  final List<SleepSegment> segments;
  final List<SleepStage> lanes;
  final Map<SleepStage, Color> colors;
  final int start;
  final int end;
  final Color lineColor;
  final Color riserColor;

  /// Blocks are 16 px high inside their 33 px lane.
  static const _barInset = 8.5;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (end - start).toDouble();
    if (span <= 0) {
      return;
    }
    final laneHeight = size.height / lanes.length;
    _paintLaneLines(canvas, size, laneHeight);
    _paintRisers(canvas, size, span, laneHeight);
    _paintBars(canvas, size, span, laneHeight);
  }

  double _x(int ms, Size size, double span) => (ms - start) / span * size.width;

  double _laneCenter(int lane, double laneHeight) => (lane + 0.5) * laneHeight;

  /// A faint line through the middle of each lane, so a block reads as sitting
  /// on its stage's row.
  void _paintLaneLines(Canvas canvas, Size size, double laneHeight) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var lane = 0; lane < lanes.length; lane++) {
      final y = _laneCenter(lane, laneHeight);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Thin vertical steps at each stage change, connecting the two lanes so the
  /// night reads as one continuous stepped trace (drawn under the bars).
  void _paintRisers(Canvas canvas, Size size, double span, double laneHeight) {
    final riser = Paint()
      ..color = riserColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < segments.length; i++) {
      final previous = lanes.indexOf(segments[i - 1].stage);
      final current = lanes.indexOf(segments[i].stage);
      if (previous < 0 || current < 0 || previous == current) {
        continue;
      }
      final x = _x(segments[i].startMs, size, span);
      canvas.drawLine(
        Offset(x, _laneCenter(previous, laneHeight)),
        Offset(x, _laneCenter(current, laneHeight)),
        riser,
      );
    }
  }

  void _paintBars(Canvas canvas, Size size, double span, double laneHeight) {
    for (final segment in segments) {
      final lane = lanes.indexOf(segment.stage);
      if (lane < 0) {
        continue;
      }
      final left = _x(segment.startMs, size, span);
      final right = _x(segment.endMs, size, span);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left,
          lane * laneHeight + _barInset,
          right,
          (lane + 1) * laneHeight - _barInset,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = colors[segment.stage]!);
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) => old.segments != segments;
}
