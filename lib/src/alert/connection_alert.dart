import 'package:flutter/widgets.dart';
import 'package:insulink/src/alert/alert.dart';

class ConnectionAlert {
  ConnectionAlert();

  void show(BuildContext context) {
    Alert(
      description: "connection.failed",
      type: AlertType.error,
    ).show(context);
  }
}
