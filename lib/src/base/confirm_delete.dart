import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../alert/alert.dart';

/// Zeigt eine Lösch-Bestätigung. [messageKey] ist der Lokalisierungs-Schlüssel
/// der Rückfrage; [onConfirm] läuft nur, wenn der Nutzer „Löschen" wählt.
/// Geteilt von allen löschenden Buttons, damit keine Aktion versehentlich feuert.
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
