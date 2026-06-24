import 'package:flutter/material.dart';

/// The small centred pill at the top of a bottom sheet that signals it can be
/// dragged. Shared by every modal sheet so they look identical.
class GrabHandle extends StatelessWidget {
  const GrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
