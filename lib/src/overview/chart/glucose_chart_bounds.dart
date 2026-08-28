/// Where the Y axis starts and stops, in mg/dL, for a set of readings.
///
/// A fixed 0 to 300 wastes most of the picture: nobody's day reaches either end,
/// so the curve is squeezed into the middle third while the empty space above and
/// below is drawn at full size. Fitting the axis to the readings gives that space
/// back to the line.
///
/// Deliberately NOT fitted tightly. Both ends round outwards to the next fifty,
/// so the axis lands on numbers a reader can measure against and, more
/// importantly, stops the whole chart rescaling every time one reading moves. An
/// axis that follows the data exactly turns a five point wobble into a chart that
/// jumps.
class GlucoseChartBounds {
  const GlucoseChartBounds(this.values);

  final Iterable<int> values;

  /// Around 50 when nothing dips lower, else rounded down to the next fifty, so
  /// an ordinary day starts at 50 rather than wasting the space down to zero.
  int get minMgdl {
    if (values.isEmpty) {
      return _restingMin;
    }
    final low = values.reduce((first, second) => first < second ? first : second);
    final floor = (low / _step).floor() * _step;
    return floor > _restingMin ? _restingMin : floor;
  }

  /// The peak plus a little headroom, rounded up to the next fifty, and never
  /// below 200: a flat day still has to show where the high range begins.
  int get maxMgdl {
    if (values.isEmpty) {
      return _restingMax;
    }
    final peak = values.reduce((first, second) => first > second ? first : second);
    final rounded = ((peak + _headroom) / _step).ceil() * _step;
    return rounded < _restingMax ? _restingMax : rounded;
  }

  static const int _step = 50;
  static const int _restingMin = 50;
  static const int _restingMax = 200;

  /// Room above the highest reading so the peak is not drawn touching the top
  /// edge, where it reads as clipped rather than as the maximum.
  static const int _headroom = 20;
}
