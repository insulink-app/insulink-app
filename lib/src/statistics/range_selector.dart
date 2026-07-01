import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:provider/provider.dart';

/// Preset windows offered alongside the custom range, in days.
const _presets = [1, 3, 7, 30, 90];

/// Statistics-window selector driving [G7Controller]: equal-width segments (one
/// per preset, like the tab control above) plus a calendar segment that opens
/// the native date-range picker. The picked custom range is shown as a caption
/// below so the segment labels stay compact. Selecting a segment updates all
/// statistics views.
class StatisticsRangeSelector extends StatelessWidget {
  const StatisticsRangeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<G7Controller>();
    final isCustom = controller.statsIsCustom;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final days in _presets)
                Expanded(
                  child: _segment(
                    context,
                    selected:
                        !isCustom && controller.statsPreset.inDays == days,
                    onTap: () => controller.statsPreset = Duration(days: days),
                    child: Text(
                      Locales.string(context, 'statistics.window.d$days'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              Expanded(
                child: _segment(
                  context,
                  selected: isCustom,
                  onTap: () => _pickCustom(context, controller),
                  child: const Icon(Icons.date_range, size: 18),
                ),
              ),
            ],
          ),
        ),
        if (isCustom) _customCaption(context, controller),
      ],
    );
  }

  Widget _segment(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Plain tappable segment (not a ChoiceChip) so no Material-3 selection
    // overlay flashes the accent colour on tap. Selection is a grey fill only —
    // border and size stay constant so the segment never resizes.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? onSurface.withValues(alpha: 0.24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _customCaption(BuildContext context, G7Controller controller) {
    final from = controller.statsCustomFrom;
    final to = controller.statsCustomTo;
    if (from == null || to == null) {
      return const SizedBox.shrink();
    }
    final locale = MaterialLocalizations.of(context);
    final label =
        '${locale.formatShortDate(from)} – '
        '${locale.formatShortDate(to.subtract(const Duration(days: 1)))}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    G7Controller controller,
  ) async {
    final now = DateTime.now();
    final current = controller.statsCustomFrom != null
        ? DateTimeRange(
            start: controller.statsCustomFrom!,
            end: controller.statsCustomTo!.subtract(const Duration(days: 1)),
          )
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: current,
    );
    if (picked != null) {
      controller.setStatsCustomRange(
        picked.start,
        picked.end.add(const Duration(days: 1)),
      );
    }
  }
}
