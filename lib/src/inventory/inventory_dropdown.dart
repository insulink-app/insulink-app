import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../base/labeled_field.dart';
import '../localization/locales.dart';
import '../theme/insulink_theme.dart';

/// A labelled dropdown of the item editor (type, sensor or pump brand), filled
/// like the text fields beside it. Uses M3 [DropdownMenu] instead of
/// [DropdownButtonFormField] because the latter's popup renders wider than its
/// field and drifts to the screen edges; [DropdownMenu]'s menu tracks the
/// field width, and [DropdownMenu.expandedInsets] `zero` makes the field fill
/// its column exactly.
class InventoryDropdown<T> extends StatelessWidget {
  const InventoryDropdown({
    super.key,
    required this.labelKey,
    required this.selected,
    required this.values,
    required this.labelKeyOf,
    required this.onChanged,
  });

  final String labelKey;
  final T selected;
  final List<T> values;
  final String Function(T value) labelKeyOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      labelKey: labelKey,
      child: Builder(builder: _menu),
    );
  }

  /// Built below the [LabeledField] so it picks up the field look the label
  /// puts in the theme.
  Widget _menu(BuildContext context) {
    final colors = context.ink;
    return DropdownMenu<T>(
      key: ValueKey(selected),
      initialSelection: selected,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      trailingIcon: Icon(
        PhosphorIconsBold.caretDown,
        size: 16,
        color: colors.muted,
      ),
      selectedTrailingIcon: Icon(
        PhosphorIconsBold.caretUp,
        size: 16,
        color: colors.muted,
      ),
      inputDecorationTheme: Theme.of(context).inputDecorationTheme,
      onSelected: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.panelRaised),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(InkRadius.field)),
          ),
        ),
      ),
      dropdownMenuEntries: [
        for (final value in values)
          DropdownMenuEntry(
            value: value,
            label: Locales.string(context, labelKeyOf(value)),
          ),
      ],
    );
  }
}
