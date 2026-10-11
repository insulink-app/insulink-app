import 'package:flutter/material.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/base/stat_strip.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/daily_history/daily_metric.dart';

/// The key figures of the window in one strip: Ø / Tag, Gesamt and how many
/// days reached the goal for a summed metric; Ø, Min and Max for a rate.
class DailyHistoryStats extends StatelessWidget {
  const DailyHistoryStats({
    super.key,
    required this.days,
    required this.metric,
  });

  /// The days of the window, never empty.
  final List<DailyValue> days;
  final DailyMetric metric;

  Iterable<double> get _values => days.map((day) => day.value);

  double get _total => _values.fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    return StatStrip(
      cells: metric.summed ? _summedCells(context) : _rateCells(context),
    );
  }

  List<MetricCell> _summedCells(BuildContext context) => [
    _cell(context, 'sport.activity.detail.average', _total / days.length),
    _cell(context, 'sport.activity.detail.total', _total),
    if (metric.hasGoal) _reachedCell(context),
  ];

  List<MetricCell> _rateCells(BuildContext context) => [
    _cell(context, 'sport.weight.avg', _total / days.length),
    _cell(
      context,
      'sport.weight.min',
      _values.reduce((low, value) => low < value ? low : value),
    ),
    _cell(
      context,
      'sport.weight.max',
      _values.reduce((high, value) => high > value ? high : value),
    ),
  ];

  MetricCell _cell(BuildContext context, String key, double value) => (
    label: Locales.string(context, key),
    value: metric.format(value),
    unit: metric.unit,
  );

  MetricCell _reachedCell(BuildContext context) => (
    label: Locales.string(context, 'daily_history.goal_reached'),
    value: '${_values.where(metric.reached).length}',
    unit: '/ ${days.length}',
  );
}
