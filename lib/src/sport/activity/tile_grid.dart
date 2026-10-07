import 'package:flutter/material.dart';

/// A 2-column grid of summary boxes with even gutters, sizing each tile to half
/// the available width.
///
/// The plain layout, shared by [ReorderableTileGrid] (which wraps every tile in
/// its drag machinery) and the all-values page (which must not reorder anything).
/// [tileBuilder] is handed the measured tile width because a dragged tile's
/// floating copy has no parent constraints and must be given one.
class TileGrid<T> extends StatelessWidget {
  const TileGrid({super.key, required this.tiles, required this.tileBuilder});

  final List<T> tiles;
  final Widget Function(BuildContext context, T tile, double width) tileBuilder;

  static const _gutter = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - _gutter) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < tiles.length; index += 2) ...[
              if (index > 0) const SizedBox(height: _gutter),
              _row(
                tileBuilder(context, tiles[index], tileWidth),
                index + 1 < tiles.length
                    ? tileBuilder(context, tiles[index + 1], tileWidth)
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }

  /// One grid row. [IntrinsicHeight] so both tiles take the taller one's height
  /// (a two-line label must not leave its neighbour short), and a lone trailing
  /// tile keeps its half width rather than stretching across, so the columns stay
  /// aligned down the whole grid.
  Widget _row(Widget first, Widget? second) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: _gutter),
          Expanded(child: second ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
