import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/metric_grid.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A few figures side by side in one panel, centred and parted by thin
/// vertical lines: Ø / Min / Max on the heart-rate and weight pages.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.cells});

  final List<MetricCell> cells;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return InkPanel(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var index = 0; index < cells.length; index++) ...[
              if (index > 0)
                VerticalDivider(width: 1, thickness: 1, color: colors.line),
              Expanded(child: _cell(colors, cells[index])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(InsulinkColors colors, MetricCell cell) {
    return Column(
      spacing: 6,
      children: [
        Text(cell.label, style: InkText.label.copyWith(color: colors.muted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              text: cell.value,
              style: InkText.bigValue.copyWith(
                fontSize: 24,
                color: colors.text,
              ),
              children: [
                if (cell.unit != null)
                  TextSpan(
                    text: ' ${cell.unit}',
                    style: InkText.unit.copyWith(color: colors.muted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
