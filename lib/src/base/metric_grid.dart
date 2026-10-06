import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One figure of a [MetricGrid]: what it is, the number, and its unit.
typedef MetricCell = ({String label, String value, String? unit});

/// Figures in one panel, two per row, the cells parted by 1 px lines instead of
/// being separate cards: the analysis key figures and the forecast scores.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.cells});

  final List<MetricCell> cells;

  @override
  Widget build(BuildContext context) {
    final line = context.ink.line;
    return InkPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var row = 0; row * 2 < cells.length; row++) ...[
            if (row > 0) Divider(height: 1, thickness: 1, color: line),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _cell(context, cells[row * 2])),
                  VerticalDivider(width: 1, thickness: 1, color: line),
                  Expanded(
                    child: row * 2 + 1 < cells.length
                        ? _cell(context, cells[row * 2 + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, MetricCell cell) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            cell.label,
            style: InkText.caption.copyWith(color: colors.muted),
          ),
          Text.rich(
            TextSpan(
              text: cell.value,
              style: InkText.bigValue.copyWith(
                fontSize: 28,
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
        ],
      ),
    );
  }
}
