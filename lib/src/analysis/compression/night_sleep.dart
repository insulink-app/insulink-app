/// One night's sleep as read off the pulse.
class NightSleep {
  const NightSleep(this.from, this.to);

  final DateTime from;
  final DateTime to;

  bool contains(DateTime at) => !at.isBefore(from) && !at.isAfter(to);
}

/// Finds the night's sleep in the minute pulse (`IntradayPulseStore`).
///
/// Asleep is a pulse whose 30-minute median stays within [_margin] bpm of the
/// night's resting level, the 10th percentile between midnight and 5:00. The
/// sleep is the longest such stretch from 20:00 to 11:00, bridging gaps of
/// up to [_maxGap] (getting up once, a few minutes awake). The night needs
/// [_minNightSamples] minutes of pulse after midnight and a sleep of at least
/// [_minSleep]; a band left off says nothing.
///
/// Lying down by day squeezes a sensor as much as by night, so [detectAll] adds
/// the day's rests: every stretch from 11:00 to 20:00 of at least [_minRest] at
/// the same night's resting level. Shorter than a night's sleep, since a nap
/// or an hour on the couch is what it is after.
class NightSleepDetector {
  const NightSleepDetector();

  static const _margin = 10;
  static const _halfWindow = 15;
  static const _maxGap = 20;
  static const _minNightSamples = 120;
  static const _minSleep = Duration(hours: 3);
  static const _minRest = Duration(minutes: 45);

  /// The night's sleep plus the rests of the day after it, from 20:00 on the
  /// evening of [evening] to 20:00 the next day; empty when the night's pulse
  /// cannot tell. A rest is measured against the night's resting level, so a day
  /// after a night without pulse has none.
  List<NightSleep> detectAll(DateTime evening, Map<int, int> pulse) {
    final start = _eveningMinute(evening);
    final resting = _restingLevel(pulse, start + 4 * 60, start + 9 * 60);
    if (resting == null) {
      return const [];
    }
    return [
      ?_sleepIn(pulse, start, start + 15 * 60, resting),
      for (final run in _asleepRuns(
        pulse,
        start + 15 * 60,
        start + 24 * 60,
        resting,
      ))
        if (run.to - run.from >= _minRest.inMinutes)
          NightSleep(_time(run.from), _time(run.to)),
    ];
  }

  /// The sleep of the night that starts on the evening of [evening], from the
  /// bpm per epoch minute in [pulse], or null when the pulse cannot tell.
  NightSleep? detect(DateTime evening, Map<int, int> pulse) {
    final start = _eveningMinute(evening);
    final resting = _restingLevel(pulse, start + 4 * 60, start + 9 * 60);
    if (resting == null) {
      return null;
    }
    return _sleepIn(pulse, start, start + 15 * 60, resting);
  }

  /// The longest asleep stretch in `[from, to)`, if it lasts a night's sleep.
  NightSleep? _sleepIn(Map<int, int> pulse, int from, int to, int resting) {
    final runs = _asleepRuns(pulse, from, to, resting);
    if (runs.isEmpty) {
      return null;
    }
    final run = runs.reduce(
      (longest, candidate) =>
          candidate.to - candidate.from > longest.to - longest.from
          ? candidate
          : longest,
    );
    if (run.to - run.from < _minSleep.inMinutes) {
      return null;
    }
    return NightSleep(_time(run.from), _time(run.to));
  }

  /// The 10th percentile of the pulse in `[from, to)`, or null when too thin.
  int? _restingLevel(Map<int, int> pulse, int from, int to) {
    final night = [
      for (var minute = from; minute < to; minute++) ?pulse[minute],
    ]..sort();
    if (night.length < _minNightSamples) {
      return null;
    }
    return night[night.length ~/ 10];
  }

  /// Every stretch of asleep minutes in `[from, to)`, short gaps bridged.
  List<({int from, int to})> _asleepRuns(
    Map<int, int> pulse,
    int from,
    int to,
    int resting,
  ) {
    final runs = <({int from, int to})>[];
    int? runStart;
    int? lastAsleep;
    for (var minute = from; minute < to; minute++) {
      if (_asleep(pulse, minute, resting)) {
        if (runStart == null) {
          runStart = minute;
          runs.add((from: minute, to: minute));
        }
        lastAsleep = minute;
        runs.last = (from: runStart, to: minute);
      } else if (lastAsleep != null && minute - lastAsleep > _maxGap) {
        runStart = null;
        lastAsleep = null;
      }
    }
    return runs;
  }

  /// Whether the median pulse around [minute] sits at the resting level.
  bool _asleep(Map<int, int> pulse, int minute, int resting) {
    final around = [
      for (var at = minute - _halfWindow; at < minute + _halfWindow; at++)
        ?pulse[at],
    ];
    if (around.length < _halfWindow * 2 / 3) {
      return false;
    }
    around.sort();
    return around[around.length ~/ 2] <= resting + _margin;
  }

  int _eveningMinute(DateTime evening) =>
      DateTime(
        evening.year,
        evening.month,
        evening.day,
        20,
      ).millisecondsSinceEpoch ~/
      60000;

  DateTime _time(int epochMinute) =>
      DateTime.fromMillisecondsSinceEpoch(epochMinute * 60000);
}
