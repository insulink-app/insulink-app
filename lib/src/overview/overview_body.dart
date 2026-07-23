import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/connections/connections_body.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/overview/chart/overview_chart.dart';
import 'package:insulink/src/overview/chart/overview_chart_page.dart';
import 'package:insulink/src/overview/overview_active_insulin.dart';
import 'package:insulink/src/overview/overview_boxes.dart';
import 'package:insulink/src/overview/overview_current_value.dart';
import 'package:insulink/src/overview/overview_section.dart';
import 'package:insulink/src/overview/overview_sensor_life.dart';
import 'package:insulink/src/overview/overview_time_in_range.dart';
import 'package:insulink/src/overview/update/overview_update.dart';
import 'package:insulink/src/overview/overview_states.dart';
import 'package:insulink/src/overview/sensor_restore_offer.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
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
class _OverviewTitle extends StatelessWidget {
  const _OverviewTitle();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    return OverviewUpdate(
      lastUpdate: controller.lastUpdate,
      intervalSec: controller.sensorType.readingIntervalSec,
    );
  }
}

class OverviewBodyContent extends StatelessWidget {
  const OverviewBodyContent({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final silent = context.watch<ProfileSilentState>().silent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          if (silent) ...[const SilentBanner(), const SizedBox(height: 12)],
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
    // No sensor set up: below the empty prompt, offer the account's stored
    // sensor (renders nothing unless the backend has one).
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SensorRestoreOffer(),
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
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _overviewScrollOffset)
        ..addListener(_remember);

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
        const SizedBox(height: 16),
        OverviewCurrentValue(
          mgdl: controller.currentMgdl,
          trendPerMin: controller.displayTrendPerMin,
          stale: controller.currentIsStale,
        ),
        const SizedBox(height: 28),
        OverviewSection(
          child: _ChartPreview(controller: controller, byTime: widget.byTime),
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
    final niceMin = _niceMinMgdl();
    final niceMax = _niceMaxMgdl();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const OverviewChartPage(),
        ),
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

  /// Y-axis top (mg/dL): the peak rounded up to the next 50, floored at 200 so
  /// the target band stays visible. A low day uses less space; a high day more.
  int _niceMaxMgdl() {
    final values = byTime.values;
    if (values.isEmpty) {
      return 200;
    }
    final peak = values.reduce((a, b) => a > b ? a : b);
    final rounded = ((peak + 20) / 50).ceil() * 50;
    return rounded < 200 ? 200 : rounded;
  }

  /// Y-axis bottom (mg/dL): ~50 when nothing dips lower, else rounded down to the
  /// next 50 — so a normal day starts at 50 instead of wasting space down to 0.
  int _niceMinMgdl() {
    final values = byTime.values;
    if (values.isEmpty) {
      return 50;
    }
    final low = values.reduce((a, b) => a < b ? a : b);
    final floor = (low / 50).floor() * 50;
    return floor > 50 ? 50 : floor;
  }
}
