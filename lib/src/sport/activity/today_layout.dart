import 'package:insulink/src/sport/activity/tile_layout_state.dart';

export 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// Box layout of the Sport "Today" grid. Defaults: the four activity boxes plus
/// resting HR, sleep and the live heart rate (SpO2 hidden until the user enables it).
class TodayLayoutState extends TileLayoutState<TodayTile> {
  static const key = 'sport.today_layout';
  static const _defaultHidden = {TodayTile.spo2, TodayTile.hba1c};

  TodayLayoutState(super.order, super.hidden);

  @override
  String get storageKey => key;

  @override
  bool isConditional(TodayTile tile) => tile.isGoogleHealth;

  static Future<String> loadRaw() =>
      TileLayoutState.rawFor(key, TodayTile.values, _defaultHidden);

  static Future<TodayLayoutState> load() async {
    final parsed = TileLayoutState.parse(
      await TileLayoutState.read(key),
      TodayTile.values,
      _defaultHidden,
    );
    return TodayLayoutState(parsed.order, parsed.hidden);
  }
}
