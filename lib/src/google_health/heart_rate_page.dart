import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/google_health/intraday_pulse_store.dart';
import 'package:insulink/src/google_health/pulse_sync.dart';
import 'package:insulink/src/google_health/heart_rate_chart.dart';
import 'package:insulink/src/base/pinch_zoom_listener.dart';
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
  static final Map<DateTime, List<HrSample>> _memory = {};

  late DateTime _day = _today();

  /// Right edge of the window (captured when the data is loaded so the X axis and
  /// the query share one anchor): now for today, else the selected day's end.
  late DateTime _end;

  /// The day's curve once anything is known, newest source last; null shows
  /// the loader. Kept across a refresh so the page never blanks to load.
  List<HrSample>? _samples;

  /// Visible window in hours, ending [_panHours] before [_end]. The toggle
  /// jumps to 24 / 12 / 6; two fingers zoom it between [_minRangeHours] and
  /// 24 and pan it across the loaded day, like the glucose chart.
  double _rangeHours = 24;
  double _panHours = 0;
  static const double _minRangeHours = 0.5;

  /// User-configurable pulse zones (green / orange / red).
  HeartRateZones _zones = const HeartRateZones();

  @override
  void initState() {
    super.initState();
    _load();
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

  /// Shows the day straight away: the in-process [_memory] curve if there is
  /// one, else what the local pulse store already holds. Health Connect is read
  /// behind it and swapped in when it answers, so the page never waits on it.
  void _load() {
    _end = _isToday ? DateTime.now() : _day.add(const Duration(days: 1));
    final day = _day;
    _samples = _memory[day];
    if (_samples == null) {
      _pulseStore.rangeCurve(_from, _end).then((stored) {
        if (stored.isNotEmpty && _samples == null) {
          _show(day, stored);
        }
      });
    }
    _refresh(day).then((fresh) => _show(day, fresh));
  }

  DateTime get _from => _end.subtract(const Duration(hours: 24));

  void _show(DateTime day, List<HrSample> samples) {
    if (mounted && _day == day) {
      setState(() => _samples = samples);
    }
  }

  /// Ingests fresh Health Connect samples into [_pulseStore] (and syncs them),
  /// then reads the window back FROM the store — the store, not Health Connect,
  /// is the source of truth, so the curve also draws from backend-pulled data on
  /// a device without Health Connect. A Health Connect failure still answers
  /// with what the store holds.
  Future<List<HrSample>> _refresh(DateTime day) async {
    final from = _from;
    final end = _end;
    try {
      final fresh = await GoogleHealthImporter().heartRateBetween(from, end);
      if (fresh.isNotEmpty) {
        final touched = await _pulseStore.merge(fresh);
        PulseSync().push(touched);
      }
    } catch (_) {}
    final curve = await _pulseStore.rangeCurve(from, end);
    _memory[day] = curve;
    return curve;
  }

  Future<void> _loadRange() async {
    final stored = int.tryParse(await _storage.read(key: _kRangeKey) ?? '');
    if (mounted && (stored == 6 || stored == 12 || stored == 24)) {
      setState(() => _rangeHours = stored!.toDouble());
    }
  }

  void _setRange(int hours) {
    setState(() {
      _rangeHours = hours.toDouble();
      _panHours = _panHours.clamp(0, 24 - _rangeHours);
    });
    _storage.write(key: _kRangeKey, value: '$hours');
  }

  /// Zooms around the fingers (the time under them stays put) and pans by
  /// their sideways travel; fingers moving right bring earlier pulse in.
  void _pinch(PinchStep step) {
    if (step.scale <= 0) {
      return;
    }
    final oldRange = _rangeHours;
    final newRange = (oldRange / step.scale).clamp(_minRangeHours, 24.0);
    var delta = (oldRange - newRange) * (1 - step.focalFraction);
    if (step.plotWidth > 0) {
      delta += step.focalTravelX * newRange / step.plotWidth;
    }
    setState(() {
      _rangeHours = newRange;
      _panHours = (_panHours + delta).clamp(0, 24 - newRange);
    });
  }

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (next.isAfter(_today())) {
      return;
    }
    setState(() {
      _day = next;
      _panHours = 0;
      _load();
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
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final samples = _samples;
    if (samples == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (samples.isEmpty && !_isToday) {
      return Center(child: LocaleText('google_health.detail.empty'));
    }
    return _content(context, samples);
  }

  /// Whole clock hour at/just before [_end] — the X=0 reference, so integer X
  /// values land on whole clock hours (the tick labels).
  DateTime get _wholeHour =>
      DateTime(_end.year, _end.month, _end.day, _end.hour);

  /// Chart X of a time: hours relative to [_wholeHour] (negative = earlier).
  double _xOf(DateTime at) => at.difference(_wholeHour).inSeconds / 3600;

  /// For today the right edge rolls to now so live samples streaming past the
  /// load-time [_end] stay on the chart; past days pin to [_end]. A pan moves
  /// it back.
  double get _rightX => _xOf(_isToday ? DateTime.now() : _end) - _panHours;
  double get _leftX => _rightX - _rangeHours;

  /// Live BLE samples the worn band is streaming now, newer than the freshest
  /// Health Connect sample — Health Connect lags the band by hours, so this
  /// bridges the gap to the live pulse. Only for today.
  List<HrSample> _mergeLive(BuildContext context, List<HrSample> hc) {
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

  Widget _content(BuildContext context, List<HrSample> hcSamples) {
    final monitor = context.read<GoogleHealthState>().liveHrMonitor;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) =>
          _contentBody(context, _mergeLive(context, hcSamples)),
    );
  }

  Widget _contentBody(BuildContext context, List<HrSample> samples) {
    final visible = [
      for (final sample in samples)
        if (_xOf(sample.at) >= _leftX && _xOf(sample.at) <= _rightX) sample,
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
          selected: _rangeHours == _rangeHours.roundToDouble()
              ? _rangeHours.round()
              : -1,
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
  Widget _chartCard(BuildContext context, List<HrSample> samples) {
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
          SizedBox(
            height: 240,
            child: PinchZoomListener(
              axisInset: 36,
              onPinch: _pinch,
              child: HeartRateChart(
                samples: samples,
                zones: _zones,
                wholeHour: _wholeHour,
                leftX: _leftX,
                rightX: _rightX,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
