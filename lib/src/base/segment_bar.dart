import 'package:flutter/material.dart';

/// One piece of a [SegmentBar]: its colour and its share of the width.
class BarSegment {
  const BarSegment({required this.color, required this.weight});

  final Color color;
  final double weight;
}

/// A row of rounded segments with a gap between them: the range scale, the
/// time-in-range bar and the remaining days of a sensor or pod.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.segments,
    this.height = 6,
    this.gap = 4,
  });

  /// [total] equal segments, the first [filled] in [fill], the rest in [empty].
  factory SegmentBar.count({
    required int total,
    required int filled,
    required Color fill,
    required Color empty,
    double gap = 4,
  }) {
    return SegmentBar(
      gap: gap,
      segments: [
        for (var index = 0; index < total; index++)
          BarSegment(color: index < filled ? fill : empty, weight: 1),
      ],
    );
  }

  final List<BarSegment> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((segment) => segment.weight > 0).toList();
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0) SizedBox(width: gap),
            Expanded(
              flex: (visible[index].weight * 1000).round().clamp(1, 1 << 30),
              child: _piece(visible[index].color),
            ),
          ],
        ],
      ),
    );
  }

  Widget _piece(Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
