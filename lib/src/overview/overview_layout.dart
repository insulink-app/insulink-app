import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// Box layout of the overview's summary boxes — Sport metrics AND nutrition boxes
/// in one grid. Defaults to just steps + weight; everything else (including all
/// nutrition boxes) is hidden until the user enables it, so the overview stays
/// compact unless personalized.
class OverviewLayoutState extends TileLayoutState<OverviewBox> {
  static const key = 'overview.boxes_layout';
  static const _defaultHidden = {
    OverviewBox.distance,
    OverviewBox.calories,
    OverviewBox.restingHr,
    OverviewBox.sleep,
    OverviewBox.heartRate,
    OverviewBox.spo2,
    OverviewBox.carbs,
    OverviewBox.protein,
    OverviewBox.bolus,
    OverviewBox.water,
    OverviewBox.meals,
    OverviewBox.hba1c,
  };

  OverviewLayoutState(super.order, super.hidden);

  @override
  String get storageKey => key;

  @override
  bool isConditional(OverviewBox tile) => tile.isGoogleHealth;

  static Future<String> loadRaw() =>
      TileLayoutState.rawFor(key, OverviewBox.values, _defaultHidden);

  static Future<OverviewLayoutState> load() async {
    final parsed = TileLayoutState.parse(
      await TileLayoutState.read(key),
      OverviewBox.values,
      _defaultHidden,
    );
    return OverviewLayoutState(parsed.order, parsed.hidden);
  }
}
