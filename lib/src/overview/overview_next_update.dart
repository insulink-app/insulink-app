import 'package:flutter/material.dart';
import 'package:insulink/src/overview/overview_clock_painter.dart';

/// Compact "next reading" indicator: an animated clock whose ring fills as the
/// next ~5-minute G7 reading approaches, with a short m:ss countdown. Replaces
/// the verbose last/next-update text — the absolute last-reception time now
/// lives on the sensor page.
class OverviewNextUpdate extends StatefulWidget {
  const OverviewNextUpdate({super.key, required this.lastUpdate});

  final DateTime? lastUpdate;

  @override
  State<OverviewNextUpdate> createState() => _OverviewNextUpdateState();
}

class _OverviewNextUpdateState extends State<OverviewNextUpdate>
    with SingleTickerProviderStateMixin {
  /// G7 EGV cadence — a new value roughly every 5 minutes.
  static const _intervalSec = 300;

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
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        final state = _resolve(scheme);
        return Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CustomPaint(
                painter: ClockRingPainter(
                  progress: state.progress,
                  spin: _spin.value,
                  color: state.color,
                  track: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _countdownText(state.color, state.value),
          ],
        );
      },
    );
  }

  Text _countdownText(Color color, String value) {
    return Text(
      value,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      ),
    );
  }

  /// Ring fill, colour and countdown label for the current moment. Grey + "—"
  /// without data; orange "+m:ss" once a reading is overdue; otherwise the
  /// remaining time toward the next ~5-minute slot.
  ({double progress, Color color, String value}) _resolve(ColorScheme scheme) {
    final last = widget.lastUpdate;
    if (last == null) {
      return (progress: 0, color: Colors.grey, value: '—');
    }
    final elapsed = DateTime.now().difference(last);
    final remaining = const Duration(seconds: _intervalSec) - elapsed;
    final progress = (elapsed.inSeconds / _intervalSec).clamp(0.0, 1.0);
    if (remaining.isNegative) {
      return (
        progress: progress,
        color: Colors.orangeAccent,
        value: '+${_mmss(remaining)}',
      );
    }
    return (
      progress: progress,
      color: scheme.onSurface.withValues(alpha: 0.5),
      value: _mmss(remaining),
    );
  }

  String _mmss(Duration duration) {
    final seconds = duration.inSeconds.abs();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
