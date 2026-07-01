// Context is optional UI feedback forwarded to RequestReset.reset, which guards
// `mounted` itself — forwarding a stale one across these gaps is harmless.
// ignore_for_file: use_build_context_synchronously
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/request.dart';
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
    if (response == null || response.statusCode == 409) {
      return false;
    }
    var responseBody = jsonDecode(response.body);
    if (responseBody["success"] == false) {
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
