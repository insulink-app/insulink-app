import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
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

  /// The presets on a pill track, a round calendar button beside it for a
  /// custom window, the same look as the sleep and weight pages.
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CgmController>();
    final isCustom = controller.statsIsCustom;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: InkSpace.panelMargin),
      child: Column(
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: SegmentedToggle<int>.page(
                  expand: true,
                  selected: isCustom ? -1 : controller.statsPreset.inDays,
                  onChanged: (days) =>
                      controller.statsPreset = Duration(days: days),
                  options: [
                    for (final days in _presets)
                      (
                        value: days,
                        label: Locales.string(
                          context,
                          'analysis.window.d$days',
                        ),
                      ),
                  ],
                ),
              ),
              HeaderIconButton(
                icon: PhosphorIconsRegular.calendarBlank,
                labelKey: 'sport.range.pick',
                statusColor: isCustom ? context.ink.accent : null,
                onTap: () => _pickCustom(context, controller),
              ),
            ],
          ),
          if (isCustom) _customCaption(context, controller),
        ],
      ),
    );
  }

  Widget _customCaption(BuildContext context, CgmController controller) {
    final from = controller.statsCustomFrom;
    final to = controller.statsCustomTo;
    if (from == null || to == null) {
      return const SizedBox.shrink();
    }
    final locale = MaterialLocalizations.of(context);
    final label = Locales.string(
      context,
      'date.range',
      params: [
        locale.formatShortDate(from),
        locale.formatShortDate(to.subtract(const Duration(days: 1))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        style: InkText.caption.copyWith(color: context.ink.muted),
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
