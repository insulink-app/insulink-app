import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One choice of a [SegmentedToggle]: its value and the label shown for it.
typedef ToggleOption<T> = ({T value, String label});

/// A pill track with one option lit in the accent: the chart's 24 h / 12 h /
/// 6 h, the automation's Off / Active.
///
/// [SegmentedToggle.page] stands on the page (a panel track with a rim, as wide
/// as its labels); the default sits inside a panel (a track in the page colour,
/// options sharing the full width, 42 px each). Both keep a 44 px touch height.
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticsLabel,
  }) : onPage = false,
       expand = true;

  const SegmentedToggle.page({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticsLabel,
    this.expand = false,
  }) : onPage = true;

  final List<ToggleOption<T>> options;
  final T selected;
  final ValueChanged<T>? onChanged;

  /// What the whole group chooses, read out before the options.
  final String? semanticsLabel;

  final bool onPage;

  /// Options share the full width instead of hugging their labels.
  final bool expand;

  double get _optionHeight => onPage ? 36 : 42;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: onPage ? colors.panel : colors.ground,
          borderRadius: BorderRadius.circular(_optionHeight / 2 + 4),
          border: onPage ? Border.all(color: colors.border) : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          spacing: onPage ? 2 : 4,
          children: [
            for (final option in options)
              expand
                  ? Expanded(child: _option(colors, option))
                  : _option(colors, option),
          ],
        ),
      ),
    );
  }

  Widget _option(InsulinkColors colors, ToggleOption<T> option) {
    final active = option.value == selected;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: active,
      button: true,
      child: Material(
        color: active ? colors.accent : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(option.value),
          child: Container(
            height: _optionHeight,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: expand ? 4 : 14),
            child: Text(
              option.label,
              style: InkText.row.copyWith(
                fontSize: onPage ? 14 : 15,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                color: active ? colors.onAccent : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
