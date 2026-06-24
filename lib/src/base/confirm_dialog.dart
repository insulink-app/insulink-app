import 'package:flutter/material.dart';

import '../localization/locales.dart';

/// Reusable yes/no confirmation dialog. Returns `true` via `Navigator.pop` when
/// the confirm action is chosen, `false`/`null` otherwise. Show it with
/// `showDialog<bool>(context: ..., builder: (_) => ConfirmDialog(...))`.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.titleKey,
    required this.bodyKey,
    required this.confirmKey,
    this.destructive = false,
  });

  final String titleKey;
  final String bodyKey;
  final String confirmKey;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Locales.string(context, titleKey)),
      content: Text(Locales.string(context, bodyKey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(Locales.string(context, 'alert.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: Colors.redAccent)
              : null,
          child: Text(Locales.string(context, confirmKey)),
        ),
      ],
    );
  }
}
