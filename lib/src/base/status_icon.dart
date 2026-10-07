import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A device glyph in a tinted 48 px disc with a status dot at its lower right,
/// ringed in the card colour: the connection's state lives in the dot alone.
class StatusIcon extends StatelessWidget {
  const StatusIcon({
    super.key,
    required this.icon,
    required this.statusColor,
    this.size = 48,
  });

  final IconData icon;
  final Color statusColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withValues(alpha: 0.14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: size * 0.46, color: colors.accent),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [BoxShadow(color: colors.panel, spreadRadius: 3)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
