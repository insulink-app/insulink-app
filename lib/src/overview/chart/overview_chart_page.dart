import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/meal/meal.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/overview/chart/chart_sync.dart';
import 'package:insulink/src/overview/chart/glucose_chart_bounds.dart';
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

  /// What the two charts share so they behave as one: the window, the axis
  /// labels, the scrub, and where a pinch is applied.
  final ChartSync _sync = ChartSync();

  /// The two-finger gesture, measured over the WHOLE pair rather than over the
  /// glucose chart alone, so pinching and dragging on the insulin underneath
  /// moves the same window. Mirrors the pointer bookkeeping fl_chart's own
  /// scrubbing needs left alone.
  final Map<int, Offset> _pinchPointers = {};
  double? _pinchLastDistance;
  Offset? _pinchLastFocal;
  final GlobalKey _pairKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _sync.addListener(_onSyncChanged);
    _loadShowMeals();
    _refreshInsulin();
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    _sync.dispose();
    super.dispose();
  }

  /// Rebuilds so the insulin chart is handed a series over the CURRENT window.
  ///
  /// The window is read here, in the page's build, but the page listened to
  /// nothing: panning or zooming the glucose chart moved its own window and left
  /// the insulin chart holding the series built for the previous one, which is
  /// the pair drifting apart. A scrub is not a window change and is already
  /// handled by the chart that draws it, so it is skipped.
  void _onSyncChanged() {
    final from = _sync.from;
    final to = _sync.to;
    if (!mounted || (from == _shownFrom && to == _shownTo)) {
      return;
    }
    setState(() {
      _shownFrom = from;
      _shownTo = to;
    });
  }

  DateTime? _shownFrom;
  DateTime? _shownTo;

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

  void _onPointerDown(PointerDownEvent event) {
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length == 2) {
      _pinchLastDistance = _pinchDistance();
      _pinchLastFocal = _pinchFocal();
    }
    _sync.gesturing = _pinchPointers.length > 1;
  }

  /// Hands a two-finger move to whoever owns the range, as a scale and a
  /// sideways travel. Anywhere over the pair counts, which is what makes the two
  /// charts zoom and scroll as one surface.
  void _onPointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) {
      return;
    }
    _pinchPointers[event.pointer] = event.position;
    final last = _pinchLastDistance;
    if (_pinchPointers.length != 2 || last == null) {
      return;
    }
    final distance = _pinchDistance();
    if (distance <= 0) {
      return;
    }
    final box = _pairKey.currentContext?.findRenderObject() as RenderBox?;
    final focal = _pinchFocal();
    final travel = _pinchLastFocal == null
        ? 0.0
        : focal.dx - _pinchLastFocal!.dx;
    _pinchLastDistance = distance;
    _pinchLastFocal = focal;
    _sync.onPinch?.call(
      scale: distance / last,
      focalTravelX: travel,
      plotWidth: (box?.size.width ?? 0) - InsulinBarChart.axisInset,
      focalFraction: _focalFraction(box, focal),
    );
  }

  /// The gesture is only over once the LAST finger lifts, not once it drops
  /// below two. Clearing it at two would let the finger still on the glass start
  /// scrubbing in the middle of a pinch being released.
  void _onPointerUp(PointerEvent event) {
    _pinchPointers.remove(event.pointer);
    if (_pinchPointers.length < 2) {
      _pinchLastDistance = null;
      _pinchLastFocal = null;
    }
    if (_pinchPointers.isEmpty) {
      _sync.gesturing = false;
    }
  }

  double _pinchDistance() {
    final points = _pinchPointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  Offset _pinchFocal() {
    final points = _pinchPointers.values.toList();
    return (points[0] + points[1]) / 2;
  }

  /// Where the pinch sits across the plot, so the time under the fingers can be
  /// held in place. Falls back to the right edge when the geometry is unknown.
  double _focalFraction(RenderBox? box, Offset focal) {
    if (box == null) {
      return 1;
    }
    final plotWidth = box.size.width - InsulinBarChart.axisInset;
    if (plotWidth <= 0) {
      return 1;
    }
    final localX = box.globalToLocal(focal).dx;
    return ((localX - InsulinBarChart.axisInset) / plotWidth).clamp(0.0, 1.0);
  }

  /// The insulin that went in over the same stretch. Nothing is drawn until the
  /// window is known: a chart over a guessed stretch of time, sitting under one
  /// over a real stretch, would be read as if the two lined up.
  Widget _insulin(List<Meal> meals) {
    final from = _sync.from;
    final to = _sync.to;
    if (from == null || to == null) {
      return const SizedBox.shrink();
    }
    return InsulinBarChart(
      sync: _sync,
      showMeals: _showMeals,
      series: InsulinChartSeries(
        basalHours: context.watch<PodController>().store.basalHours,
        meals: meals,
        from: from,
        to: to,
        liveEdge: _sync.liveEdge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meals = context.watch<MealState>().meals;
    final controller = context.watch<CgmController>();
    final bounds = GlucoseChartBounds(controller.chartHistory.values);
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
      // Glucose above, the insulin that moved it below, sharing one window.
      body: Padding(
        // Room under the insulin chart so its legend is not pressed against the
        // bottom edge of the screen.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Listener(
          key: _pairKey,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Column(
            children: [
              // The glucose chart is deliberately NOT given every pixel it can
              // take. Fitted to the readings it no longer needs the height it
              // used to, and a chart that runs to the bottom of the screen reads
              // as something the page ran out of room for.
              Expanded(
                flex: 46,
                child: OverviewChart(
                  byTime: controller.chartHistory,
                  sensorStart: controller.sensorStart,
                  navigable: true,
                  showMeals: _showMeals,
                  meals: meals,
                  sync: _sync,
                  // The same fit the overview uses, rather than a fixed 0 to 300
                  // that spends most of the picture on ranges nobody reaches.
                  minYmgdl: bounds.minMgdl,
                  maxYmgdl: bounds.maxMgdl,
                ),
              ),
              // No gap and no divider between them: they share one time axis,
              // and anything drawn in between reads as a border around two
              // separate pictures rather than one stacked pair. The axis labels
              // sit under the LOWER chart, which is what closes the seam.
              Expanded(flex: 26, child: _insulin(meals)),
              // Breathing room at the foot of the page, taken from the charts
              // rather than added under them, so it scales with the screen.
              const Spacer(flex: 12),
            ],
          ),
        ),
      ),
    );
  }
}
