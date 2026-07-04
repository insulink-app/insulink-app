import 'dart:async';

import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';

import '../sport_store.dart';
import 'cardio_models.dart';

/// Subscribes to the OS activity-recognition stream in the foreground-service
/// isolate and logs each activity CHANGE (walking / running / cycling / in a
/// vehicle) to the store. The cardio auto-detector reads this log to tell a real
/// bike ride from a bus/train — speed alone classifies both as cycling.
///
/// Best-effort: does nothing unless the ACTIVITY_RECOGNITION permission is held
/// (the UI/onboarding requests it; the service isolate can't show a dialog);
/// glucose reading never depends on it.
class ActivityRecognitionSampler {
  final SportStore _store;
  StreamSubscription<Activity>? _subscription;
  ActivityKind? _last;

  ActivityRecognitionSampler([this._store = const SportStore()]);

  /// Idempotent: subscribe once, only if the permission is already granted.
  Future<void> start() async {
    if (_subscription != null) {
      return;
    }
    final permission =
        await FlutterActivityRecognition.instance.checkPermission();
    if (permission != ActivityPermission.GRANTED) {
      return;
    }
    _subscription = FlutterActivityRecognition.instance.activityStream
        .handleError((_) {})
        .listen(_onActivity);
  }

  /// Records one sample per distinct kind — the stream re-emits the same activity
  /// repeatedly, so we only append when the kind actually changes.
  Future<void> _onActivity(Activity activity) async {
    final kind = _map(activity.type);
    if (kind == _last) {
      return;
    }
    _last = kind;
    await _store.appendActivitySample(
      ActivitySample(tMs: DateTime.now().millisecondsSinceEpoch, kind: kind),
    );
  }

  ActivityKind _map(ActivityType type) => switch (type) {
    ActivityType.STILL => ActivityKind.still,
    ActivityType.WALKING => ActivityKind.walk,
    ActivityType.RUNNING => ActivityKind.run,
    ActivityType.ON_BICYCLE => ActivityKind.bike,
    ActivityType.IN_VEHICLE => ActivityKind.vehicle,
    ActivityType.UNKNOWN => ActivityKind.unknown,
  };

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
