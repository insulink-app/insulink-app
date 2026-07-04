import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';
import 'package:insulink/src/sport/activity/today_tile_builder.dart';

/// Lets the user pick which summary boxes are shown and drag them into the order
/// they prefer. Works on any [TileLayoutState] (the Today grid or the overview),
/// which it mutates directly; the opener syncs the settings blob on return.
class TileLayoutEditor extends StatelessWidget {
  const TileLayoutEditor({
    super.key,
    required this.state,
    required this.titleKey,
    required this.hintKey,
  });

  final TileLayoutState state;
  final String titleKey;
  final String hintKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(titleKey),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: LocaleText(
                hintKey,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.all(12),
                onReorderItem: state.reorder,
                children: [for (final tile in state.order) _row(context, tile)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, TodayTile tile) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(tile),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(todayTileIcon(tile), color: scheme.primary),
        title: LocaleText(todayTileLabelKey(tile)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: state.isVisible(tile),
              onChanged: (value) => state.setVisible(tile, value),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.drag_handle, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
