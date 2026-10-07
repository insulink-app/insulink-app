import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A calm grouped area: panel colour, radius 20 and a faint 1 px rim, no shadow.
///
/// [InkPanel.list] stacks rows (list rows, key/value rows, danger rows) in one
/// panel and draws the 1 px line between them itself, so a list never turns
/// into a pile of separate cards.
class InkPanel extends StatelessWidget {
  const InkPanel({
    super.key,
    required Widget this.child,
    this.padding = const EdgeInsets.all(InkSpace.panelPadding),
    this.color,
    this.radius = InkRadius.panel,
  }) : rows = null;

  const InkPanel.list({
    super.key,
    required List<Widget> this.rows,
    this.color,
    this.radius = InkRadius.panel,
  }) : child = null,
       padding = EdgeInsets.zero;

  final Widget? child;
  final List<Widget>? rows;

  /// Inner spacing; a panel ending in a row that brings its own height trims
  /// the bottom.
  final EdgeInsets padding;

  /// Overrides the panel colour, for a card that sits inside a sheet.
  final Color? color;

  /// Corner radius; a page's lead card takes a larger one.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Container(
      width: double.infinity,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? colors.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.border),
      ),
      child: child ?? _rows(colors),
    );
  }

  /// Material ancestor so the rows' ink splashes paint on the panel and not
  /// behind it.
  Widget _rows(InsulinkColors colors) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows!.length; index++) ...[
            if (index > 0) Divider(height: 1, thickness: 1, color: colors.line),
            rows![index],
          ],
        ],
      ),
    );
  }
}
