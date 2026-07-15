import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/analysis/calendar/daily_time_in_range.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Calendar heatmap of daily time-in-range: one cell per day (Mon–Sun grid),
/// traffic-light coloured by how much of the day was in target. Reads the
/// long-term archive so it spans sensor swaps.
class CalendarHeatmapView extends StatelessWidget {
  const CalendarHeatmapView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    final tirByDay = DailyTimeInRange(controller.statsArchive, glucose).build();
    if (tirByDay.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsRegular.chartLineUp,
        titleKey: 'analysis.empty',
      );
    }
    final days = tirByDay.keys.toList()..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _weekdayHeader(context),
          const SizedBox(height: 4),
          for (final week in _weeks(days.first, days.last))
            Row(
              children: [
                for (final day in week)
                  Expanded(child: _cell(context, day, tirByDay, colors)),
              ],
            ),
          const SizedBox(height: 16),
          _Legend(colors: colors),
        ],
      ),
    );
  }

  /// The Mon–Sun weekday header.
  Widget _weekdayHeader(BuildContext context) {
    return Row(
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          Expanded(
            child: Center(
              child: Text(
                Locales.string(context, 'date.weekday.$weekday'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Full Mon-aligned weeks spanning [first]..[last] (rows of 7 days; days
  /// outside the data range render as empty padding cells).
  List<List<DateTime?>> _weeks(DateTime first, DateTime last) {
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks = <List<DateTime?>>[];
    var cursor = start;
    while (!cursor.isAfter(last)) {
      weeks.add([
        for (var column = 0; column < 7; column++)
          () {
            final day = cursor.add(Duration(days: column));
            return day.isBefore(first) || day.isAfter(last) ? null : day;
          }(),
      ]);
      cursor = cursor.add(const Duration(days: 7));
    }
    return weeks;
  }

  Widget _cell(
    BuildContext context,
    DateTime? day,
    Map<DateTime, double> tirByDay,
    GlucoseColors colors,
  ) {
    final tir = day == null ? null : tirByDay[day];
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _cellColor(tir, day != null, colors, onSurface),
            borderRadius: BorderRadius.circular(6),
          ),
          child: day == null
              ? null
              : Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: tir == null
                        ? onSurface.withValues(alpha: 0.4)
                        : Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  /// Traffic-light colour for a day's TIR; faint for a data-less in-range day,
  /// transparent for out-of-range padding.
  Color _cellColor(
    double? tir,
    bool inSpan,
    GlucoseColors colors,
    Color onSurface,
  ) {
    if (tir == null) {
      return inSpan ? onSurface.withValues(alpha: 0.06) : Colors.transparent;
    }
    return tirColor(tir, colors);
  }

  /// Shared TIR→colour scale (also used by the legend): green ≥70%, amber ≥50%,
  /// orange ≥30%, else red.
  static Color tirColor(double tir, GlucoseColors colors) {
    if (tir >= 0.7) {
      return colors.inRange;
    }
    if (tir >= 0.5) {
      return colors.high;
    }
    if (tir >= 0.3) {
      return Color.lerp(colors.high, colors.low, 0.5)!;
    }
    return colors.low;
  }
}

/// The four-bucket colour key under the grid.
class _Legend extends StatelessWidget {
  const _Legend({required this.colors});

  final GlucoseColors colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        _entry(context, 0.8, 'analysis.calendar.good'),
        _entry(context, 0.6, 'analysis.calendar.ok'),
        _entry(context, 0.4, 'analysis.calendar.fair'),
        _entry(context, 0.1, 'analysis.calendar.poor'),
      ],
    );
  }

  Widget _entry(BuildContext context, double tir, String labelKey) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: CalendarHeatmapView.tirColor(tir, colors),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        LocaleText(labelKey, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
