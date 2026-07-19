import 'package:flutter/material.dart';

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
  });

  final List<SleepSegment> segments;

  /// Fill colour and lane label for each stage, resolved (and localized) by the
  /// caller so this widget stays context-free.
  final Map<SleepStage, Color> colors;
  final Map<SleepStage, String> labels;
  final Color axisColor;

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

  static const _laneHeight = 30.0;

  /// Stretches shorter than this are folded into the surrounding stage so the
  /// hypnogram doesn't jitter with tiny blips.
  // ponytail: 5 min heuristic — bump if the trace is still too busy.
  static const _mergeBelowMs = 5 * 60 * 1000;

  List<SleepStage> _lanesOf(List<SleepSegment> shown) {
    final present = shown.map((segment) => segment.stage).toSet();
    return [
      for (final stage in _allLanes)
        if (present.contains(stage)) stage,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shown = mergeShortSleepSegments(segments, minMs: _mergeBelowMs);
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
                width: 90,
                child: Column(
                  children: [
                    for (final stage in lanes)
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
                child: InteractiveHypnogram(
                  painter: _HypnogramPainter(
                    segments: shown,
                    lanes: lanes,
                    colors: colors,
                    start: start,
                    end: end,
                    trackColor: axisColor.withValues(alpha: 0.08),
                    riserColor: axisColor.withValues(alpha: 0.15),
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
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 70),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _hhmm(start),
                style: TextStyle(fontSize: 11, color: axisColor),
              ),
              Text(
                _hhmm(end),
                style: TextStyle(fontSize: 11, color: axisColor),
              ),
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
    required this.trackColor,
    required this.riserColor,
  });

  final List<SleepSegment> segments;
  final List<SleepStage> lanes;
  final Map<SleepStage, Color> colors;
  final int start;
  final int end;
  final Color trackColor;
  final Color riserColor;

  static const _barInset = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (end - start).toDouble();
    if (span <= 0) {
      return;
    }
    final laneHeight = size.height / lanes.length;
    _paintTracks(canvas, size, laneHeight);
    _paintRisers(canvas, size, span, laneHeight);
    _paintBars(canvas, size, span, laneHeight);
  }

  double _x(int ms, Size size, double span) => (ms - start) / span * size.width;

  double _laneCenter(int lane, double laneHeight) => (lane + 0.5) * laneHeight;

  /// A faint full-width rounded track behind each lane, like a progress bar's
  /// unfilled groove — the coloured bars sit on top of it.
  void _paintTracks(Canvas canvas, Size size, double laneHeight) {
    final track = Paint()..color = trackColor;
    for (var lane = 0; lane < lanes.length; lane++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          lane * laneHeight + _barInset,
          size.width,
          laneHeight - 2 * _barInset,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, track);
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
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = colors[segment.stage]!);
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) => old.segments != segments;
}
