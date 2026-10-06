import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/overview/chart/meal_label_rows.dart';

const _rows = MealLabelRows();

({double left, double right}) _label(double left, [double width = 56]) =>
    (left: left, right: left + width);

/// Meals minutes apart put their carb labels on top of each other, and dropping
/// one would hide a meal the chart still draws a line for. So they stack, by
/// their real width in pixels, and only as far as they have to.
void main() {
  test('a single meal sits in the top row', () {
    expect(_rows.assign([_label(40)]), [0]);
  });

  test('labels with room between them all sit in the top row', () {
    expect(_rows.assign([_label(0), _label(80), _label(160)]), [0, 0, 0]);
  });

  test('two labels that would touch step down', () {
    expect(_rows.assign([_label(100), _label(130)]), [0, 1]);
  });

  test('a gap smaller than the spacing still counts as touching', () {
    expect(_rows.assign([_label(0), _label(60)]), [0, 1]);
    expect(_rows.assign([_label(0), _label(62)]), [0, 0]);
  });

  test('a label goes back up as soon as the top row has room', () {
    expect(_rows.assign([_label(0), _label(20), _label(70)]), [0, 1, 0]);
  });

  test('a full stack puts the next label where the overlap is least', () {
    expect(_rows.assign([_label(0), _label(10), _label(20), _label(30)]), [
      0,
      1,
      2,
      0,
    ]);
  });

  test('the order the meals come in does not matter', () {
    expect(_rows.assign([_label(130), _label(100)]), [1, 0]);
  });

  test('no meals, no rows', () {
    expect(_rows.assign(const []), isEmpty);
  });
}
