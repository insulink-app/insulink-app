import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/analysis_segment.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Preset windows offered alongside the custom range, in days.
const _presets = [1, 3, 7, 30, 90];

/// Analysis-window selector driving [CgmController]: equal-width segments (one
/// per preset, like the tab control above) plus a calendar segment that opens
/// the native date-range picker. The picked custom range is shown as a caption
/// below so the segment labels stay compact. Selecting a segment updates all
/// analysis views.
class AnalysisRangeSelector extends StatelessWidget {
  const AnalysisRangeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final isCustom = controller.statsIsCustom;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final days in _presets)
                Expanded(
                  child: AnalysisSegment(
                    selected:
                        !isCustom && controller.statsPreset.inDays == days,
                    onTap: () => controller.statsPreset = Duration(days: days),
                    child: Text(
                      Locales.string(context, 'analysis.window.d$days'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              Expanded(
                child: AnalysisSegment(
                  selected: isCustom,
                  onTap: () => _pickCustom(context, controller),
                  child: const Icon(
                    PhosphorIconsBold.calendarBlank,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isCustom) _customCaption(context, controller),
      ],
    );
  }

  Widget _customCaption(BuildContext context, CgmController controller) {
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
    CgmController controller,
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
