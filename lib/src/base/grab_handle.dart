import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The small centred pill at the top of a bottom sheet that signals it can be
/// dragged. Shared by every modal sheet so they look identical.
class GrabHandle extends StatelessWidget {
  const GrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: context.ink.muted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
