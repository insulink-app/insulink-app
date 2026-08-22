import 'dart:ui';

/// Draws a dashed line from [from] to [to].
///
/// Shared so the two charts' dashes are the same dashes. A scrub line that runs
/// through both has to be one line, and two implementations of "dashed" would
/// give that away at the seam.
void paintDashedLine(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint,
  List<double> dash,
) {
  final total = (to - from).distance;
  if (total <= 0) {
    return;
  }
  final step = (to - from) / total;
  var drawn = 0.0;
  var on = true;
  while (drawn < total) {
    final length = (on ? dash[0] : dash[1]).clamp(0.0, total - drawn);
    if (on) {
      canvas.drawLine(from + step * drawn, from + step * (drawn + length), paint);
    }
    drawn += length;
    on = !on;
  }
}
