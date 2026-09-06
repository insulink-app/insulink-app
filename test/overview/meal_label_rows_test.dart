import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/meal_label_rows.dart';

/// A 24-hour window, so the crowding threshold is about 1.4 hours.
const _rows = MealLabelRows(spanX: 24);

/// Meals minutes apart put their carb labels on top of each other, and dropping
/// one would hide a meal the chart still draws a line for. So they stack, and
/// the stacking has to reset as soon as there is room again.
void main() {
  test('a single meal sits in the top row', () {
    expect(_rows.assign([6]), [0]);
  });

  test('meals far apart all sit in the top row', () {
    expect(_rows.assign([2, 8, 14, 20]), [0, 0, 0, 0]);
  });

  test('a crowded pair steps down', () {
    expect(_rows.assign([6, 6.5]), [0, 1]);
  });

  test('a cluster steps down in the order it happened', () {
    expect(_rows.assign([6, 6.3, 6.6, 6.9]), [0, 1, 2, 0]);
  });

  test('room after a cluster resets to the top', () {
    expect(_rows.assign([6, 6.3, 18, 18.4]), [0, 1, 0, 1]);
  });

  test('just past the threshold is room, just inside it is not', () {
    expect(_rows.assign([6, 6 + _rows.threshold * 1.01]), [0, 0]);
    expect(_rows.assign([6, 6 + _rows.threshold * 0.99]), [0, 1]);
  });

  test('the threshold scales with the window, not with the clock', () {
    const narrow = MealLabelRows(spanX: 3);
    // 20 minutes apart: crowded on a 24 h window, roomy on a 3 h one.
    expect(_rows.assign([6, 6.33]), [0, 1]);
    expect(narrow.assign([6, 6.33]), [0, 0]);
  });

  test('no meals, no rows', () {
    expect(_rows.assign(const []), isEmpty);
  });
}
