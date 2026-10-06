/// Which stacking row each meal's carb label belongs in, so labels of meals
/// logged close together do not print on top of each other.
///
/// The labels hang off vertical lines at fixed x positions, and nothing stops
/// two of those from being minutes apart: a meal and its correction, or a snack
/// during dinner. Dropping one would hide a meal the chart draws a line for, so
/// they are stacked downward instead and all of them stay.
///
/// Works on the labels' measured extents in pixels: it used to guess "too
/// close" as a share of the window, which was a fifth of a label's real width,
/// so labels still overlapped.
class MealLabelRows {
  const MealLabelRows({this.gap = 6, this.rows = 3});

  /// Space kept between two labels in one row.
  final double gap;

  /// How far the labels stack. When every row is taken, a label goes where the
  /// row ends furthest to the left, so the overlap is the smallest possible.
  final int rows;

  /// A row per label, in the order given. The labels are placed left to right
  /// whatever order they come in; each takes the topmost row it fits in, so a
  /// lone meal never sits low for no reason.
  List<int> assign(List<({double left, double right})> labels) {
    final order = [for (var index = 0; index < labels.length; index++) index]
      ..sort(
        (first, second) => labels[first].left.compareTo(labels[second].left),
      );
    final rowEnds = List<double>.filled(rows, double.negativeInfinity);
    final assigned = List<int>.filled(labels.length, 0);
    for (final index in order) {
      final label = labels[index];
      var row = rowEnds.indexWhere((end) => end + gap <= label.left);
      if (row < 0) {
        row = _leastTaken(rowEnds);
      }
      rowEnds[row] = label.right;
      assigned[index] = row;
    }
    return assigned;
  }

  int _leastTaken(List<double> rowEnds) {
    var best = 0;
    for (var row = 1; row < rowEnds.length; row++) {
      if (rowEnds[row] < rowEnds[best]) {
        best = row;
      }
    }
    return best;
  }
}
