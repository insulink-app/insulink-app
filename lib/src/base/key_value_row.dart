import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One line of a key/value table in an [InkPanel.list]: the key muted on the
/// left, the value bold on the right. [valueWidget] replaces the plain value
/// where it carries more than text (a status dot, a selectable serial).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.leading,
  }) : assert((value == null) != (valueWidget == null));

  final String label;
  final String? value;
  final Widget? valueWidget;

  /// A glyph before the key, as on the bolus confirmation's summary.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: 16,
        children: [
          ?leading,
          Text(
            label,
            style: InkText.body.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.muted,
            ),
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: valueWidget ?? _value(colors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _value(InsulinkColors colors) {
    return Text(
      value!,
      textAlign: TextAlign.end,
      style: InkText.row.copyWith(color: colors.text),
    );
  }
}
