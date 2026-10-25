import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// How well the phone hears the band, in three steps a person can act on.
///
/// ponytail: three fixed lines on the usual BLE scale; tune them if the Air's
/// radio reads differently.
enum BandSignal {
  good,
  medium,
  poor;

  /// The step for a signal of [rssi] dBm.
  static BandSignal of(int rssi) => switch (rssi) {
    >= -70 => good,
    >= -82 => medium,
    _ => poor,
  };

  /// How many of the three bars are lit.
  int get bars => values.length - index;

  /// "Verbindung gut", the status line beside the bars.
  String get localeKey => 'google_health.band.signal.$name';

  Color color(InsulinkColors colors) => switch (this) {
    good => colors.range,
    medium => colors.high,
    poor => colors.low,
  };
}

/// Three rising rounded bars at the head of the band's status line, in place
/// of the dot: as many lit as [signal] has, in its colour, the rest dimmed,
/// the way a phone's status bar shows its own signal. A long press shows the
/// exact dBm.
class BandSignalBars extends StatelessWidget {
  const BandSignalBars({super.key, required this.signal, required this.rssi});

  final BandSignal signal;
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Tooltip(
      message: '$rssi dBm',
      child: SizedBox(
        width: 14,
        height: 13,
        child: CustomPaint(
          painter: _SignalBarsPainter(
            signal.bars,
            signal.color(colors),
            colors.line,
          ),
        ),
      ),
    );
  }
}

/// Three rising pill-shaped bars, the first [filled] in [on], the rest in [off].
class _SignalBarsPainter extends CustomPainter {
  const _SignalBarsPainter(this.filled, this.on, this.off);

  static const _count = 3;

  final int filled;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.16;
    final width = (size.width - gap * (_count - 1)) / _count;
    for (var index = 0; index < _count; index++) {
      final height = size.height * (0.45 + 0.275 * index);
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          index * (width + gap),
          size.height - height,
          width,
          height,
        ),
        Radius.circular(width / 2),
      );
      canvas.drawRRect(bar, Paint()..color = index < filled ? on : off);
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) =>
      old.filled != filled || old.on != on || old.off != off;
}
