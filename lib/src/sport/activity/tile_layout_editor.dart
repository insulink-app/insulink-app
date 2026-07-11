import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// Lets the user pick which summary boxes are shown and drag them into the order
/// they prefer. Works on any [TileLayoutState] (the Today grid, the overview, the
/// nutrition stats), which it mutates directly; the opener syncs the settings blob
/// on return. [icon]/[labelKey] map a tile to its glyph + localization key.
///
/// A search field filters the list by label. Dragging to reorder is only offered
/// while the search is empty — with a filter active the reorder indices wouldn't
/// map back to the full order.
class TileLayoutEditor<T extends Enum> extends StatefulWidget {
  const TileLayoutEditor({
    super.key,
    required this.state,
    required this.titleKey,
    required this.hintKey,
    required this.icon,
    required this.labelKey,
  });

  final TileLayoutState<T> state;
  final String titleKey;
  final String hintKey;
  final IconData Function(T) icon;
  final String Function(T) labelKey;

  @override
  State<TileLayoutEditor<T>> createState() => _TileLayoutEditorState<T>();
}

class _TileLayoutEditorState<T extends Enum>
    extends State<TileLayoutEditor<T>> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Tiles whose localized label contains the query; the full order when empty.
  List<T> _matches(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.state.order;
    }
    return [
      for (final tile in widget.state.order)
        if (Locales.string(context, widget.labelKey(tile))
            .toLowerCase()
            .contains(query))
          tile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final filtering = _query.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(widget.titleKey),
      ),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final tiles = _matches(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchField(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: LocaleText(
                  widget.hintKey,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
              Expanded(child: _list(context, tiles, filtering)),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: TextField(
        controller: _query,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: Locales.string(context, 'sport.layout.search'),
          suffixIcon: _query.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _query.clear,
                ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<T> tiles, bool filtering) {
    if (filtering) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [for (final tile in tiles) _row(context, tile, false)],
      );
    }
    return ReorderableListView(
      padding: const EdgeInsets.all(12),
      onReorderItem: widget.state.reorder,
      children: [for (final tile in tiles) _row(context, tile, true)],
    );
  }

  Widget _row(BuildContext context, T tile, bool draggable) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(tile),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        tileColor: scheme.onSurface.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(widget.icon(tile), color: scheme.primary),
        title: LocaleText(widget.labelKey(tile)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: widget.state.isVisible(tile),
              onChanged: (value) => widget.state.setVisible(tile, value),
            ),
            const SizedBox(width: 4),
            if (draggable)
              const Icon(Icons.drag_handle, color: Colors.grey)
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}
