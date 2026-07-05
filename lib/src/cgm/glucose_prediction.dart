import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';

/// One point of the forecast curve: minutes ahead of "now" and predicted mg/dL.
class PredictionPoint {
  const PredictionPoint(this.offsetMin, this.mgdl);

  final int offsetMin;
  final int mgdl;
}

/// A fetched forecast: the reading time it is anchored to plus the curve.
class GlucosePrediction {
  const GlucosePrediction(this.base, this.points);

  final DateTime base;
  final List<PredictionPoint> points;

  Map<String, dynamic> toJson() => {
    'base': base.millisecondsSinceEpoch,
    'points': [
      for (final point in points) {'o': point.offsetMin, 'm': point.mgdl},
    ],
  };

  static GlucosePrediction? fromJson(Map<String, dynamic> json) {
    final base = json['base'];
    final points = json['points'];
    if (base is! int || points is! List) {
      return null;
    }
    final parsed = [
      for (final point in points)
        PredictionPoint((point as Map)['o'] as int, point['m'] as int),
    ];
    return parsed.isEmpty
        ? null
        : GlucosePrediction(DateTime.fromMillisecondsSinceEpoch(base), parsed);
  }
}

/// Fetches the glucose forecast from the backend (`GET /glucose/predict/`).
///
/// Returns null only when the request fails (the caller keeps the last good
/// forecast). The backend reads the user's recent readings from its own store
/// and calls the Python model, so no reading data is sent from the client.
class GlucosePredictionFetcher {
  /// [mgdl]/[time] carry the client's freshest reading so the backend anchors
  /// the forecast to it even before the debounced glucose report has synced it.
  Future<GlucosePrediction?> fetch(int horizon, {int? mgdl, DateTime? time}) async {
    var url = '/glucose/predict/?horizon=$horizon';
    if (mgdl != null && time != null) {
      url += '&value=$mgdl&time=${time.millisecondsSinceEpoch}';
    }
    final response = await Request.get(url: url).send(null);
    if (response == null || response.statusCode != 200) {
      return null;
    }
    return _parse(response.body);
  }

  GlucosePrediction? _parse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['success'] != true || json['curve'] is! List) {
      return null;
    }
    final base = DateTime.fromMillisecondsSinceEpoch(json['generated_at'] as int);
    final points = [
      for (final item in json['curve'] as List)
        PredictionPoint(
          (item as Map)['offset_min'] as int,
          (item['mgdl'] as num).round(),
        ),
    ];
    return points.isEmpty ? null : GlucosePrediction(base, points);
  }
}

/// Persists the latest forecast so it survives an app restart (the overlay would
/// otherwise be blank until the next reading ~5 min later).
class PredictionCache {
  static const _kCache = 'prediction_cache';
  static const _storage = FlutterSecureStorage();

  Future<void> save(GlucosePrediction? prediction) async {
    if (prediction == null) {
      await _storage.delete(key: _kCache);
      return;
    }
    await _storage.write(key: _kCache, value: jsonEncode(prediction.toJson()));
  }

  Future<GlucosePrediction?> load() async {
    final raw = await _storage.read(key: _kCache);
    if (raw == null) {
      return null;
    }
    return GlucosePrediction.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
