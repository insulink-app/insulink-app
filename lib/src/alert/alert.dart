import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_dialog.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

enum AlertType { success, error, neutral }

/// The confirmation/notice call every feature already makes, shown as the
/// app's [InkDialog]. The parameters stay as they were so no caller changes:
/// [description] becomes the dialog's title, [content] sits under it, the
/// confirm button is the action and the cancel button the text button under
/// it. Something that deletes, stops or failed gets the danger tone.
class Alert {
  final AlertType? type;
  final IconData? icon;
  final Color? iconColor;
  final String? description;
  final Widget? content;
  final bool? cancelButton;
  final String? cancelButtonText;
  final String? confirmButtonText;
  final Color? confirmButtonColor;
  final bool Function()? confirmButtonEnabled;
  final Function()? callback;
  final Function()? cancelCallback;

  const Alert({
    this.type,
    this.icon,
    this.iconColor,
    this.description,
    this.content,
    this.cancelButton,
    this.cancelButtonText,
    this.confirmButtonText,
    this.confirmButtonColor,
    this.confirmButtonEnabled,
    this.callback,
    this.cancelCallback,
  });

  void show(BuildContext context) {
    InkDialog(
      icon: _icon(),
      tone: _tone(context),
      titleKey: description,
      content: content,
      actionKey: confirmButtonText ?? 'alert.ok',
      onAction: callback == null ? null : () => callback!(),
      actionEnabled: confirmButtonEnabled,
      cancelKey: cancelButton == true
          ? (cancelButtonText ?? 'alert.cancel')
          : null,
      onCancel: cancelCallback == null ? null : () => cancelCallback!(),
    ).show(context);
  }

  IconData _icon() {
    return icon ??
        switch (type) {
          AlertType.success => PhosphorIconsBold.checkCircle,
          AlertType.error => PhosphorIconsBold.warningCircle,
          _ => PhosphorIconsBold.info,
        };
  }

  /// Danger for an error, or where the caller marked the icon or the
  /// confirm button as dangerous (delete, stop, discard); accent otherwise.
  InkDialogTone _tone(BuildContext context) {
    final dangerous =
        type == AlertType.error ||
        (iconColor != null && iconColor == context.danger) ||
        (confirmButtonColor != null &&
            confirmButtonColor == Theme.of(context).colorScheme.error);
    return dangerous ? InkDialogTone.danger : InkDialogTone.accent;
  }
}
