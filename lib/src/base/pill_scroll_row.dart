import 'package:flutter/material.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// A horizontally scrolling row of pills, one lit: the analysis tab's areas.
/// The lit pill is light (text colour) with dark writing, the others sit on
/// the panel colour with muted writing. Scrolls past the page edge so a long
/// set never squeezes its labels, and scrolls a newly lit pill into view.
class PillScrollRow<T> extends StatefulWidget {
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
  State<PillScrollRow<T>> createState() => _PillScrollRowState<T>();
}

class _PillScrollRowState<T> extends State<PillScrollRow<T>> {
  final Map<T, GlobalKey> _pillKeys = {};

  /// A selection made elsewhere (a swipe of the views below) can light a pill
  /// that sits past the edge; it slides in from the side it was hidden on.
  @override
  void didUpdateWidget(PillScrollRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) {
      return;
    }
    final forward = _indexOf(widget.selected) > _indexOf(oldWidget.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(forward));
  }

  int _indexOf(T value) =>
      widget.options.indexWhere((option) => option.value == value);

  void _reveal(bool forward) {
    final pillContext = _pillKeys[widget.selected]?.currentContext;
    if (pillContext == null || !pillContext.mounted) {
      return;
    }
    Scrollable.ensureVisible(
      pillContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignmentPolicy: forward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: widget.edge),
      child: Row(
        spacing: 8,
        children: [
          for (final option in widget.options) _pill(context.ink, option),
        ],
      ),
    );
  }

  Widget _pill(InsulinkColors colors, ToggleOption<T> option) {
    final active = option.value == widget.selected;
    return Semantics(
      key: _pillKeys.putIfAbsent(option.value, GlobalKey.new),
      button: true,
      selected: active,
      child: Material(
        color: active ? colors.text : colors.panel,
        shape: StadiumBorder(
          side: active ? BorderSide.none : BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onChanged(option.value),
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
