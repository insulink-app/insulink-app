import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The Insulink sign (the one-colour logo) in the accent, [size] wide. With
/// [framed] it sits in a 96 px tinted square, as on the welcome page.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, this.framed = false});

  final double size;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final mark = Image.asset(
      'assets/images/logo-white.png',
      width: size,
      color: colors.accent,
    );
    if (!framed) {
      return Center(child: mark);
    }
    return Center(
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.panelRaised,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.border),
        ),
        child: mark,
      ),
    );
  }
}
