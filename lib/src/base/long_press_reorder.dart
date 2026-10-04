import 'package:flutter/widgets.dart';

/// The phone's way of reordering a list, on every platform: a long press picks a
/// row up anywhere on it.
///
/// `ReorderableListView` does this by itself only on Android and iOS. On desktop
/// platforms, which include the browser demo, its default handles instead lay a
/// drag icon over the trailing end of every row, right on top of the row's own
/// menu or delete button. Lists use this with `buildDefaultDragHandles: false`.
extension LongPressReorder on List<Widget> {
  /// Each row wrapped in a long-press drag listener that carries the row's key,
  /// since `ReorderableListView` needs the key on its direct children.
  List<Widget> pickedUpByLongPress() => [
    for (final (index, row) in indexed)
      ReorderableDelayedDragStartListener(
        key: row.key,
        index: index,
        child: row,
      ),
  ];
}
