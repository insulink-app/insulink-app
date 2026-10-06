import 'package:flutter/material.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/chart/chart_sync.dart';
import 'package:insulink/src/overview/chart/insulin_bar_painter.dart';
import 'package:insulink/src/overview/chart/insulin_chart_series.dart';
import 'package:insulink/src/theme/insulin_colors.dart';

/// The insulin that went in over the stretch of time the glucose chart above is
/// showing, basal and bolus told apart by colour.
///
/// Drawn under the glucose chart and over the SAME window, sharing its plot
/// geometry down to the pixel: [axisInset] matches the glucose chart's right
/// `reservedSize`, so a bar sits under the glucose it belongs to rather than
/// beside it. Get that wrong and the two charts are two pictures.
///
/// One shared axis in units, not two. A basal hour is around a unit and a bolus
/// is several, so the boluses do tower over the basal, and that is the true
/// proportion rather than something to correct for with a second scale.
class InsulinBarChart extends StatefulWidget {
  const InsulinBarChart({
    super.key,
    required this.series,
    required this.sync,
    this.showMeals = false,
  });

  final InsulinChartSeries series;

  /// What this chart shares with the glucose chart above: the window, the axis
  /// labels it draws for the pair, and the scrub either of them starts.
  final ChartSync sync;

  /// Whether the glucose chart's meal lines are on, so they can be continued
  /// through this one.
  final bool showMeals;

  /// The width of the axis label strip on the RIGHT of both charts. Must equal
  /// the glucose chart's rightTitles `reservedSize`, which is what makes the two
  /// x axes the same axis. The plot starts at the left edge.
  static const double axisInset = 36;

  /// A bolus is a moment, so it keeps a fixed width. Basal is not: it is drawn
  /// as wide as the hour it covers, which makes it grow as the window narrows.
  static const double bolusWidth = 7;

  @override
  State<InsulinBarChart> createState() => _InsulinBarChartState();
}

class _InsulinBarChartState extends State<InsulinBarChart> {
  /// Where the pointer is, which is the SHARED scrub rather than one of this
  /// chart's own: a finger on the glucose chart above has to read out here too,
  /// and a finger here has to read out up there.
  double? get _scrub => widget.sync.scrub;

  InsulinBar? get _touched {
    final fraction = _scrub;
    return fraction == null ? null : widget.series.nearest(fraction);
  }

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSyncChanged);
  }

  @override
  void didUpdateWidget(InsulinBarChart old) {
    super.didUpdateWidget(old);
    if (old.sync == widget.sync) {
      return;
    }
    old.sync.removeListener(_onSyncChanged);
    widget.sync.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    widget.sync.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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
        const SizedBox(height: 14),
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
                    labelColor: context.ink.muted,
                    mealColor: context.ink.muted,
                    scrubColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.35,
                    ),
                    gridColor: context.ink.line,
                    plotColor: context.ink.panel,
                    rightInset: InsulinBarChart.axisInset,
                    bolusWidth: InsulinBarChart.bolusWidth,
                    ticks: widget.sync.ticks,
                    mealFractions: _mealFractions(),
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
  /// never runs off the plot, and it sits at the BOTTOM: the bars hang from the
  /// top now, and a readout pinned up there would cover the thing it describes.
  List<Widget> _tooltip(BuildContext context, double width) {
    final touched = _touched;
    final fraction = _scrub;
    if (touched == null || fraction == null) {
      return const [];
    }
    final theme = Theme.of(context);
    final plotWidth = width - InsulinBarChart.axisInset;
    final x = fraction * plotWidth;
    final flip = x > width - _tooltipWidth - 8;
    return [
      Positioned(
        bottom: InsulinBarPainter.bottomInset + 4,
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
                Locales.string(
                  context,
                  'injection.bolus.value',
                  params: [sportDecimal(touched.units, 2)],
                ),
                style: TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                _describe(context, touched),
                style: TextStyle(
                  color: theme.colorScheme.onInverseSurface.withValues(
                    alpha: 0.7,
                  ),
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
    return bar.isBolus ? line : line.replaceFirst('#', _clock(bar.coversUntil));
  }

  String _clock(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  /// Where the glucose chart's meal lines cross this one. Empty while the
  /// overlay is off, so the two charts show the markers together or not at all.
  List<double> _mealFractions() {
    if (!widget.showMeals) {
      return const [];
    }
    return [
      for (final meal in widget.series.visibleMeals)
        widget.series.fractionOf(meal.time),
    ];
  }

  /// Publishes the pointer to the pair rather than keeping it, so the chart
  /// above draws its own readout at the same instant.
  void _pick(BuildContext context, double localX) {
    final box = context.findRenderObject() as RenderBox?;
    final width = (box?.size.width ?? 0) - InsulinBarChart.axisInset;
    if (width <= 0) {
      return;
    }
    widget.sync.setScrub((localX / width).clamp(0.0, 1.0), mirrored: true);
  }

  void _clear() => widget.sync.setScrub(null);

  /// The key, with each kind's total beside it, UNDER the plot. Above it, it sat
  /// between the two charts and read as a divider between them; the whole point
  /// is that they belong together.
  Widget _legend(BuildContext context) {
    final colors = context.insulin;
    return Row(
      spacing: 18,
      children: [
        _key(
          context,
          colors.basal,
          'overview.chart.insulin.basal',
          widget.series.basalUnits,
          round: false,
        ),
        _key(
          context,
          colors.bolus,
          'overview.chart.insulin.bolus',
          widget.series.bolusUnits,
          round: true,
        ),
      ],
    );
  }

  /// A swatch shaped like its bars (a block for basal, a dot for bolus), the
  /// kind muted and its total bold.
  Widget _key(
    BuildContext context,
    Color color,
    String labelKey,
    double units, {
    required bool round,
  }) {
    final ink = context.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(round ? 5 : 2),
          ),
        ),
        Text.rich(
          TextSpan(
            style: InkText.body.copyWith(
              fontWeight: FontWeight.w400,
              color: ink.muted,
            ),
            children: [
              TextSpan(text: '${Locales.string(context, labelKey)}  '),
              TextSpan(
                text: Locales.string(
                  context,
                  'injection.bolus.value',
                  params: [sportDecimal(units, 1)],
                ),
                style: TextStyle(fontWeight: FontWeight.w700, color: ink.text),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
