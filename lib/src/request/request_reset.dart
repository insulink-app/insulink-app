import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/auth/auth_gate.dart';

class RequestReset {
  reset(context) async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: "user");
    await storage.delete(key: "name");
    await storage.delete(key: "authentication_token");
    await storage.delete(key: "refresh_token");
    Alert(
      description: "connection.logout",
      icon: CupertinoIcons.exclamationmark_triangle,
      callback: () {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const AuthGate(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      },
    ).show(context);
  }
}
