// Context is optional UI feedback forwarded to RequestReset.reset, which guards
// `mounted` itself — forwarding a stale one across these gaps is harmless.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';
import 'package:insulink/src/request/request_reset.dart';

class RequestRefresh {
  Future<bool>? _currentRefresh;

  Future<bool> refresh(BuildContext? context) {
    if (_currentRefresh != null) {
      return _currentRefresh!;
    }
    _currentRefresh = performRefresh(
      context,
    ).whenComplete(() => _currentRefresh = null);
    return _currentRefresh!;
  }

  Future<bool> performRefresh(BuildContext? context) async {
    const storage = FlutterSecureStorage();
    final refreshToken = await storage.read(key: "refresh_token") ?? "";
    if (refreshToken == "") {
      await RequestReset().reset(context);
      return false;
    }
    var response = await Request.post(
      url: "/refresh/",
      body: <String, String>{"refresh_token": refreshToken},
    ).send(context);
    if (response?.statusCode == 409) {
      return false;
    }
    final responseBody = response.jsonObject;
    if (responseBody == null) {
      return false;
    }
    if (responseBody["success"] == false) {
      // A concurrent refresh (the other isolate) may have already rotated the
      // token out from under us — the server then rejects OUR now-stale one. If
      // the stored token changed since we read it, that other refresh succeeded:
      // retry the original request with the fresh token instead of logging out.
      final current = await storage.read(key: "refresh_token") ?? "";
      if (current != refreshToken && current != "") {
        return true;
      }
      await RequestReset().reset(context);
      return false;
    }
    await storage.write(
      key: "authentication_token",
      value: responseBody["authentication_token"],
    );
    await storage.write(
      key: "refresh_token",
      value: responseBody["refresh_token"],
    );
    return true;
  }
}
