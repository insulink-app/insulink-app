import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/overview/chart/insulin_bar_chart.dart';
import 'package:insulink/src/overview/chart/insulin_chart_series.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Full-screen glucose chart, opened by tapping the overview preview. Shows the
/// interactive chart (range selector + scrub tooltip) with room to breathe, and
/// an optional meal overlay (marker + tappable details) toggled from the app bar
/// and persisted like the range. Reads the live data straight from the
/// [CgmController] so a new reading shows without reopening the page.
///
/// Underneath it, the insulin that went in over the SAME stretch of time, basal
/// and bolus told apart by colour. The window is handed down from the glucose
/// chart rather than chosen here, so panning or zooming moves both together;
/// two graphs stacked over different stretches would invite exactly the
/// comparison they cannot support.
class OverviewChartPage extends StatefulWidget {
  const OverviewChartPage({super.key});

  @override
  State<OverviewChartPage> createState() => _OverviewChartPageState();
}

class _OverviewChartPageState extends State<OverviewChartPage> {
  static const _kShowMealsKey = 'chart_show_meals';
  static const _storage = FlutterSecureStorage();

  bool _showMeals = false;

  /// The stretch the glucose chart is showing, so the insulin chart underneath
  /// covers the same one. Null until the chart has laid out once, or whenever
  /// there is no sensor session to place session seconds on a clock with.
  DateTime? _windowFrom;
  DateTime? _windowTo;

  /// Where the measured glucose stops and the forecast begins. The insulin chart
  /// stops there too, since it draws things that have happened.
  DateTime? _liveEdge;

  @override
  void initState() {
    super.initState();
    _loadShowMeals();
    _refreshInsulin();
  }

  /// Re-reads the pod store so the insulin chart shows what the background
  /// service has booked since this isolate last looked.
  ///
  /// The store serves its getters from an in-memory cache that is PER ISOLATE,
  /// and basal is booked in the service. Without this the chart would quietly
  /// show whatever was known when the app started. Cheap enough for a page
  /// open, and no radio is involved.
  Future<void> _refreshInsulin() async {
    await context.read<PodController>().store.reload();
    if (mounted) {
      setState(() {});
    }
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

  /// Follows the glucose chart's window, so panning or zooming it moves the
  /// insulin underneath with it.
  void _adoptWindow(DateTime from, DateTime to, DateTime liveEdge) {
    if (_windowFrom == from && _windowTo == to && _liveEdge == liveEdge) {
      return;
    }
    setState(() {
      _windowFrom = from;
      _windowTo = to;
      _liveEdge = liveEdge;
    });
  }

  /// The insulin that went in over the same stretch. Nothing is drawn until the
  /// window is known: a chart over a guessed stretch of time, sitting under one
  /// over a real stretch, would be read as if the two lined up.
  Widget _insulin(List<Meal> meals) {
    final from = _windowFrom;
    final to = _windowTo;
    if (from == null || to == null) {
      return const SizedBox.shrink();
    }
    return InsulinBarChart(
      series: InsulinChartSeries(
        basalHours: context.watch<PodController>().store.basalHours,
        meals: meals,
        from: from,
        to: to,
        liveEdge: _liveEdge,
      ),
    );
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
      // Glucose above, the insulin that moved it below, sharing one window. The
      // split leaves the glucose chart nearly the room it had while giving the
      // insulin enough height for a bolus and an hour of basal to be told apart.
      body: Padding(
        // Room under the insulin chart so its legend is not pressed against the
        // bottom edge of the screen.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Column(
          children: [
            Expanded(
              flex: 60,
              child: OverviewChart(
                byTime: controller.chartHistory,
                sensorStart: controller.sensorStart,
                navigable: true,
                showMeals: _showMeals,
                meals: meals,
                onWindowChanged: _adoptWindow,
              ),
            ),
            // No gap and no divider between them: they share one time axis, and
            // anything drawn in between reads as a border around two separate
            // pictures rather than one stacked pair.
            Expanded(flex: 25, child: _insulin(meals)),
          ],
        ),
      ),
    );
  }
}
