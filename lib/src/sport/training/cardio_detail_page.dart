import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/training/km_splits.dart';
import 'package:insulink/src/sport/training/track_interpolation.dart';
import 'package:insulink/src/sport/training/training_metrics_chart.dart';
import 'package:insulink/src/sport/training/training_splits_panel.dart';
import 'package:insulink/src/sport/training/training_stats_panel.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Detail view of a training: the route as a framed map window, the stat tiles
/// and, at the bottom, a glucose + heart-rate chart over the training. Scrubbing
/// the chart spotlights the matching position on the route.
class CardioDetailPage extends StatefulWidget {
  const CardioDetailPage({super.key, required this.training});

  final CardioTraining training;

  @override
  State<CardioDetailPage> createState() => _CardioDetailPageState();
}

class _CardioDetailPageState extends State<CardioDetailPage> {
  LatLng? _highlight;
  final ScrollController _scroll = ScrollController();
  final MapController _map = MapController();

  /// The route-fit zoom captured the first time the map reports it, so the
  /// scroll-driven zoom-out is measured from a stable baseline.
  double? _baseZoom;

  /// How far the header collapses (expandedHeight − collapsedHeight) and how many
  /// zoom levels to shed over that distance.
  static const _collapseDistance = 160.0;
  static const _zoomOut = 0.8;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Zooms the map out in step with the header collapse: 0 shed at the top, up to
  /// [_zoomOut] levels once fully collapsed.
  void _onScroll() {
    final double base;
    try {
      base = _baseZoom ??= _map.camera.zoom;
    } catch (_) {
      return;
    }
    final progress = (_scroll.offset / _collapseDistance).clamp(0.0, 1.0);
    try {
      _map.move(_map.camera.center, base - progress * _zoomOut);
    } catch (_) {}
  }

  void _onHoverMs(int? ms, CardioTraining training) {
    final position = ms == null ? null : trackPositionAt(training.track, ms);
    if (position != _highlight) {
      setState(() => _highlight = position);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CardioTrainingState>();
    final training = state.trainings.firstWhere(
      (item) => item.id == widget.training.id,
      orElse: () => widget.training,
    );
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(training.type.labelKey),
        actions: [
          PopupMenuButton<CardioType>(
            icon: const Icon(PhosphorIconsRegular.pencilSimple),
            tooltip: Locales.string(context, 'sport.trainings.change_type'),
            onSelected: (type) => state.changeTrainingType(training.id, type),
            itemBuilder: (context) => [
              for (final type in CardioType.values)
                PopupMenuItem<CardioType>(
                  value: type,
                  child: Row(
                    children: [
                      Icon(type.icon, size: 20),
                      const SizedBox(width: 12),
                      Text(Locales.string(context, type.labelKey)),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.trash),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'sport.trainings.delete_confirm',
              onConfirm: () {
                context.read<CardioTrainingState>().removeTraining(training.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _mapHeader(training),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                TrainingStatsPanel(training: training),
                ..._splits(training),
                const SizedBox(height: 20),
                _metricsChart(context, training),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// The route map as a collapsing header that stays pinned at the top while the
  /// stats/chart below scroll — shrinks from a full window to a compact strip.
  Widget _mapHeader(CardioTraining training) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 300,
      collapsedHeight: 300,
      expandedHeight: 460,
      flexibleSpace: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: training.track.length >= 2
              ? CardioMap(
                  points: training.track,
                  highlight: _highlight,
                  controller: _map,
                )
              : Container(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  alignment: Alignment.center,
                  child: LocaleText('sport.trainings.no_route'),
                ),
        ),
      ),
    );
  }

  /// Per-km pace splits — only for walk/jog (pace is a running metric; cycling
  /// reads in km/h) and only when at least one split was covered.
  List<Widget> _splits(CardioTraining training) {
    if (training.type == CardioType.bike) {
      return const [];
    }
    final splits = kmSplits(training.track);
    if (splits.isEmpty) {
      return const [];
    }
    return [const SizedBox(height: 12), TrainingSplitsPanel(splits: splits)];
  }

  Widget _metricsChart(BuildContext context, CardioTraining training) {
    // Pad the query so the chart can show the reading just before/after a short
    // training too.
    const pad = Duration(minutes: 15);
    final glucose = context.watch<CgmController>().archiveBetween(
      DateTime.fromMillisecondsSinceEpoch(training.startMs).subtract(pad),
      DateTime.fromMillisecondsSinceEpoch(training.endMs).add(pad),
    );
    return TrainingMetricsChart(
      startMs: training.startMs,
      endMs: training.endMs,
      glucose: glucose,
      onHoverMs: (ms) => _onHoverMs(ms, training),
    );
  }
}
