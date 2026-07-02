import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum _Phase { countdown, recording }

/// Live view of an endurance training. The GPS itself is recorded by the
/// foreground service into the shared location log (so it survives leaving/
/// closing the app); this page only mirrors it: map with the route, ticking
/// duration/distance/speed, pause and a confirmed stop. Opened fresh with a
/// [type] (3-2-1 countdown first) or reopened for an already-running training
/// ([resume]).
class CardioRecordingPage extends StatefulWidget {
  const CardioRecordingPage({super.key, this.type, this.resume = false});

  final CardioType? type;
  final bool resume;

  @override
  State<CardioRecordingPage> createState() => _CardioRecordingPageState();
}

class _CardioRecordingPageState extends State<CardioRecordingPage> {
  late final CardioTrainingState _state = context.read<CardioTrainingState>();
  final MapController _map = MapController();

  _Phase _phase = _Phase.recording;
  int _count = 3;
  Timer? _countdown;
  Timer? _ticker;
  int _tickCount = 0;

  List<TrackPoint> _points = const [];
  double _distanceM = 0;
  double _speedKmh = 0;
  double? _headingDeg;
  LatLng? _fallbackCenter;

  double _appliedRotation = 0;
  static const _rotationThresholdDeg = 25.0;
  static const _rotationMinSpeedKmh = 3.0;
  static const _refreshEvery = 3;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // Decide the phase synchronously so the countdown shows from the first frame
    // (no flash of the live panel). context.read is allowed in initState.
    _phase = (widget.resume || _state.activeTraining != null)
        ? _Phase.recording
        : _Phase.countdown;
    _loadFallbackCenter();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _loadFallbackCenter() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) {
        return;
      }
      final center = LatLng(last.latitude, last.longitude);
      setState(() => _fallbackCenter = center);
      // FlutterMap ignores initialCenter changes after it is built, so recenter
      // the already-built map onto the cached position (guarded until attached).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_points.isEmpty) {
          try {
            _map.move(center, 16);
          } catch (_) {}
        }
      });
    } catch (_) {
      // Best-effort: no last-known position just leaves the default center.
    }
  }

  void _begin() {
    if (_phase == _Phase.recording) {
      _startTicker();
      return;
    }
    _countdown = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _countTick(),
    );
  }

  Future<void> _countTick() async {
    if (_count > 1) {
      setState(() => _count -= 1);
      return;
    }
    _countdown?.cancel();
    await _state.startTraining(widget.type ?? CardioType.walk);
    if (!mounted) {
      return;
    }
    setState(() => _phase = _Phase.recording);
    _startTicker();
  }

  void _startTicker() {
    _refreshTrack();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _tickCount += 1;
    if (_tickCount % _refreshEvery == 0 &&
        !(_state.activeTraining?.isPaused ?? true)) {
      _refreshTrack();
    }
  }

  Future<void> _refreshTrack() async {
    final points = await _state.activeTrack();
    if (!mounted) {
      return;
    }
    setState(() {
      _points = points;
      _distanceM = _computeDistanceM(points);
      _speedKmh = _computeSpeedKmh(points);
      _headingDeg = _computeHeadingDeg(points);
    });
    _recenter();
  }

  double _computeDistanceM(List<TrackPoint> points) {
    var total = 0.0;
    for (var index = 1; index < points.length; index++) {
      total += Geolocator.distanceBetween(
        points[index - 1].lat,
        points[index - 1].lng,
        points[index].lat,
        points[index].lng,
      );
    }
    return total;
  }

  double _computeSpeedKmh(List<TrackPoint> points) {
    if (points.length < 2) {
      return 0;
    }
    final from = points[points.length - 2];
    final to = points.last;
    final seconds = (to.tMs - from.tMs) / 1000;
    if (seconds <= 0) {
      return 0;
    }
    final meters = Geolocator.distanceBetween(
      from.lat,
      from.lng,
      to.lat,
      to.lng,
    );
    return meters / seconds * 3.6;
  }

  double? _computeHeadingDeg(List<TrackPoint> points) {
    if (points.length < 2) {
      return null;
    }
    final from = points[points.length - 2];
    final to = points.last;
    return Geolocator.bearingBetween(from.lat, from.lng, to.lat, to.lng) % 360;
  }

  void _recenter() {
    if (_points.isEmpty) {
      return;
    }
    final center = LatLng(_points.last.lat, _points.last.lng);
    final heading = _headingDeg;
    if (heading != null &&
        _speedKmh >= _rotationMinSpeedKmh &&
        _headingDelta(-heading).abs() > _rotationThresholdDeg) {
      _appliedRotation = -heading;
      _map.moveAndRotate(center, _map.camera.zoom, _appliedRotation);
    } else {
      _map.move(center, _map.camera.zoom);
    }
  }

  /// Shortest angular difference (-180..180) so e.g. 350°→10° counts as 20°.
  double _headingDelta(double target) {
    var delta = (target - _appliedRotation) % 360;
    if (delta > 180) {
      delta -= 360;
    }
    if (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  void _confirmStop() {
    Alert(
      icon: Icons.stop_circle_rounded,
      iconColor: Colors.red.shade700,
      description: 'sport.trainings.stop_confirm',
      cancelButton: true,
      confirmButtonText: 'sport.trainings.stop',
      confirmButtonColor: Colors.red.shade700,
      callback: _stop,
    ).show(context);
  }

  Future<void> _stop() async {
    await _state.stopTraining();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _togglePause() {
    final active = _state.activeTraining;
    if (active == null) {
      return;
    }
    active.isPaused ? _state.resumeTraining() : _state.pauseTraining();
    setState(() {});
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _state.activeTraining;
    final type = active?.type ?? widget.type ?? CardioType.walk;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(type.labelKey),
        actions: [
          if (active != null)
            IconButton(
              icon: Icon(active.isPaused ? Icons.play_arrow : Icons.pause),
              tooltip: Locales.string(
                context,
                active.isPaused
                    ? 'sport.trainings.resume'
                    : 'sport.trainings.pause',
              ),
              onPressed: _togglePause,
            ),
        ],
      ),
      body: Stack(
        children: [
          CardioMap(
            controller: _map,
            points: _points,
            live: true,
            fallbackCenter: _fallbackCenter,
          ),
          if (_phase == _Phase.countdown) _countdownOverlay(context),
          if (_phase == _Phase.recording)
            Align(alignment: Alignment.bottomCenter, child: _panel(context)),
        ],
      ),
    );
  }

  Widget _countdownOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: Text(
        '$_count',
        style: const TextStyle(
          fontSize: 120,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _state.activeTraining;
    final paused = active?.isPaused ?? false;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metric(
                context,
                'sport.trainings.duration',
                formatDuration(active?.elapsed ?? Duration.zero),
              ),
              _metric(
                context,
                'sport.trainings.distance',
                formatDistanceKm(_distanceM),
              ),
              _metric(context, 'sport.trainings.speed', formatSpeed(_speedKmh)),
            ],
          ),
          if (paused) ...[
            const SizedBox(height: 8),
            LocaleText(
              'sport.trainings.paused',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              icon: const Icon(Icons.stop_rounded, size: 28),
              label: LocaleText(
                'sport.trainings.stop',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _confirmStop,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String labelKey, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          Locales.string(context, labelKey),
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
