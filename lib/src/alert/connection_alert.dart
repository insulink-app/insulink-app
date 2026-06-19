import 'package:insulink/src/alert/alert.dart';

class ConnectionAlert {
  ConnectionAlert();

  show(context) {
    Alert(
      description: "connection.failed",
      type: AlertType.error,
    ).show(context);
  }
}
