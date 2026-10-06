import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// An analysis chart with its title and one-line explanation above it, the
/// chart in a panel, and optionally the line/band key under it (patterns).
class AnalysisChartSection extends StatelessWidget {
  const AnalysisChartSection({
    super.key,
    required this.titleKey,
    required this.hintKey,
    required this.chart,
    this.withKey = false,
  });

  final String titleKey;
  final String hintKey;
  final Widget chart;

  /// Show "Ø" (the line) and "Streuung" (the band) under the chart.
  final bool withKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        14,
        InkSpace.panelMargin,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                LocaleText(titleKey, style: InkText.section),
                LocaleText(
                  hintKey,
                  style: InkText.label.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          InkPanel(
            padding: const EdgeInsets.fromLTRB(12, 22, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 260, child: chart),
                if (withKey) ...[const SizedBox(height: 14), _key(colors)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(InsulinkColors colors) {
    Widget swatch(Color color, double height) => Container(
      width: 18,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
    final style = InkText.label.copyWith(color: colors.muted);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        spacing: 10,
        children: [
          swatch(colors.text, 3),
          LocaleText('analysis.patterns.mean', style: style),
          const SizedBox(width: 10),
          swatch(colors.accent.withValues(alpha: 0.35), 10),
          LocaleText('analysis.patterns.spread', style: style),
        ],
      ),
    );
  }
}
