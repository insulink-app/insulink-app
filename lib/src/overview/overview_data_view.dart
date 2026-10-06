import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:insulink/src/base/page.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/overview/chart/overview_chart_preview.dart';
import 'package:insulink/src/overview/glucose_hero.dart';
import 'package:insulink/src/overview/overview_active_insulin.dart';
import 'package:insulink/src/overview/overview_boxes.dart';
import 'package:insulink/src/overview/overview_devices.dart';
import 'package:insulink/src/overview/overview_time_in_range.dart';
import 'package:insulink/src/overview/range_scale.dart';
import 'package:insulink/src/overview/sensor_restore_offer.dart';
import 'package:insulink/src/pump/pod_restore_card.dart';
import 'package:provider/provider.dart';

/// The overview's last scroll offset, held at module scope so it survives a full
/// rebuild of the app subtree — an account-sync `_reload` (main.dart) bumps the
/// provider generation key, which recreates the Navigator and drops PageStorage,
/// snapping the list back to the top. This outlives that; it resets only on a
/// cold process start.
double _overviewScrollOffset = 0;

/// Normal view once a (live or cached) reading exists: headline value + chart.
/// Stateful so it can own a [ScrollController] that restores [_overviewScrollOffset]
/// on (re)build and keeps it current as the user scrolls.
class OverviewDataView extends StatefulWidget {
  const OverviewDataView({
    super.key,
    required this.controller,
    required this.byTime,
  });

  final CgmController controller;

  /// The chart series for this build (see `OverviewBodyContent`).
  final SplayTreeMap<int, int> byTime;

  @override
  State<OverviewDataView> createState() => _OverviewDataViewState();
}

class _OverviewDataViewState extends State<OverviewDataView> {
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

  /// The sections are few and expensive (the chart rebuilds its whole series).
  /// The default 250 px cache drops one the moment it leaves the viewport and
  /// rebuilds it on the way back, the stutter you get scrolling up and down;
  /// one and a half viewports of cache keeps the page built for that gesture.
  ///
  /// The restore offers stay here too: a returning device shows this view
  /// (synced history) instead of the empty screen, and the pod's offer is the
  /// ONLY thing that can command a pod still on the body.
  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _scroll,
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
      padding: const EdgeInsets.only(bottom: 52),
      children: [
        const SensorRestoreOffer(),
        const PodRestoreCard(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _glucoseArea(),
        ),
        const SizedBox(height: 22),
        const OverviewActiveInsulin(),
        const SizedBox(height: 12),
        const OverviewDevices(),
        const SizedBox(height: 24),
        const OverviewBoxes(),
      ],
    );
  }

  /// Value, scale, chart and time in range: open on the page, no panel.
  Widget _glucoseArea() {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        GlucoseHero(
          mgdl: controller.currentMgdl,
          trendPerMin: controller.displayTrendPerMin,
          stale: controller.currentIsStale,
        ),
        const SizedBox(height: 22),
        RangeScale(mgdl: controller.currentMgdl),
        const SizedBox(height: 18),
        _chart(),
        const SizedBox(height: 22),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => appTab.value = kAnalysisTabIndex,
          child: const OverviewTimeInRange(),
        ),
      ],
    );
  }

  /// Gated on the controller's chart fingerprint, so the burst of service pings
  /// on open (log/connection/prediction) that notify without changing the
  /// plotted data reuse the built chart instead of re-laying it out. When the
  /// fingerprint changes the whole body has already rebuilt too, so
  /// `widget.byTime` is the fresh series.
  Widget _chart() {
    return Selector<CgmController, int>(
      selector: (_, controller) => controller.chartRevision,
      builder: (_, _, _) => OverviewChartPreview(
        controller: widget.controller,
        byTime: widget.byTime,
      ),
    );
  }
}
