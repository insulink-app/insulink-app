import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

/// A round 44 px header button: panel face, faint rim, a glyph in full text
/// colour, and optionally a status dot in its top-right corner.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.onTap,
    this.statusColor,
  });

  final IconData icon;

  /// Locale key read out by screen readers.
  final String labelKey;
  final VoidCallback onTap;

  /// Colour of the status dot; null draws none.
  final Color? statusColor;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.insulinkColors;
    return Semantics(
      button: true,
      label: Locales.string(context, labelKey),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _face(colors)),
            if (statusColor != null) _dot(colors),
          ],
        ),
      ),
    );
  }

  Widget _face(InsulinkColors colors) {
    return Material(
      color: colors.panel,
      shape: CircleBorder(side: BorderSide(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Icon(icon, size: 20, color: colors.text),
      ),
    );
  }

  /// A 10 px dot with a 2.5 px ring in the page colour, so it reads as sitting
  /// on top of the button rather than inside it.
  Widget _dot(InsulinkColors colors) {
    return Positioned(
      top: 1,
      right: 1,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: colors.ground, spreadRadius: 2.5)],
        ),
      ),
    );
  }
}
