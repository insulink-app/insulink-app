import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A round 44 px header button: panel face, faint rim, a glyph in full text
/// colour, and optionally a status dot in its top-right corner.
///
/// [HeaderIconButton.plain] is the same control without a face, in the muted
/// tone: the controls beside a section title and in a pushed page's bar.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.onTap,
    this.statusColor,
  }) : plain = false;

  const HeaderIconButton.plain({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.onTap,
    this.statusColor,
  }) : plain = true;

  final IconData icon;

  /// Locale key read out by screen readers.
  final String labelKey;

  /// Null draws the button dimmed and reports it as disabled.
  final VoidCallback? onTap;

  /// Colour of the status dot; null draws none.
  final Color? statusColor;

  /// No face and no rim, glyph in the muted tone.
  final bool plain;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: Locales.string(context, labelKey),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: onTap == null ? 0.35 : 1,
                child: _face(colors),
              ),
            ),
            if (statusColor != null) _dot(colors),
          ],
        ),
      ),
    );
  }

  Widget _face(InsulinkColors colors) {
    return Material(
      color: plain ? Colors.transparent : colors.panel,
      shape: CircleBorder(
        side: plain ? BorderSide.none : BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Icon(icon, size: 20, color: plain ? colors.muted : colors.text),
      ),
    );
  }

  /// A 10 px dot with a 2.5 px ring in the page colour, so it reads as sitting
  /// on top of the button rather than inside it. Without a face it sits on the
  /// glyph's corner instead of the rim.
  Widget _dot(InsulinkColors colors) {
    final inset = plain ? 8.0 : 1.0;
    return Positioned(
      top: inset,
      right: inset,
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
