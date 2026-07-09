import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/base/hour_range_selector.dart';
import 'package:insulink/src/google_health/fitbit_heart_rate_monitor.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/heart_rate_chart_series.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';
import 'package:insulink/src/google_health/heart_rate_zones_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:provider/provider.dart';

typedef _HrSample = ({DateTime at, int bpm});

/// Intraday heart-rate curve for a single day (pulse over the day) with a day
/// picker, a 24 / 12 / 6 h window selector (like the glucose chart) and a
/// Ø / Min / Max header computed over the visible window. Samples are read live
/// from Health Connect (see [GoogleHealthImporter.heartRateBetween]).
class HeartRatePage extends StatefulWidget {
  const HeartRatePage({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  static const _kRangeKey = 'hr_range_hours';
  static const _kCurveCacheKey = 'hr_curve_cache';
  static const _storage = FlutterSecureStorage();

  /// Per-day intraday curve cache, kept across page instances so reopening the
  /// page (or switching days back) shows the last-loaded curve instantly instead
  /// of a loader. Persisted to secure storage (see [_persistCache]) so it also
  /// survives an app relaunch — a background re-read refreshes it. Sleep already
  /// feels instant because it lives in the persisted archive; this gives pulse
  /// the same feel.
  static final Map<DateTime, List<_HrSample>> _cache = {};

  /// Restore-from-storage runs once per process (the cache is static).
  static bool _restored = false;

  late DateTime _day = _today();

  /// Right edge of the window (captured when the data is loaded so the X axis and
  /// the query share one anchor): now for today, else the selected day's end.
  late DateTime _end;
  late Future<List<_HrSample>> _future = _load();

  /// Visible window in hours (24 / 12 / 6), ending at [_end] — a rolling window,
  /// so 24 h shows the trailing day (crossing midnight), not 0–24 o'clock.
  int _rangeHours = 24;

  /// User-configurable pulse zones (green / orange / red).
  HeartRateZones _zones = const HeartRateZones();

  /// Index of the transparent overlay bar that owns touch (so the tooltip shows
  /// one value, not one per zone bar).
  int _touchBarIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreCache();
    _loadRange();
    HeartRateZones.load().then((zones) {
      if (mounted) {
        setState(() => _zones = zones);
      }
    });
  }

  Future<void> _editZones() async {
    final updated = await showHeartRateZonesSheet(context, _zones);
    if (updated != null && mounted) {
      setState(() => _zones = updated);
    }
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _day == _today();

  /// Always loads the full 24 h ending at [_end]; the 6/12 h views just re-window
  /// this without re-reading.
  Future<List<_HrSample>> _load() {
    _end = _isToday ? DateTime.now() : _day.add(const Duration(days: 1));
    final day = _day;
    final fresh = GoogleHealthImporter()
        .heartRateBetween(_end.subtract(const Duration(hours: 24)), _end)
        .then((samples) {
      _cache[day] = samples;
      _persistCache();
      return samples;
    });
    final cached = _cache[day];
    if (cached == null) {
      return fresh;
    }
    // Show cached instantly, swap in the refreshed curve when it lands.
    fresh.then((samples) {
      if (mounted && _day == day) {
        setState(() => _future = Future.value(samples));
      }
    });
    return Future.value(cached);
  }

  /// Loads the persisted curve cache once per process and, if the current day is
  /// present, swaps it in so a cold reopen shows the last curve instantly instead
  /// of a loader (the fresh read from [_load] then refreshes it in the
  /// background).
  Future<void> _restoreCache() async {
    if (_restored) {
      return;
    }
    _restored = true;
    final raw = await _storage.read(key: _kCurveCacheKey);
    if (raw == null) {
      return;
    }
    (jsonDecode(raw) as Map<String, dynamic>).forEach((key, value) {
      _cache[DateTime.parse(key)] = [
        for (final sample in value as List)
          (
            at: DateTime.fromMillisecondsSinceEpoch(sample['t'] as int),
            bpm: sample['b'] as int,
          ),
      ];
    });
    final cached = _cache[_day];
    if (mounted && cached != null) {
      setState(() => _future = Future.value(cached));
    }
  }

  /// Persists the most recent 7 days of the curve cache to secure storage.
  Future<void> _persistCache() async {
    final days = _cache.keys.toList()..sort();
    final recent = days.length > 7 ? days.sublist(days.length - 7) : days;
    await _storage.write(
      key: _kCurveCacheKey,
      value: jsonEncode({
        for (final day in recent)
          day.toIso8601String(): [
            for (final sample in _cache[day]!)
              {'t': sample.at.millisecondsSinceEpoch, 'b': sample.bpm},
          ],
      }),
    );
  }

  Future<void> _loadRange() async {
    final stored = int.tryParse(await _storage.read(key: _kRangeKey) ?? '');
    if (mounted && (stored == 6 || stored == 12 || stored == 24)) {
      setState(() => _rangeHours = stored!);
    }
  }

  void _setRange(int hours) {
    setState(() => _rangeHours = hours);
    _storage.write(key: _kRangeKey, value: '$hours');
  }

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(_today())) {
      return;
    }
    setState(() {
      _day = next;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('google_health.heart_rate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: Locales.string(context, 'google_health.hr_zones.title'),
            onPressed: _editZones,
          ),
        ],
      ),
      body: Column(
        children: [
          _liveBanner(context),
          _dayPicker(context),
          Expanded(
            child: FutureBuilder<List<_HrSample>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final samples = snapshot.data ?? const [];
                if (samples.isEmpty) {
                  return Center(child: LocaleText('google_health.detail.empty'));
                }
                return _content(context, samples);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Real-time BLE pulse from the worn Fitbit (see [FitbitHeartRateMonitor]),
  /// with its scan/connect/stream status so a missing pulse is diagnosable.
  Widget _liveBanner(BuildContext context) {
    final monitor = context.read<GoogleHealthState>().liveHrMonitor;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final live = monitor.status == FitbitHrStatus.streaming;
        return InkWell(
          onTap: monitor.isRunning ? null : monitor.start,
          borderRadius: BorderRadius.circular(16),
          child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                Icons.favorite,
                color: live ? scheme.error : scheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 12),
              Text(
                live && monitor.bpm != null ? '${monitor.bpm}' : '–',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('bpm', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _dayPicker(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1),
          ),
          Text(
            locale.formatMediumDate(_day),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : () => _shift(1),
          ),
        ],
      ),
    );
  }

  /// Whole clock hour at/just before [_end] — the X=0 reference, so integer X
  /// values land on whole clock hours (the tick labels).
  DateTime get _wholeHour =>
      DateTime(_end.year, _end.month, _end.day, _end.hour);

  /// Chart X of a time: hours relative to [_wholeHour] (negative = earlier).
  double _xOf(DateTime at) => at.difference(_wholeHour).inSeconds / 3600;

  double get _rightX => _xOf(_end);
  double get _leftX => _rightX - _rangeHours;

  Widget _content(BuildContext context, List<_HrSample> samples) {
    final scheme = Theme.of(context).colorScheme;
    final visible = [
      for (final sample in samples)
        if (_xOf(sample.at) >= _leftX) sample,
    ];
    if (visible.isEmpty) {
      return Center(child: LocaleText('google_health.detail.empty'));
    }
    final bpms = visible.map((sample) => sample.bpm);
    final avg = bpms.reduce((a, b) => a + b) / visible.length;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        _statsRow(context, scheme, avg.round(),
            bpms.reduce((a, b) => a < b ? a : b),
            bpms.reduce((a, b) => a > b ? a : b)),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: HourRangeSelector(selected: _rangeHours, onChanged: _setRange),
        ),
        const SizedBox(height: 16),
        _chartCard(scheme, visible),
      ],
    );
  }

  Widget _statsRow(
    BuildContext context,
    ColorScheme scheme,
    int avg,
    int min,
    int max,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(context, scheme, 'sport.activity.detail.average', avg),
          _stat(context, scheme, 'google_health.hr_min', min),
          _stat(context, scheme, 'google_health.hr_max', max),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, ColorScheme scheme, String labelKey, int value) {
    return Column(
      children: [
        Text(
          Locales.string(context, labelKey),
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            text: sportInt(value),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            children: [
              TextSpan(
                text: ' bpm',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chartCard(ColorScheme scheme, List<_HrSample> samples) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        height: 240,
        child: LineChart(_chartData(scheme, samples)),
      ),
    );
  }

  /// Target number of points the line is thinned to. Scales inversely with the
  /// window (120 at 24 h, 240 at 12 h, 480 at 6 h): a zoomed-in range has fewer
  /// samples spread over the same width, so a finer curve stays readable.
  int get _maxChartPoints => (120 * 24 / _rangeHours).round();

  /// Thins the samples to at most [_maxChartPoints] by averaging each equal-width
  /// time bucket, so the curve reads cleanly while keeping its shape. Stats
  /// (Ø/Min/Max) are computed separately over the full data, so no extremes are
  /// lost to the averaging.
  List<FlSpot> _chartSpots(List<_HrSample> samples) {
    if (samples.length <= _maxChartPoints) {
      return [
        for (final sample in samples)
          FlSpot(_xOf(sample.at), sample.bpm.toDouble()),
      ];
    }
    final bucketHours = (_rightX - _leftX) / _maxChartPoints;
    final buckets = <int, ({double x, double y, int count})>{};
    for (final sample in samples) {
      final x = _xOf(sample.at);
      final index = (x / bucketHours).floor();
      final current = buckets[index];
      buckets[index] = current == null
          ? (x: x, y: sample.bpm.toDouble(), count: 1)
          : (x: current.x + x, y: current.y + sample.bpm, count: current.count + 1);
    }
    final indices = buckets.keys.toList()..sort();
    return [
      for (final index in indices)
        FlSpot(
          buckets[index]!.x / buckets[index]!.count,
          buckets[index]!.y / buckets[index]!.count,
        ),
    ];
  }

  LineChartData _chartData(ColorScheme scheme, List<_HrSample> samples) {
    final spots = _chartSpots(samples);
    final series = HeartRateChartSeries(points: spots, zones: _zones);
    final bars = series.buildBars();
    // Transparent overlay owning touch, so a scrub snaps to a single sample
    // rather than to each zone bar (which share boundary crossing points).
    _touchBarIndex = bars.length;
    bars.add(
      LineChartBarData(
        spots: series.spots,
        isCurved: true,
        curveSmoothness: 0.15,
        barWidth: 0,
        color: Colors.transparent,
        dotData: const FlDotData(show: false),
      ),
    );
    final ys = spots.map((spot) => spot.y);
    final yMin = (ys.reduce((a, b) => a < b ? a : b) / 10).floor() * 10.0;
    final rawMax = (ys.reduce((a, b) => a > b ? a : b) / 10).ceil() * 10.0;
    // At least a 40 bpm span so the curve isn't squashed flat on a calm day.
    final yMax = rawMax - yMin < 40 ? yMin + 40 : rawMax;
    final yInterval = ((yMax - yMin) / 4 / 10).ceil() * 10.0;
    return LineChartData(
      minX: _leftX,
      maxX: _rightX,
      minY: yMin,
      maxY: yMax,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: scheme.onSurface.withValues(alpha: 0.06),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: _titles(yInterval),
      lineTouchData: _touch(scheme),
      lineBarsData: bars,
    );
  }

  LineTouchData _touch(ColorScheme scheme) {
    return LineTouchData(
      // Only the transparent overlay (barWidth 0) shows a touch dot — otherwise
      // both zone bars meeting at a crossing each draw one (a green + an orange
      // point at the same spot).
      getTouchedSpotIndicator: (barData, indexes) {
        if (barData.barWidth != 0) {
          return List<TouchedSpotIndicatorData?>.filled(indexes.length, null);
        }
        return [
          for (final _ in indexes)
            TouchedSpotIndicatorData(
              FlLine(
                color: scheme.onSurface.withValues(alpha: 0.35),
                strokeWidth: 1.5,
                dashArray: const [4, 4],
              ),
              FlDotData(
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: _zones.colorFor(spot.y),
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
            ),
        ];
      },
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        tooltipBorderRadius: BorderRadius.circular(8),
        getTooltipItems: (spots) => [
          for (final spot in spots)
            if (spot.barIndex != _touchBarIndex)
              null
            else
              LineTooltipItem(
                '${spot.y.round()} bpm',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(
                    text: '\n${_clockAt(spot.x)}',
                    style: TextStyle(
                      color: scheme.onInverseSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  /// Wall-clock HH:mm of a chart X value (hours relative to [_wholeHour]).
  String _clockAt(double x) {
    final time = _wholeHour.add(Duration(seconds: (x * 3600).round()));
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  FlTitlesData _titles(double yInterval) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: yInterval,
          reservedSize: 32,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              '${value.round()}',
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: _rangeHours <= 6 ? 2 : _rangeHours / 4,
          reservedSize: 22,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) {
            final clock = _wholeHour.add(Duration(hours: value.round()));
            return SideTitleWidget(
              meta: meta,
              child: Text(
                '${clock.hour.toString().padLeft(2, '0')}:00',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          },
        ),
      ),
    );
  }
}
