import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A change since the entry before, as a small tinted pill with an arrow:
/// green going down, amber going up ("↓ 0,2 kg").
class ChangeChip extends StatelessWidget {
  const ChangeChip({super.key, required this.label, required this.up});

  /// The amount, already formatted with its unit and without a sign.
  final String label;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final tone = up ? colors.high : colors.range;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: tone.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(
            up ? PhosphorIconsBold.arrowUp : PhosphorIconsBold.arrowDown,
            size: 14,
            color: tone,
          ),
          Text(
            label,
            style: InkText.label.copyWith(
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
