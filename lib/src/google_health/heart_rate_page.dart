import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';

typedef _HrSample = ({DateTime at, int bpm});

/// Intraday heart-rate curve for a single day (pulse over 24 h) with a day
/// picker and Ø / Min / Max header. Samples are read live from Health Connect
/// per day (see [GoogleHealthImporter.intradayHeartRate]), not from the daily archive.
class HeartRatePage extends StatefulWidget {
  const HeartRatePage({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  late DateTime _day = _today();
  late Future<List<_HrSample>> _future = _load();

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _day == _today();

  Future<List<_HrSample>> _load() => GoogleHealthImporter().intradayHeartRate(_day);

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
      ),
      body: Column(
        children: [
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

  Widget _content(BuildContext context, List<_HrSample> samples) {
    final scheme = Theme.of(context).colorScheme;
    final bpms = samples.map((sample) => sample.bpm);
    final avg = bpms.reduce((a, b) => a + b) / samples.length;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        _statsRow(context, scheme, avg.round(), bpms.reduce((a, b) => a < b ? a : b),
            bpms.reduce((a, b) => a > b ? a : b)),
        const SizedBox(height: 20),
        _chartCard(scheme, samples),
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

  LineChartData _chartData(ColorScheme scheme, List<_HrSample> samples) {
    final spots = [
      for (final sample in samples)
        FlSpot(
          sample.at.hour + sample.at.minute / 60,
          sample.bpm.toDouble(),
        ),
    ];
    return LineChartData(
      minX: 0,
      maxX: 24,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: _titles(),
      lineTouchData: _touch(scheme),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: scheme.error,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: scheme.error.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  LineTouchData _touch(ColorScheme scheme) {
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        getTooltipItems: (spots) => [
          for (final spot in spots)
            LineTooltipItem(
              '${spot.y.round()} bpm',
              TextStyle(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  FlTitlesData _titles() {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: true, reservedSize: 34),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 6,
          reservedSize: 22,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              '${value.toInt()}:00',
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
