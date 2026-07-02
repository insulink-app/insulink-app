import 'package:flutter/material.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/localization/locales.dart';

enum _SportRowAction { copy, delete }

/// Trailing overflow menu shared by the exercise and routine rows: "copy" and a
/// confirmed "delete", each with an icon. [extra] slots a widget (e.g. a
/// routine's play button) before the menu.
class SportRowMenu extends StatelessWidget {
  const SportRowMenu({
    super.key,
    required this.onCopy,
    required this.deleteConfirmKey,
    required this.onDelete,
    this.extra,
  });

  final VoidCallback onCopy;
  final String deleteConfirmKey;
  final VoidCallback onDelete;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final menu = PopupMenuButton<_SportRowAction>(
      icon: Icon(
        Icons.more_vert,
        color: scheme.onSurface.withValues(alpha: 0.55),
      ),
      tooltip: '',
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (action) => _run(context, action),
      itemBuilder: (context) => [
        _item(
          context,
          _SportRowAction.copy,
          Icons.copy_rounded,
          'sport.copy',
          scheme.onSurface,
        ),
        _item(
          context,
          _SportRowAction.delete,
          Icons.delete_outline_rounded,
          'alert.delete',
          scheme.error,
        ),
      ],
    );
    if (extra == null) {
      return menu;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [extra!, menu]);
  }

  PopupMenuItem<_SportRowAction> _item(
    BuildContext context,
    _SportRowAction action,
    IconData icon,
    String labelKey,
    Color color,
  ) {
    return PopupMenuItem<_SportRowAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(
            Locales.string(context, labelKey),
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _run(BuildContext context, _SportRowAction action) {
    switch (action) {
      case _SportRowAction.copy:
        onCopy();
      case _SportRowAction.delete:
        confirmDelete(
          context,
          messageKey: deleteConfirmKey,
          onConfirm: onDelete,
        );
    }
  }
}
