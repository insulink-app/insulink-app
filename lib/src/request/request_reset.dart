import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/auth/auth_gate.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class RequestReset {
  /// Clears the session and sends the user back to the auth gate.
  ///
  /// A null context means a BACKGROUND isolate (the foreground service's glucose
  /// / event / sport sync) hit an auth failure. Those posts are best-effort and
  /// have no UI to re-login through, so the background must NEVER clear the
  /// shared tokens — doing so logs the UI isolate out from under the user (the
  /// intermittent `connection.logout`). Token lifecycle is the UI isolate's job;
  /// the background just lets the request fail and retries later.
  Future<void> reset(BuildContext? context) async {
    if (context == null) {
      return;
    }
    const storage = FlutterSecureStorage();
    await storage.delete(key: "user");
    await storage.delete(key: "name");
    await storage.delete(key: "authentication_token");
    await storage.delete(key: "refresh_token");
    if (!context.mounted) {
      return;
    }
    Alert(
      description: "connection.logout",
      icon: PhosphorIconsRegular.warning,
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
