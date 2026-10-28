import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/analysis/compression/compression_lows.dart';
import 'package:insulink/src/analysis/compression/night_sleep.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';

/// The compression filter shared by the full-screen chart and the analysis
/// views: one switch (in the chart's app bar), one answer for both. While
/// [hidden], the readings of every compression low ([CompressionLows]) are
/// taken out of what they draw; switched off, both show the raw readings.
///
/// Worked out per NIGHT, not per window, from the archive itself: the chart and
/// the analysis ask for different windows, and a result per window would have
/// each one's request undo the other's. Sleep comes from the stored pulse,
/// which is slow to load, so a night is searched in the background and the
/// views redraw once it is known. A night is kept once two days old; a younger
/// one is searched again at most every [_refreshEvery], since its readings and
/// pulse may still be arriving.
class NightCompressionState extends ChangeNotifier {
  NightCompressionState({
    required this._meals,
    required this._glucose,
    this._pulse = const IntradayPulseStore(),
  });

  /// On by default: the filtered picture is what was asked for, the raw one
  /// is one tap away.
  static const hideSetting = NotificationSetting(
    'analysis_hide_night_compression',
    'overview.chart.hide_compression',
  );

  static const _settledAfter = Duration(days: 2);
  static const _refreshEvery = Duration(minutes: 5);

  final MealState _meals;
  final CgmController _glucose;
  final IntradayPulseStore _pulse;
  final Map<DateTime, ({Set<int> flagged, DateTime searchedAt})> _nights = {};
  final Set<DateTime> _searching = {};
  bool _hidden = true;

  bool get hidden => _hidden;

  Future<void> load() async {
    _hidden = await hideSetting.load();
    notifyListeners();
  }

  Future<void> toggle() async {
    _hidden = !_hidden;
    notifyListeners();
    await hideSetting.save(_hidden);
  }

  /// [archive] (epoch minute to mg/dL) without its compression lows while
  /// [hidden], else as it is. Nights not searched yet answer unfiltered.
  SplayTreeMap<int, int> apply(SplayTreeMap<int, int> archive) {
    if (archive.isEmpty) {
      return archive;
    }
    _follow(archive.firstKey()!, archive.lastKey()!);
    return _without(archive, (epochMinute) => epochMinute);
  }

  /// The same for the chart's series, keyed by seconds since [sensorStart].
  /// Without a session clock its keys name no time, so it stays as it is.
  SplayTreeMap<int, int> applyToChart(
    SplayTreeMap<int, int> bySeconds,
    DateTime? sensorStart,
  ) {
    if (bySeconds.isEmpty || sensorStart == null) {
      return bySeconds;
    }
    final startSeconds = sensorStart.millisecondsSinceEpoch ~/ 1000;
    int epochMinute(int seconds) => (seconds + startSeconds) ~/ 60;
    _follow(
      epochMinute(bySeconds.firstKey()!),
      epochMinute(bySeconds.lastKey()!),
    );
    return _without(bySeconds, epochMinute);
  }

  /// [series] without the flagged minutes, [toMinute] turning its key into one.
  SplayTreeMap<int, int> _without(
    SplayTreeMap<int, int> series,
    int Function(int key) toMinute,
  ) {
    final flagged = {for (final night in _nights.values) ...night.flagged};
    if (!_hidden || flagged.isEmpty) {
      return series;
    }
    return SplayTreeMap.of({
      for (final entry in series.entries)
        if (!flagged.contains(toMinute(entry.key))) entry.key: entry.value,
    });
  }

  /// Starts a search for every night from [fromMinute] to [toMinute] that has
  /// none yet, or whose last one may be out of date.
  void _follow(int fromMinute, int toMinute) {
    final first = _time(fromMinute).subtract(const Duration(days: 1));
    final last = _time(toMinute);
    var evening = DateTime(first.year, first.month, first.day);
    while (!evening.isAfter(last)) {
      if (_due(evening)) {
        unawaited(_search(evening));
      }
      evening = DateTime(evening.year, evening.month, evening.day + 1);
    }
  }

  bool _due(DateTime evening) {
    final night = _nights[evening];
    if (_searching.contains(evening)) {
      return false;
    }
    if (night == null) {
      return true;
    }
    final settled = night.searchedAt.difference(evening) > _settledAfter;
    return !settled &&
        DateTime.now().difference(night.searchedAt) > _refreshEvery;
  }

  /// Searches the night after [evening] and redraws. A failed read (the pulse
  /// store, say) leaves the night unsearched, to be tried on the next ask.
  Future<void> _search(DateTime evening) async {
    _searching.add(evening);
    try {
      _nights[evening] = (
        flagged: await _flaggedIn(evening),
        searchedAt: DateTime.now(),
      );
      notifyListeners();
    } finally {
      _searching.remove(evening);
    }
  }

  /// The reading minutes of the night's compression lows, none without a sleep
  /// to find them in.
  Future<Set<int>> _flaggedIn(DateTime evening) async {
    final from = evening.add(const Duration(hours: 20));
    final to = from.add(const Duration(hours: 15));
    final samples = await _pulse.rangeCurve(from, to);
    final sleep = const NightSleepDetector().detect(evening, {
      for (final sample in samples)
        sample.at.millisecondsSinceEpoch ~/ 60000: sample.bpm,
    });
    if (sleep == null) {
      return const {};
    }
    final readings = _glucose.archiveBetween(from, to);
    final dips = CompressionLows(
      sleeps: [sleep],
      mealMinutes: _mealMinutes,
    ).find(readings);
    return _flaggedMinutes(readings, dips);
  }

  List<int> get _mealMinutes => [
    for (final meal in _meals.meals) meal.time.millisecondsSinceEpoch ~/ 60000,
  ];

  /// The reading minutes inside any of [dips].
  Set<int> _flaggedMinutes(
    SplayTreeMap<int, int> readings,
    List<CompressionDip> dips,
  ) {
    return {
      for (final minute in readings.keys)
        if (dips.any((dip) => minute > dip.fromMinute && minute < dip.toMinute))
          minute,
    };
  }

  DateTime _time(int epochMinute) =>
      DateTime.fromMillisecondsSinceEpoch(epochMinute * 60000);
}
