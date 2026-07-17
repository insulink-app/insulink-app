import 'package:flutter/material.dart';

import '../alert/alert.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

/// Shows a delete confirmation. [messageKey] is the localization key of the
/// prompt; [onConfirm] runs only when the user chooses "Delete". Shared by all
/// deleting buttons so no action fires accidentally.
void confirmDelete(
  BuildContext context, {
  required String messageKey,
  required VoidCallback onConfirm,
}) {
  Alert(
    icon: PhosphorIconsBold.trash,
    iconColor: context.danger,
    description: messageKey,
    cancelButton: true,
    confirmButtonText: 'alert.delete',
    confirmButtonColor: Theme.of(context).colorScheme.error,
    callback: onConfirm,
  ).show(context);
}
