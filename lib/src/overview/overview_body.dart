import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/connections/status/connection_status_page.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/battery_saver_banner.dart';
import 'package:insulink/src/overview/advisory_bolus_notice.dart';
import 'package:insulink/src/overview/overview_running_bolus.dart';
import 'package:insulink/src/overview/chart/glucose_chart_bounds.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';
import 'package:insulink/src/overview/chart/overview_chart_page.dart';
import 'package:insulink/src/overview/overview_active_insulin.dart';
import 'package:insulink/src/overview/overview_boxes.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/overview/overview_section.dart';
import 'package:insulink/src/overview/overview_pod_life.dart';
import 'package:insulink/src/overview/overview_sensor_life.dart';
import 'package:insulink/src/overview/overview_time_in_range.dart';
import 'package:insulink/src/overview/update/overview_update.dart';
import 'package:insulink/src/overview/overview_states.dart';
import 'package:insulink/src/overview/sensor_restore_offer.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:insulink/src/profile/battery/profile_battery_state.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/pump/pod_controller.dart';
import 'package:provider/provider.dart';

class OverviewBody extends AppPageBody {
  OverviewBody({super.key})
    : super(
        name: "overview.label",
        unselectedIcon: PhosphorIconsRegular.squaresFour,
        selectedIcon: PhosphorIconsFill.squaresFour,
      );

  @override
  Widget content(BuildContext context) {
    return const OverviewBodyContent();
  }

  @override
  Widget? title(BuildContext context) => const _OverviewTitle();
}

/// Header title for the overview: the "next reading" clock, which used to sit
/// in the top-right corner of the chart view. Watches the controller itself so
/// only this widget rebuilds when a new reading arrives.
///
/// Tapping it opens the connection page. The clock is already the thing the user
/// looks at when they wonder whether anything is still arriving, so "is it still
/// connected, and when did it last say anything" belongs behind it.
class _OverviewTitle extends StatelessWidget {
  const _OverviewTitle();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => openConnectionStatus(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: OverviewUpdate(
          lastUpdate: controller.lastUpdate,
          intervalSec: controller.sensorType.readingIntervalSec,
        ),
      ),
    );
  }
}

class OverviewBodyContent extends StatelessWidget {
  const OverviewBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final silent = context.watch<ProfileSilentState>().activeMode;
    final battery = context.watch<ProfileBatteryState>().activeMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          const OverviewRunningBolus(),
          const AdvisoryBolusNotice(),
          if (silent != SilentMode.off) ...[
            SilentBanner(silent),
            const SizedBox(height: 12),
          ],
          if (battery != BatteryMode.off) ...[
            BatterySaverBanner(battery),
            const SizedBox(height: 12),
          ],
          Expanded(child: _view(controller)),
        ],
      ),
    );
  }

  /// Picks the body for the current state. Show the loader while we don't yet
  /// know there's NO sensor: during initial store load, or when a sensor is
  /// paired / connecting but no reading has arrived yet. Only fall through to
  /// the "no sensor" view once we're sure.
  Widget _view(CgmController controller) {
    // Known data (a live/cached value OR archived history) → show the chart
    // straight away, even before a fresh reading lands after a re-login/restore;
    // the headline shows a loader until the current value arrives.
    //
    // Read ONCE per build and handed down: every `byTime` read rebuilds the
    // series out of the archive, and the view used to ask for it four times
    // (here, the chart, and each Y-axis bound).
    final byTime = controller.byTime;
    if (controller.currentMgdl != null || byTime.isNotEmpty) {
      return _DataView(controller: controller, byTime: byTime);
    }
    final loading =
        !controller.initialized ||
        controller.hasSensor ||
        controller.connected ||
        controller.busy;
    if (loading) {
      return const SearchingView();
    }
    // No sensor set up: above the empty prompt, offer whatever the account is
    // holding. Each renders nothing unless the backend has one, and a reinstall
    // typically has BOTH to pick up: the sensor and the pod on the body.
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SensorRestoreOffer(),
        PodRestoreCard(),
        Expanded(child: EmptyView()),
      ],
    );
  }
}

/// The overview's last scroll offset, held at module scope so it survives a full
/// rebuild of the app subtree — an account-sync `_reload` (main.dart) bumps the
/// provider generation key, which recreates the Navigator and drops PageStorage,
/// snapping the list back to the top. This outlives that; it resets only on a
/// cold process start.
double _overviewScrollOffset = 0;

/// Normal view once a (live or cached) reading exists: headline value + chart.
/// Stateful so it can own a [ScrollController] that restores [_overviewScrollOffset]
/// on (re)build and keeps it current as the user scrolls.
class _DataView extends StatefulWidget {
  const _DataView({required this.controller, required this.byTime});

  final CgmController controller;

  /// The chart series for this build (see [OverviewBodyContent._view]).
  final SplayTreeMap<int, int> byTime;

  @override
  State<_DataView> createState() => _DataViewState();
}

class _DataViewState extends State<_DataView> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _overviewScrollOffset,
  )..addListener(_remember);

  void _remember() {
    if (_scroll.hasClients) {
      _overviewScrollOffset = _scroll.offset;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_remember);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListView(
      controller: _scroll,
      // The sections here are few and expensive (the chart rebuilds its whole
      // series). The default 250 px cache drops one the moment it leaves the
      // viewport and rebuilds it on the way back — the stutter you get scrolling
      // up and down. One-and-a-half viewports of cache keeps the page built for
      // the length of that gesture.
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
      padding: const EdgeInsets.only(bottom: 52),
      children: [
        // Still offer the account's stored sensor when none is paired locally —
        // a returning device now shows this data view (synced history) instead of
        // the empty screen, so the restore offer must live here too. Renders
        // nothing unless the backend has a sensor to adopt.
        const SensorRestoreOffer(),
        // The pod is the same story and the more urgent half of it: the key it
        // is offering is the ONLY thing that can command a pod still on the
        // body, and a reinstalled app that never showed the offer here left it
        // buried on the pump page.
        const PodRestoreCard(),
        const SizedBox(height: 16),
        OverviewCurrentValue(
          mgdl: controller.currentMgdl,
          trendPerMin: controller.displayTrendPerMin,
          stale: controller.currentIsStale,
        ),
        const SizedBox(height: 28),
        OverviewSection(
          // Gate the fl_chart rebuild on the controller's chart fingerprint, so
          // the burst of service pings on open (log/connection/prediction) that
          // notify without changing the plotted data reuse the built chart
          // instead of re-laying it out. When the fingerprint changes the whole
          // body has already rebuilt too, so `widget.byTime` is the fresh series.
          child: Selector<CgmController, int>(
            selector: (_, controller) => controller.chartRevision,
            builder: (_, _, _) =>
                _ChartPreview(controller: controller, byTime: widget.byTime),
          ),
        ),
        const SizedBox(height: 16),
        const OverviewActiveInsulin(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => appTab.value = kAnalysisTabIndex,
          child: const OverviewSection(child: OverviewTimeInRange()),
        ),
        const SizedBox(height: 16),
        if (controller.sensorStart != null) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openSensorPage(context),
            child: const OverviewSection(child: OverviewSensorLife()),
          ),
          const SizedBox(height: 16),
        ],
        if (context.watch<PodController>().hasPod) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openPumpPage(context),
            child: const OverviewSection(child: OverviewPodLife()),
          ),
          const SizedBox(height: 16),
        ],
        const OverviewBoxes(),
      ],
    );
  }
}

/// Smaller, non-interactive glucose chart; tapping opens the full-screen page.
class _ChartPreview extends StatelessWidget {
  const _ChartPreview({required this.controller, required this.byTime});

  final CgmController controller;
  final SplayTreeMap<int, int> byTime;

  @override
  Widget build(BuildContext context) {
    final bounds = GlucoseChartBounds(byTime.values);
    final niceMin = bounds.minMgdl;
    final niceMax = bounds.maxMgdl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OverviewChartPage()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context),
          const SizedBox(height: 12),
          SizedBox(
            height: math.max(200.0, (niceMax - niceMin) * 0.9),
            child: OverviewChart(
              byTime: byTime,
              sensorStart: controller.sensorStart,
              preview: true,
              minYmgdl: niceMin,
              maxYmgdl: niceMax,
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        LocaleText(
          'overview.glucose',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Icon(
          PhosphorIconsBold.caretRight,
          size: 20,
          color: scheme.onSurface.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}
