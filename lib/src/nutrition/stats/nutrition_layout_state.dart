import 'package:insulink/src/nutrition/stats/nutrition_tile.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// Box layout of the nutrition stats grid: which boxes are shown and their order.
/// Fat and kcal are opt-in, every other box is visible by default. Same persistence + settings-sync machinery as
/// the Sport "Today" grid ([TileLayoutState]).
class NutritionLayoutState extends TileLayoutState<NutritionTile> {
  static const key = 'nutrition.stats_layout';
  static const _defaultHidden = {NutritionTile.kcal, NutritionTile.fat};

  NutritionLayoutState(super.order, super.hidden);

  @override
  String get storageKey => key;

  static Future<String> loadRaw() =>
      TileLayoutState.rawFor(key, NutritionTile.values, _defaultHidden);

  static Future<NutritionLayoutState> load() async {
    final parsed = TileLayoutState.parse(
      await TileLayoutState.read(key),
      NutritionTile.values,
      _defaultHidden,
    );
    return NutritionLayoutState(parsed.order, parsed.hidden);
  }
}
