import 'dart:async';

import 'package:insulink/src/demo/demo_bonn_routes.dart';
import 'package:insulink/src/demo/demo_cardio.dart';
import 'package:insulink/src/demo/demo_route.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/active_training.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

/// The demo's GPS while a live training records. The browser has no service
/// isolate sampling the location, so the route stayed empty and the map had no
/// current position. This appends a point every few seconds to the same
/// location log the service writes, moving along a Bonn route at the pace of
/// the demo trainings ([DemoCardio.kilometresPerHour]) and looping at its end.
class DemoLiveTrack {
  DemoLiveTrack({required this.store, required this.active});

  final SportStore store;

  /// The training being recorded, read on every sample.
  final ActiveTraining? Function() active;

  static const Duration sampleEvery = Duration(seconds: 3);

  static final Map<CardioType, DemoRoute> routes = {
    CardioType.walk: DemoBonnRoutes.rheinaue,
    CardioType.jog: DemoBonnRoutes.riverside,
    CardioType.bike: DemoBonnRoutes.bridges,
  };

  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(sampleEvery, (_) => unawaited(_sample()));
    unawaited(_sample());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Where the training is after its elapsed (unpaused) time; nothing while
  /// paused, so the route stands still like a real one.
  Future<void> _sample() async {
    final training = active();
    if (training == null) {
      stop();
      return;
    }
    if (training.isPaused) {
      return;
    }
    final route = routes[training.type]!;
    final metresPerSecond =
        DemoCardio.kilometresPerHour[training.type.name]! / 3.6;
    final metres =
        training.elapsed.inMilliseconds / 1000 * metresPerSecond % route.length;
    final (lat, lng) = route.at(metres);
    await store.appendLocationSample(
      TrackPoint(
        lat: lat,
        lng: lng,
        tMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
