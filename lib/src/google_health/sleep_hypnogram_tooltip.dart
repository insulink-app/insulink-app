import 'package:flutter/material.dart';

import 'google_health_models.dart';

/// Wraps the hypnogram [painter] in pointer tracking so hovering (desktop/web)
/// or dragging (touch) over a stretch surfaces a tooltip with that stage's
/// phase, duration and clock time. Pure overlay; the painter is unchanged.
class InteractiveHypnogram extends StatefulWidget {
  const InteractiveHypnogram({
    super.key,
    required this.painter,
    required this.segments,
    required this.colors,
    required this.labels,
    required this.start,
    required this.end,
  });

  final CustomPainter painter;
  final List<SleepSegment> segments;
  final Map<SleepStage, Color> colors;
  final Map<SleepStage, String> labels;
  final int start;
  final int end;

  @override
  State<InteractiveHypnogram> createState() => _InteractiveHypnogramState();
}

class _InteractiveHypnogramState extends State<InteractiveHypnogram> {
  SleepSegment? _active;
  Offset _pointer = Offset.zero;

  static const _tooltipWidth = 150.0;

  /// Maps a horizontal position to the stretch under it, using the same
  /// time→x mapping as the painter (inverted).
  SleepSegment? _segmentAt(double localX, double width) {
    final span = (widget.end - widget.start).toDouble();
    if (span <= 0 || width <= 0) {
      return null;
    }
    final ms = widget.start + (localX / width * span).round();
    for (final segment in widget.segments) {
      if (ms >= segment.startMs && ms < segment.endMs) {
        return segment;
      }
    }
    return null;
  }

  void _update(Offset local, double width) {
    setState(() {
      _pointer = local;
      _active = _segmentAt(local.dx, width);
    });
  }

  void _clear() {
    setState(() => _active = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          onHover: (event) => _update(event.localPosition, width),
          onExit: (_) => _clear(),
          child: GestureDetector(
            onTapDown: (details) => _update(details.localPosition, width),
            onTapUp: (_) => _clear(),
            onTapCancel: _clear,
            onHorizontalDragUpdate: (details) =>
                _update(details.localPosition, width),
            onHorizontalDragEnd: (_) => _clear(),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: widget.painter)),
                if (_active != null) _tooltip(context, width, _active!),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tooltip(BuildContext context, double width, SleepSegment segment) {
    final left = (_pointer.dx - _tooltipWidth / 2)
        .clamp(0.0, (width - _tooltipWidth).clamp(0.0, width));
    return Positioned(
      left: left,
      top: 0,
      child: IgnorePointer(
        child: _TooltipCard(
          color: widget.colors[segment.stage]!,
          label: widget.labels[segment.stage] ?? '',
          segment: segment,
        ),
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.color,
    required this.label,
    required this.segment,
  });

  final Color color;
  final String label;
  final SleepSegment segment;

  String _hhmm(int ms) {
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = (segment.endMs - segment.startMs) ~/ 60000;
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_hhmm(segment.startMs)}–${_hhmm(segment.endMs)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          Text(
            formatSleepMinutes(minutes),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
