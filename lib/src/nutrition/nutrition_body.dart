import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/nutrition/food/food_section.dart';
import 'package:insulink/src/nutrition/food/food_state.dart';
import 'package:insulink/src/nutrition/food/food_store.dart';
import 'package:insulink/src/nutrition/hydration/hydration_card.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_store.dart';
import 'package:insulink/src/nutrition/meal/meal_section.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/nutrition/meal/meal_store.dart';
import 'package:insulink/src/nutrition/nutrition_sync.dart';
import 'package:insulink/src/nutrition/stats/nutrition_stats_section.dart';
import 'package:insulink/src/request/pull_throttle.dart';
import 'package:insulink/src/request/sync_reload.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Nutrition tab. Hydration tracking up top; more sections land here later.
class NutritionBody extends AppPageBody {
  NutritionBody({super.key})
    : super(
        name: "nutrition.label",
        unselectedIcon: PhosphorIconsRegular.forkKnife,
        selectedIcon: PhosphorIconsFill.forkKnife,
      );

  @override
  Widget content(BuildContext context) {
    return const NutritionBodyContent();
  }
}

/// The page itself. Stateful (like [SportBodyContent]) so entering the tab can
/// sync the account.
class NutritionBodyContent extends StatefulWidget {
  const NutritionBodyContent({super.key});

  @override
  State<NutritionBodyContent> createState() => _NutritionBodyContentState();
}

class _NutritionBodyContentState extends State<NutritionBodyContent> {
  @override
  void initState() {
    super.initState();
    // Throttled: the body is rebuilt on every tab switch, so this fired a fresh
    // pull each visit — the burst whose reload+rebuild hitched the page a second
    // after opening it. Pull-to-refresh below stays un-throttled.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => const PullThrottle('nutrition').run(_syncAccount),
    );
  }

  /// Adopts the account's nutrition data, then re-reads it into the shared state
  /// so the page shows it. Runs on every entry to the tab (the shell rebuilds the
  /// body per tab switch, so [initState] IS "on enter") and behind the
  /// pull-to-refresh.
  ///
  /// The pull only rewrites the STORE; without the reloads below, the in-memory
  /// state would keep what it read at startup and nothing would change on screen.
  /// The reload runs only when the pull actually changed something (see
  /// [SyncReload]), so a sync that brings nothing new causes no rebuild.
  Future<void> _syncAccount() async {
    final nutrition = context.read<NutritionState>();
    final meals = context.read<MealState>();
    final food = context.read<FoodState>();
    await const SyncReload().ifChanged(NutritionSync.syncedKeys, () => NutritionSync().pull(context), (changed) async {
      if (!mounted) {
        return;
      }
      await Future.wait([
        if (NutritionStore.syncedKeys.any(changed.contains)) nutrition.reload(),
        if (MealStore.syncedKeys.any(changed.contains)) meals.reload(),
        if (FoodStore.syncedKeys.any(changed.contains)) food.reload(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _syncAccount,
      child: ListView(
        // Always scrollable/bouncy so the pull-to-refresh is reachable even when
        // the content is shorter than the screen.
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        // Few, expensive sections: keep them built across a scroll gesture
        // instead of rebuilding each one as it re-enters the viewport.
        scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
        // Bottom padding keeps the centered injection FAB (page.dart) clear.
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
        children: const [
          NutritionStatsSection(),
          SizedBox(height: 28),
          HydrationCard(),
          SizedBox(height: 28),
          MealSection(),
          SizedBox(height: 28),
          FoodSection(),
        ],
      ),
    );
  }
}
