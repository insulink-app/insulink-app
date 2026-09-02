import 'dart:convert';

import 'package:insulink/src/request/request.dart';

/// One forecast the model made in the past: issued at [at], for `at + horizon`.
///
/// [persistence] is the reading the anchor itself sat on — the baseline
/// `ŷ_{t+h} = g_t` the backend's ROADMAP scores every model against. It travels
/// with the point so the skill score needs nothing but this and the reading that
/// actually arrived.
class BacktestPoint {
  const BacktestPoint({
    required this.at,
    required this.predicted,
    required this.persistence,
    this.lo,
    this.hi,
  });

  final DateTime at;
  final int predicted;
  final int persistence;

  /// The point's conformal q10/q90 bounds, null for a model trained before the
  /// band existed. The mean is shrunk toward the middle, so the band is what
  /// actually reaches a low or a high — coverage is scored on it, not on
  /// [predicted].
  final int? lo;
  final int? hi;
}

/// A window of past forecasts for one horizon, oldest first.
class ForecastBacktest {
  const ForecastBacktest({required this.horizonMin, required this.points});

  final int horizonMin;
  final List<BacktestPoint> points;
}

/// Fetches the past forecasts from the backend (`POST /glucose/predict/backtest/`).
///
/// The backend replays the user's own model over its stored history and hands
/// back what it would have said at every five-minute bucket. Nothing is scored
/// there: the readings that actually arrived live on this device, so the
/// comparison happens here.
///
/// Returns null when the request fails or the user has no trained model yet —
/// the caller shows an empty state rather than an error, because "no model yet"
/// is the ordinary state of a new account.
class ForecastBacktestFetcher {
  Future<ForecastBacktest?> fetch(int horizon, {int hours = 24}) async {
    final response = await Request.post(
      url: '/glucose/predict/backtest/',
      body: {'horizon': horizon, 'hours': hours},
    ).send(null);
    if (response == null || response.statusCode != 200) {
      return null;
    }
    return _parse(response.body);
  }

  ForecastBacktest? _parse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['success'] != true || json['points'] is! List) {
      return null;
    }
    final points = [
      for (final item in json['points'] as List)
        BacktestPoint(
          at: DateTime.fromMillisecondsSinceEpoch((item as Map)['ts'] as int),
          predicted: (item['mgdl'] as num).round(),
          persistence: (item['anchor_mgdl'] as num).round(),
          lo: (item['lo_mgdl'] as num?)?.round(),
          hi: (item['hi_mgdl'] as num?)?.round(),
        ),
    ];
    return points.isEmpty
        ? null
        : ForecastBacktest(
            horizonMin: json['horizon_min'] as int,
            points: points,
          );
  }
}
