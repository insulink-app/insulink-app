import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:insulink/src/analysis/compression/compression_lows.dart';
import 'package:insulink/src/analysis/compression/night_sleep.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/nutrition/meal/meal_state.dart';
import 'package:insulink/src/profile/notifications/notification_setting.dart';

/// The analysis views' compression filter: finds the compression lows of the
/// selected window ([CompressionLows]) and, while [hidden], takes their
/// readings out of the archive the views read. Switched off, every view shows
/// the raw readings again.
///
/// Sleep is read from the stored pulse, which is slow to load, so the dips are
/// worked out in the background and the views redraw once they are known. A
/// night's sleep is kept once read; only the last two nights are read again,
/// since their pulse may still be arriving.
class NightCompressionState extends ChangeNotifier {
  NightCompressionState({
    required this._meals,
    this._pulse = const IntradayPulseStore(),
  });

  /// On by default: the user asked for the filtered numbers, and the raw ones
  /// are one switch away.
  static const hideSetting = NotificationSetting(
    'analysis_hide_night_compression',
    'analysis.compression.hide',
  );

  static const _settledAfter = Duration(days: 2);

  final MealState _meals;
  final IntradayPulseStore _pulse;
  final Map<DateTime, NightSleep?> _sleeps = {};
  bool _hidden = true;
  List<CompressionDip> _dips = const [];
  Set<int> _flagged = const {};
  String? _archiveKey;

  bool get hidden => _hidden;

  /// The compression lows found in the window last passed to [apply].
  int get dipCount => _dips.length;

  Future<void> load() async {
    _hidden = await hideSetting.load();
    notifyListeners();
  }

  Future<void> setHidden(bool value) async {
    _hidden = value;
    notifyListeners();
    await hideSetting.save(value);
  }

  /// [archive] without its compression lows while [hidden], else as it is.
  /// The first call for a window starts the search and answers unfiltered.
  SplayTreeMap<int, int> apply(SplayTreeMap<int, int> archive) {
    _follow(archive);
    if (!_hidden || _flagged.isEmpty) {
      return archive;
    }
    return SplayTreeMap.of({
      for (final entry in archive.entries)
        if (!_flagged.contains(entry.key)) entry.key: entry.value,
    });
  }

  /// Starts the search when [archive] is not the one last searched.
  void _follow(SplayTreeMap<int, int> archive) {
    if (archive.isEmpty) {
      return;
    }
    final key = '${archive.firstKey()}-${archive.lastKey()}-${archive.length}';
    if (key == _archiveKey) {
      return;
    }
    _archiveKey = key;
    unawaited(_search(archive, key));
  }

  Future<void> _search(SplayTreeMap<int, int> archive, String key) async {
    final dips = CompressionLows(
      sleeps: await _sleepsFor(archive),
      mealMinutes: [
        for (final meal in _meals.meals)
          meal.time.millisecondsSinceEpoch ~/ 60000,
      ],
    ).find(archive);
    if (key != _archiveKey) {
      return;
    }
    _dips = dips;
    _flagged = _flaggedMinutes(archive, dips);
    notifyListeners();
  }

  /// The sleep of every night the archive touches.
  Future<List<NightSleep>> _sleepsFor(SplayTreeMap<int, int> archive) async {
    final first = _time(archive.firstKey()!).subtract(const Duration(days: 1));
    final last = _time(archive.lastKey()!);
    final sleeps = <NightSleep>[];
    var evening = DateTime(first.year, first.month, first.day);
    while (!evening.isAfter(last)) {
      final sleep = await _sleepOf(evening);
      if (sleep != null) {
        sleeps.add(sleep);
      }
      evening = DateTime(evening.year, evening.month, evening.day + 1);
    }
    return sleeps;
  }

  /// The sleep of the night after [evening], cached once it is settled.
  Future<NightSleep?> _sleepOf(DateTime evening) async {
    final settled = DateTime.now().difference(evening) > _settledAfter;
    if (settled && _sleeps.containsKey(evening)) {
      return _sleeps[evening];
    }
    final from = evening.add(const Duration(hours: 20));
    final samples = await _pulse.rangeCurve(
      from,
      from.add(const Duration(hours: 15)),
    );
    final sleep = const NightSleepDetector().detect(evening, {
      for (final sample in samples)
        sample.at.millisecondsSinceEpoch ~/ 60000: sample.bpm,
    });
    _sleeps[evening] = sleep;
    return sleep;
  }

  /// The archive minutes inside any of [dips].
  Set<int> _flaggedMinutes(
    SplayTreeMap<int, int> archive,
    List<CompressionDip> dips,
  ) {
    return {
      for (final minute in archive.keys)
        if (dips.any((dip) => minute > dip.fromMinute && minute < dip.toMinute))
          minute,
    };
  }

  DateTime _time(int epochMinute) =>
      DateTime.fromMillisecondsSinceEpoch(epochMinute * 60000);
}
