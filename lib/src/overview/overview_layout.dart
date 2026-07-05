import 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// Box layout of the overview's summary boxes. Defaults to just steps + weight
/// (the overview's previous fixed boxes); everything else is hidden until the
/// user enables it, so the overview stays compact unless personalized.
class OverviewLayoutState extends TileLayoutState {
  static const key = 'overview.boxes_layout';
  static const _defaultHidden = {
    TodayTile.distance,
    TodayTile.calories,
    TodayTile.restingHr,
    TodayTile.sleep,
    TodayTile.heartRate,
    TodayTile.spo2,
  };

  OverviewLayoutState(super.order, super.hidden);

  @override
  String get storageKey => key;

  static Future<String> loadRaw() => TileLayoutState.rawFor(key, _defaultHidden);

  static Future<OverviewLayoutState> load() async {
    final parsed = TileLayoutState.parse(
      await TileLayoutState.read(key),
      _defaultHidden,
    );
    return OverviewLayoutState(parsed.order, parsed.hidden);
  }
}
