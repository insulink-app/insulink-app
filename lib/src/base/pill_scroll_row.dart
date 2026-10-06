import 'package:flutter/material.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A horizontally scrolling row of pills, one lit: the analysis tab's areas.
/// The lit pill is light (text colour) with dark writing, the others sit on
/// the panel colour with muted writing. Scrolls past the page edge so a long
/// set never squeezes its labels.
class PillScrollRow<T> extends StatelessWidget {
  const PillScrollRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.edge = InkSpace.panelMargin,
  });

  final List<ToggleOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Space before the first and after the last pill.
  final double edge;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: edge),
      child: Row(
        spacing: 8,
        children: [for (final option in options) _pill(context.ink, option)],
      ),
    );
  }

  Widget _pill(InsulinkColors colors, ToggleOption<T> option) {
    final active = option.value == selected;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? colors.text : colors.panel,
        shape: StadiumBorder(
          side: active ? BorderSide.none : BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(option.value),
          child: Container(
            height: InkSpace.minTouch,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              option.label,
              style: InkText.row.copyWith(
                color: active ? colors.ground : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
