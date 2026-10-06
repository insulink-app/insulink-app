import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/overview/all_values_page.dart';
import 'package:insulink/src/overview/overview_box.dart';
import 'package:insulink/src/overview/overview_box_builder.dart';
import 'package:insulink/src/overview/overview_layout.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/reorderable_tile_grid.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/sport/activity/tile_layout_editor.dart';
import 'package:insulink/src/theme/insulink_colors.dart';
import 'package:insulink/src/theme/insulink_text_styles.dart';
import 'package:provider/provider.dart';

/// Personalizable summary boxes on the overview: Sport metrics AND nutrition
/// boxes in ONE section with a single settings button. The user picks which
/// boxes and their order (drag to reorder, tune icon to show/hide). Reuses the
/// shared grid + editor and both tile builders.
class OverviewBoxes extends StatelessWidget {
  const OverviewBoxes({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<OverviewLayoutState>();
    final builder = OverviewBoxBuilder.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  Locales.string(context, 'date.today'),
                  style: InsulinkTextStyles.sectionTitle,
                ),
              ),
              _headerButton(
                context,
                PhosphorIconsRegular.squaresFour,
                'overview.boxes.all',
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AllValuesPage(),
                  ),
                ),
              ),
              _headerButton(
                context,
                PhosphorIconsRegular.slidersHorizontal,
                'sport.layout.title',
                () => _edit(context, layout),
              ),
            ],
          ),
        ),
        ReorderableTileGrid<OverviewBox>(
          tiles: layout.visible(true),
          state: layout,
          tileBuilder: builder.build,
        ),
      ],
    );
  }

  /// One muted header action on a 44 px target. Muted, not the accent: these
  /// are controls for the section, not affordances that carry the brand.
  Widget _headerButton(
    BuildContext context,
    IconData icon,
    String tooltipKey,
    VoidCallback onPressed,
  ) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      tooltip: Locales.string(context, tooltipKey),
      icon: Icon(icon, size: 20, color: context.insulinkColors.muted),
      onPressed: onPressed,
    );
  }

  Future<void> _edit(BuildContext context, OverviewLayoutState layout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TileLayoutEditor<OverviewBox>(
          state: layout,
          titleKey: 'sport.layout.title',
          hintKey: 'sport.layout.hint',
          icon: overviewBoxIcon,
          labelKey: overviewBoxLabelKey,
        ),
      ),
    );
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }
}
