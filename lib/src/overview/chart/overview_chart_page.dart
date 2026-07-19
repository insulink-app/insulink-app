import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Full-screen glucose chart, opened by tapping the overview preview. Shows the
/// interactive chart (range selector + scrub tooltip) with room to breathe, and
/// an optional meal overlay (marker + tappable details) toggled from the app bar
/// and persisted like the range. Reads the live data straight from the
/// [CgmController] so a new reading shows without reopening the page.
class OverviewChartPage extends StatefulWidget {
  const OverviewChartPage({super.key});

  @override
  State<OverviewChartPage> createState() => _OverviewChartPageState();
}

class _OverviewChartPageState extends State<OverviewChartPage> {
  static const _kShowMealsKey = 'chart_show_meals';
  static const _storage = FlutterSecureStorage();

  bool _showMeals = false;

  @override
  void initState() {
    super.initState();
    _loadShowMeals();
  }

  Future<void> _loadShowMeals() async {
    final stored = await _storage.read(key: _kShowMealsKey);
    if (mounted && stored == 'true') {
      setState(() => _showMeals = true);
    }
  }

  /// Persist locally AND mirror to the account, so the choice is a stored setting
  /// that roams across devices like the other display preferences.
  Future<void> _toggleMeals() async {
    setState(() => _showMeals = !_showMeals);
    await _storage.write(key: _kShowMealsKey, value: '$_showMeals');
    if (mounted) {
      await ProfileSettings().push(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final controller = context.watch<CgmController>();
    return Scaffold(
      appBar: AppBar(
        title: LocaleText('overview.glucose'),
        actions: [
          IconButton(
            isSelected: _showMeals,
            tooltip: Locales.string(context, 'overview.chart.show_meals'),
            icon: const Icon(PhosphorIconsRegular.forkKnife),
            selectedIcon: const Icon(PhosphorIconsFill.forkKnife),
            onPressed: _toggleMeals,
          ),
        ],
      ),
      // The full chart (all Y labels + grid lines) sits near the top and takes
      // about two-thirds of the height rather than the whole page.
      body: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: 0.65,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: OverviewChart(
              byTime: controller.chartHistory,
              sensorStart: controller.sensorStart,
              navigable: true,
              showMeals: _showMeals,
              meals: meals,
            ),
          ),
        ),
      ),
    );
  }
}
