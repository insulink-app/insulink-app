/// Which stacking row each meal's carb label belongs in, so two meals logged
/// close together do not print their labels on top of each other.
///
/// The labels hang off vertical lines at fixed x positions, and nothing stops
/// two of those from being minutes apart: a meal and its correction, or a snack
/// during dinner. Their labels then overlap into an unreadable smear. Dropping
/// one would hide a meal the chart is drawing a line for, so they are stacked
/// downward instead and all of them stay.
class MealLabelRows {
  const MealLabelRows({required this.spanX, this.rows = 3});

  /// The x range the chart is showing, in the same units the marker x values are
  /// in. The threshold is a fraction of it, because what counts as "too close"
  /// is a distance on screen, not a distance in time: the same two meals collide
  /// on a 24-hour window and are far apart on a 3-hour one.
  final double spanX;

  /// How far the labels stack before starting again at the top. Three is two
  /// label heights of travel, which is as far as a label can drop and still
  /// clearly belong to its own line.
  final int rows;

  /// The share of the visible span within which two labels would touch.
  ///
  /// ponytail: a fraction of the width rather than a measured text width, which
  /// this layer does not have. Six percent is about one label at the widths the
  /// chart is actually drawn at; if labels ever get much wider (a four-digit carb
  /// count), measure instead of guessing.
  static const double _crowdedFraction = 0.06;

  double get threshold => spanX * _crowdedFraction;

  /// A row per x, in the order given. Ascending x is assumed; the markers come
  /// off a time-ordered meal list.
  ///
  /// A marker far enough from the one before it resets to the top row, so a
  /// lone meal never sits low for no reason and a cluster steps down through the
  /// rows in the order it happened.
  List<int> assign(List<double> xs) {
    final assigned = <int>[];
    double? previous;
    var row = 0;
    for (final x in xs) {
      if (previous == null || (x - previous).abs() > threshold) {
        row = 0;
      } else {
        row = (row + 1) % rows;
      }
      assigned.add(row);
      previous = x;
    }
    return assigned;
  }
}
