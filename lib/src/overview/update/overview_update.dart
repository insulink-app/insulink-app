import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/overview/update/overview_clock_painter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Compact "next reading" indicator: an animated clock whose ring fills as the
/// next reading approaches (cadence per [intervalSec] — ~5 min on the G7, ~1 min
/// on the Libre 3), with a short m:ss countdown. Replaces
/// the verbose last/next-update text — the absolute last-reception time now
/// lives on the sensor page.
class OverviewUpdate extends StatefulWidget {
  const OverviewUpdate({
    super.key,
    required this.lastUpdate,
    required this.intervalSec,
  });

  final DateTime? lastUpdate;

  /// Nominal seconds between readings for the active sensor (see
  /// [SensorType.readingIntervalSec]).
  final int intervalSec;

  @override
  State<OverviewUpdate> createState() => _OverviewUpdateState();
}

class _OverviewUpdateState extends State<OverviewUpdate>
    with SingleTickerProviderStateMixin {
  /// Drives the rotating clock hands so the indicator always looks "alive";
  /// also serves as the once-per-frame tick that refreshes the countdown.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        final state = _resolve(colors);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 26,
              child: CustomPaint(
                painter: ClockRingPainter(
                  progress: state.progress,
                  spin: _spin.value,
                  color: state.ring,
                  track: colors.line,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _countdownText(state.text, state.value),
          ],
        );
      },
    );
  }

  Text _countdownText(Color color, String value) {
    return Text(
      value,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
    );
  }

  /// Ring fill, colours and countdown label for the current moment. Muted "—"
  /// without data; amber "+m:ss" once a reading is overdue; otherwise the
  /// remaining time toward the next slot, with the ring in the accent.
  ({double progress, Color ring, Color text, String value}) _resolve(
    InsulinkColors colors,
  ) {
    final last = widget.lastUpdate;
    if (last == null) {
      return (progress: 0, ring: colors.muted, text: colors.muted, value: '—');
    }
    final elapsed = DateTime.now().difference(last);
    final remaining = Duration(seconds: widget.intervalSec) - elapsed;
    final progress = (elapsed.inSeconds / widget.intervalSec).clamp(0.0, 1.0);
    if (remaining.isNegative) {
      final overdue = '+${_mmss(remaining)}';
      return (
        progress: progress,
        ring: colors.high,
        text: colors.high,
        value: overdue,
      );
    }
    return (
      progress: progress,
      ring: colors.accent,
      text: colors.muted,
      value: _mmss(remaining),
    );
  }

  String _mmss(Duration duration) {
    final seconds = duration.inSeconds.abs();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
