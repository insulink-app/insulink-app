import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/chart/insulin_bar_painter.dart';
import 'package:insulink/src/overview/chart/insulin_chart_series.dart';
import 'package:insulink/src/theme/insulin_colors.dart';

/// The insulin that went in over the stretch of time the glucose chart above is
/// showing, basal and bolus told apart by colour.
///
/// Drawn under the glucose chart and over the SAME window, sharing its plot
/// geometry down to the pixel: [axisInset] matches the glucose chart's left
/// `reservedSize`, so a bar sits under the glucose it belongs to rather than
/// beside it. Get that wrong and the two charts are two pictures.
///
/// One shared axis in units, not two. A basal hour is around a unit and a bolus
/// is several, so the boluses do tower over the basal, and that is the true
/// proportion rather than something to correct for with a second scale.
class InsulinBarChart extends StatefulWidget {
  const InsulinBarChart({super.key, required this.series});

  final InsulinChartSeries series;

  /// The width of the left axis strip. Must equal the glucose chart's leftTitles
  /// `reservedSize`, which is what makes the two x axes the same axis.
  static const double axisInset = 24;

  /// A bolus is a moment, so it keeps a fixed width. Basal is not: it is drawn
  /// as wide as the hour it covers, which makes it grow as the window narrows.
  static const double bolusWidth = 9;

  @override
  State<InsulinBarChart> createState() => _InsulinBarChartState();
}

class _InsulinBarChartState extends State<InsulinBarChart> {
  InsulinBar? _touched;
  double? _scrub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: widget.series.isEmpty
              ? Center(
                  child: LocaleText(
                    'overview.chart.insulin.empty',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _plot(context),
        ),
        const SizedBox(height: 6),
        _legend(context),
      ],
    );
  }

  /// The bars, with the pointer picking one out. A mouse hovers and a finger
  /// drags; both land on the same handler, so the chart behaves the same way on
  /// a phone and on a desktop.
  Widget _plot(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.insulin;
    return MouseRegion(
      onHover: (event) => _pick(context, event.localPosition.dx),
      onExit: (_) => _clear(),
      child: GestureDetector(
        onTapDown: (details) => _pick(context, details.localPosition.dx),
        onHorizontalDragUpdate: (details) =>
            _pick(context, details.localPosition.dx),
        onHorizontalDragEnd: (_) => _clear(),
        onTapUp: (_) => _clear(),
        onTapCancel: _clear,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: InsulinBarPainter(
                    series: widget.series,
                    basal: colors.basal,
                    bolus: colors.bolus,
                    labelColor: theme.colorScheme.onSurfaceVariant,
                    scrubColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    leftInset: InsulinBarChart.axisInset,
                    bolusWidth: InsulinBarChart.bolusWidth,
                    scrubFraction: _scrub,
                    highlighted: _touched,
                  ),
                ),
              ),
              ..._tooltip(context, constraints.maxWidth),
            ],
          ),
        ),
      ),
    );
  }

  /// The readout, in the same pill the glucose chart above uses: an
  /// inverse-surface card with the value in bold and the time under it. Copied
  /// rather than styled afresh, because a second look for the same gesture is
  /// what made the two charts read as two unrelated things.
  ///
  /// It follows the scrub and flips to the other side near the right edge, so it
  /// never runs off the plot.
  List<Widget> _tooltip(BuildContext context, double width) {
    final touched = _touched;
    final fraction = _scrub;
    if (touched == null || fraction == null) {
      return const [];
    }
    final theme = Theme.of(context);
    final plotWidth = width - InsulinBarChart.axisInset;
    final x = InsulinBarChart.axisInset + fraction * plotWidth;
    final flip = x > width - _tooltipWidth - 8;
    return [
      Positioned(
        top: 0,
        left: flip ? null : x + 8,
        right: flip ? width - x + 8 : null,
        child: Container(
          width: _tooltipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${touched.units.toStringAsFixed(2)} U',
                style: TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                _describe(context, touched),
                style: TextStyle(
                  color: theme.colorScheme.onInverseSurface
                      .withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static const double _tooltipWidth = 96;

  /// A basal bar covers an hour and a bolus is a moment, so they are read out
  /// differently: saying "09:00" for an hour of basal would invite reading it as
  /// a dose given then.
  String _describe(BuildContext context, InsulinBar bar) {
    final key = bar.isBolus
        ? 'overview.chart.insulin.at_moment'
        : 'overview.chart.insulin.over_hour';
    final line = Locales.string(context, key).replaceFirst('#', _clock(bar.at));
    return bar.isBolus
        ? line
        : line.replaceFirst('#', _clock(bar.coversUntil));
  }

  String _clock(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  void _pick(BuildContext context, double localX) {
    final box = context.findRenderObject() as RenderBox?;
    final width = (box?.size.width ?? 0) - InsulinBarChart.axisInset;
    if (width <= 0) {
      return;
    }
    final fraction =
        ((localX - InsulinBarChart.axisInset) / width).clamp(0.0, 1.0);
    final nearest = widget.series.nearest(fraction);
    if (nearest != _touched || fraction != _scrub) {
      setState(() {
        _touched = nearest;
        _scrub = fraction;
      });
    }
  }

  void _clear() {
    if (_touched != null || _scrub != null) {
      setState(() {
        _touched = null;
        _scrub = null;
      });
    }
  }

  /// The key, with each kind's total beside it, UNDER the plot. Above it, it sat
  /// between the two charts and read as a divider between them; the whole point
  /// is that they belong together.
  Widget _legend(BuildContext context) {
    final colors = context.insulin;
    return Row(
      children: [
        SizedBox(width: InsulinBarChart.axisInset),
        _key(context, colors.basal, 'overview.chart.insulin.basal',
            widget.series.basalUnits),
        const SizedBox(width: 14),
        _key(context, colors.bolus, 'overview.chart.insulin.bolus',
            widget.series.bolusUnits),
      ],
    );
  }

  Widget _key(
    BuildContext context,
    Color color,
    String labelKey,
    double units,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          Locales.string(context, labelKey)
              .replaceFirst('#', units.toStringAsFixed(1)),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
