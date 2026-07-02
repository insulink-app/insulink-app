import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../alert/alert.dart';

/// Shows a delete confirmation. [messageKey] is the localization key of the
/// prompt; [onConfirm] runs only when the user chooses "Delete". Shared by all
/// deleting buttons so no action fires accidentally.
void confirmDelete(
  BuildContext context, {
  required String messageKey,
  required VoidCallback onConfirm,
}) {
  Alert(
    icon: CupertinoIcons.delete,
    iconColor: Colors.redAccent,
    description: messageKey,
    cancelButton: true,
    confirmButtonText: 'alert.delete',
    confirmButtonColor: Colors.redAccent,
    callback: onConfirm,
  ).show(context);
}
