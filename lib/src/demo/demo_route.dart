import 'dart:math';

/// A route through hand-placed waypoints (latitude, longitude), smoothed into a
/// curve the way a walked or ridden path bends, and measured in metres so a
/// recording can be sampled along it at a believable pace.
class DemoRoute {
  DemoRoute(this.waypoints);

  final List<(double, double)> waypoints;

  static const int stepsPerLeg = 12;
  static const double metresPerDegree = 111320;

  /// The smoothed path: a Catmull-Rom spline through every waypoint.
  late final List<(double, double)> path = _smooth();

  late final List<double> _covered = _cumulative();

  /// Total length in metres.
  double get length => _covered.last;

  List<(double, double)> _smooth() {
    final last = waypoints.length - 1;
    return [
      for (var leg = 0; leg < last; leg++)
        for (var step = 0; step < stepsPerLeg; step++)
          _spline(
            waypoints[max(leg - 1, 0)],
            waypoints[leg],
            waypoints[leg + 1],
            waypoints[min(leg + 2, last)],
            step / stepsPerLeg,
          ),
      waypoints[last],
    ];
  }

  (double, double) _spline(
    (double, double) before,
    (double, double) from,
    (double, double) to,
    (double, double) after,
    double share,
  ) => (
    _catmullRom(before.$1, from.$1, to.$1, after.$1, share),
    _catmullRom(before.$2, from.$2, to.$2, after.$2, share),
  );

  double _catmullRom(
    double before,
    double from,
    double to,
    double after,
    double share,
  ) {
    final square = share * share;
    return 0.5 *
        (2 * from +
            (to - before) * share +
            (2 * before - 5 * from + 4 * to - after) * square +
            (3 * from - before - 3 * to + after) * square * share);
  }

  List<double> _cumulative() {
    final covered = [0.0];
    for (var index = 1; index < path.length; index++) {
      covered.add(covered.last + _metres(path[index - 1], path[index]));
    }
    return covered;
  }

  /// Flat-earth distance, exact enough over a few hundred metres.
  double _metres((double, double) from, (double, double) to) {
    final north = (to.$1 - from.$1) * metresPerDegree;
    final east = (to.$2 - from.$2) * metresPerDegree * cos(from.$1 * pi / 180);
    return sqrt(north * north + east * east);
  }

  /// The point [metres] along the path.
  (double, double) at(double metres) {
    var index = 1;
    while (index < path.length - 1 && _covered[index] < metres) {
      index++;
    }
    final legLength = _covered[index] - _covered[index - 1];
    final share = legLength == 0
        ? 0.0
        : ((metres - _covered[index - 1]) / legLength).clamp(0.0, 1.0);
    final from = path[index - 1];
    final to = path[index];
    return (
      from.$1 + (to.$1 - from.$1) * share,
      from.$2 + (to.$2 - from.$2) * share,
    );
  }
}
