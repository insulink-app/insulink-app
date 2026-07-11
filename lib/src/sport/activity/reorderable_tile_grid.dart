import 'package:flutter/material.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/sport/activity/tile_layout_state.dart';

/// A 2-column grid of summary boxes that can be reordered by long-pressing a box
/// and dragging it onto another (a short tap still opens the box's detail page).
/// Shared by the Sport "Today" grid, the overview boxes and the nutrition stats.
/// On drop it persists the new order via [state] and syncs the settings blob.
class ReorderableTileGrid<T extends Enum> extends StatelessWidget {
  const ReorderableTileGrid({
    super.key,
    required this.tiles,
    required this.state,
    required this.tileBuilder,
  });

  final List<T> tiles;
  final TileLayoutState<T> state;
  final Widget Function(BuildContext, T) tileBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 12) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < tiles.length; index += 2) ...[
              if (index > 0) const SizedBox(height: 12),
              _row(
                _draggable(context, tiles[index], tileWidth),
                index + 1 < tiles.length
                    ? _draggable(context, tiles[index + 1], tileWidth)
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _draggable(BuildContext context, T tile, double width) {
    final child = tileBuilder(context, tile);
    return DragTarget<T>(
      onWillAcceptWithDetails: (details) => details.data != tile,
      onAcceptWithDetails: (details) => _onDrop(context, details.data, tile),
      builder: (context, candidate, rejected) {
        return LongPressDraggable<T>(
          data: tile,
          feedback: _feedback(width, child),
          childWhenDragging: Opacity(opacity: 0.3, child: child),
          child: AnimatedScale(
            scale: candidate.isEmpty ? 1.0 : 1.05,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        );
      },
    );
  }

  /// The floating tile shown under the finger while dragging: an elevated,
  /// slightly enlarged copy at the real tile width (feedback has no parent
  /// constraints, so the width must be given).
  Widget _feedback(double width, Widget child) {
    return Transform.scale(
      scale: 1.04,
      child: Material(
        color: Colors.transparent,
        elevation: 10,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  Future<void> _onDrop(BuildContext context, T from, T to) async {
    await state.moveTile(from, to);
    if (context.mounted) {
      await ProfileSettings().push(context);
    }
  }

  Widget _row(Widget left, Widget? right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
