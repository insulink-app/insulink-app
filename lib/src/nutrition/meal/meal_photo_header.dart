import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The meal's photo as the pinned header of the meal sheet, like the route map
/// of a training: large at the top, shrinking to a strip as the stats below are
/// scrolled up, and staying there. A tap opens it full screen.
///
/// [photo] is null while it downloads; a quiet panel holds the space. A photo
/// that failed to load is left out by the sheet altogether.
class MealPhotoHeader extends SliverPersistentHeaderDelegate {
  const MealPhotoHeader({required this.photo, required this.onTap});

  static const _expandedHeight = 510.0;
  static const _collapsedHeight = 250.0;
  static const _gap = 14.0;

  final Uint8List? photo;
  final VoidCallback onTap;

  @override
  double get maxExtent => _expandedHeight + _gap;

  @override
  double get minExtent => _collapsedHeight + _gap;

  @override
  bool shouldRebuild(MealPhotoHeader oldDelegate) => photo != oldDelegate.photo;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.ink;
    final loaded = photo;
    return ColoredBox(
      color: colors.panel,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _gap),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(InkRadius.panel),
          child: loaded == null
              ? ColoredBox(
                  color: colors.ground,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : Material(
                  child: Ink.image(
                    image: MemoryImage(loaded),
                    fit: BoxFit.cover,
                    child: InkWell(onTap: onTap),
                  ),
                ),
        ),
      ),
    );
  }
}
