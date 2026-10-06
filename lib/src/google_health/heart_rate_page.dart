import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/google_health/pulse_sync.dart';
import 'package:insulink/src/google_health/heart_rate_chart_series.dart';
import 'package:insulink/src/google_health/heart_rate_zones.dart';
import 'package:insulink/src/google_health/heart_rate_zones_sheet.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/day_pager.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/base/stat_strip.dart';
import 'package:insulink/src/google_health/heart_rate_hero.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

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
  static const _storage = FlutterSecureStorage();
  static const _pulseStore = IntradayPulseStore();

  /// In-process per-day cache of the last curve read from the store, so
  /// reopening the page (or switching days back) shows it instantly instead of a
  /// loader while the store/Health-Connect refresh runs. Persistence lives in
  /// [_pulseStore]; this is only a synchronous shortcut.
  static final Map<DateTime, List<_HrSample>> _memory = {};

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

  /// Loads the day's 24 h window ending at [_end]; the 6/12 h views just
  /// re-window this without re-reading. Shows the in-process [_memory] curve
  /// instantly if present, then swaps in the refreshed one from [_refresh].
  Future<List<_HrSample>> _load() {
    _end = _isToday ? DateTime.now() : _day.add(const Duration(days: 1));
    final day = _day;
    final refreshed = _refresh(day);
    final cached = _memory[day];
    if (cached == null) {
      return refreshed;
    }
    refreshed.then((samples) {
      if (mounted && _day == day) {
        setState(() {
          _future = Future.value(samples);
        });
      }
    });
    return Future.value(cached);
  }

  /// Ingests fresh Health Connect samples into [_pulseStore] (and syncs them),
  /// then reads the window back FROM the store — the store, not Health Connect,
  /// is the source of truth, so the curve also draws from backend-pulled data on
  /// a device without Health Connect.
  Future<List<_HrSample>> _refresh(DateTime day) async {
    final from = _end.subtract(const Duration(hours: 24));
    final fresh = await GoogleHealthImporter().heartRateBetween(from, _end);
    if (fresh.isNotEmpty) {
      final touched = await _pulseStore.merge(fresh);
      PulseSync().push(touched);
    }
    final curve = await _pulseStore.rangeCurve(from, _end);
    _memory[day] = curve;
    return curve;
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
            icon: const Icon(PhosphorIconsBold.slidersHorizontal),
            tooltip: Locales.string(context, 'google_health.hr_zones.title'),
            onPressed: _editZones,
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: HeartRateHero(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: DayPager(
              date: _day,
              onPrevious: () => _shift(-1),
              onNext: _isToday ? null : () => _shift(1),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_HrSample>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final samples = snapshot.data ?? const [];
                if (samples.isEmpty) {
                  return Center(
                    child: LocaleText('google_health.detail.empty'),
                  );
                }
                return _content(context, samples);
              },
            ),
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

  // For today the right edge rolls to now (captured at build) so live samples
  // streaming past the load-time [_end] stay on-chart; past days pin to [_end].
  double get _rightX => _xOf(_isToday ? DateTime.now() : _end);
  double get _leftX => _rightX - _rangeHours;

  /// Live BLE samples the worn band is streaming now, newer than the freshest
  /// Health Connect sample — Health Connect lags the band by hours, so this
  /// bridges the gap to the live pulse. Only for today.
  List<_HrSample> _mergeLive(BuildContext context, List<_HrSample> hc) {
    if (!_isToday) {
      return hc;
    }
    final live = context.read<GoogleHealthState>().liveHrMonitor.liveHistory;
    final cutoff = hc.isEmpty ? null : hc.last.at;
    final extra = [
      for (final sample in live)
        if (cutoff == null || sample.at.isAfter(cutoff)) sample,
    ];
    return extra.isEmpty ? hc : [...hc, ...extra];
  }

  Widget _content(BuildContext context, List<_HrSample> hcSamples) {
    final monitor = context.read<GoogleHealthState>().liveHrMonitor;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) =>
          _contentBody(context, _mergeLive(context, hcSamples)),
    );
  }

  Widget _contentBody(BuildContext context, List<_HrSample> samples) {
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
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 96),
      children: [
        StatStrip(
          cells: [
            _bpmCell(context, 'google_health.hr_avg', avg.round()),
            _bpmCell(
              context,
              'google_health.hr_min',
              bpms.reduce((low, value) => low < value ? low : value),
            ),
            _bpmCell(
              context,
              'google_health.hr_max',
              bpms.reduce((high, value) => high > value ? high : value),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedToggle<int>.page(
          expand: true,
          selected: _rangeHours,
          onChanged: _setRange,
          options: const [
            (value: 24, label: '24 h'),
            (value: 12, label: '12 h'),
            (value: 6, label: '6 h'),
          ],
        ),
        const SizedBox(height: 10),
        _chartCard(context, visible),
      ],
    );
  }

  MetricCell _bpmCell(BuildContext context, String labelKey, int value) => (
    label: Locales.string(context, labelKey),
    value: sportInt(value),
    unit: 'bpm',
  );

  /// The chart in a panel, with a key for the violet highlight above it.
  Widget _chartCard(BuildContext context, List<_HrSample> samples) {
    final colors = context.ink;
    return InkPanel(
      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              spacing: 10,
              children: [
                SizedBox(
                  width: 16,
                  child: Divider(thickness: 1.5, color: colors.pulseHigh),
                ),
                Text(
                  Locales.string(
                    context,
                    'google_health.hr_highlight',
                    params: ['${_zones.elevated}'],
                  ),
                  style: InkText.caption.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 240, child: LineChart(_chartData(colors, samples))),
        ],
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
          : (
              x: current.x + x,
              y: current.y + sample.bpm,
              count: current.count + 1,
            );
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

  /// Accent below the elevated threshold, violet from there on: a raised pulse
  /// is not a warning, so neither red nor amber.
  List<Color> _palette(InsulinkColors colors) => [
    colors.accent,
    colors.pulseHigh,
    colors.pulseHigh,
  ];

  LineChartData _chartData(InsulinkColors colors, List<_HrSample> samples) {
    final spots = _chartSpots(samples);
    final series = HeartRateChartSeries(
      points: spots,
      zones: _zones,
      palette: _palette(colors),
    );
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
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.line, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: _zones.elevated.toDouble(),
            color: colors.pulseHigh.withValues(alpha: 0.7),
            strokeWidth: 1,
            dashArray: const [3, 4],
          ),
        ],
      ),
      titlesData: _titles(colors, yInterval),
      lineTouchData: _touch(colors),
      lineBarsData: bars,
    );
  }

  LineTouchData _touch(InsulinkColors colors) {
    final scheme = Theme.of(context).colorScheme;
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
                  color: _palette(colors)[_zones.zoneOf(spot.y)],
                  strokeColor: colors.ground,
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

  FlTitlesData _titles(InsulinkColors colors, double yInterval) {
    final style = InkText.axis.copyWith(fontSize: 12, color: colors.muted);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: yInterval,
          reservedSize: 36,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text('${value.round()}', style: style),
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
              fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
              child: Text(
                Locales.string(
                  context,
                  'overview.chart.hour',
                  params: ['${clock.hour}'],
                ),
                style: style,
              ),
            );
          },
        ),
      ),
    );
  }
}
