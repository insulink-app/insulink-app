import 'package:flutter/material.dart';

/// The red notification marker on a navigation tab: a plain dot for the
/// special "-1" attention flag (e.g. "no sensor"), otherwise a pill showing the
/// count. Positioned to sit on the tab icon's top-right.
class NavBadge extends StatelessWidget {
  const NavBadge({super.key, required this.count});

  /// -1 renders the plain dot; any other non-zero value renders the count pill.
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    return count == -1
        ? _dot(borderColor, theme.colorScheme)
        : _pill(borderColor, theme.colorScheme);
  }

  Widget _dot(Color borderColor, ColorScheme scheme) {
    return Positioned(
      right: 10,
      top: 0,
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: scheme.error,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1),
        ),
      ),
    );
  }

  Widget _pill(Color borderColor, ColorScheme scheme) {
    return Positioned(
      right: 5,
      top: 0,
      child: Container(
        width: count < 10 ? 20 : null,
        height: 20,
        padding: count < 10
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          count.toString(),
          style: TextStyle(
            color: scheme.onError,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
