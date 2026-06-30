// The context is optional UI feedback (logout alert) threaded to the leaf
// RequestReset.reset, which itself guards `mounted` — so forwarding a stale
// context through these retry/refresh gaps is harmless.
// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:insulink/src/config/environment_options.dart';
import 'package:insulink/src/request/request_refresh.dart';
import 'package:insulink/src/request/request_reset.dart';

class Request {
  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, Object> body;
  static final RequestRefresh _refresh = RequestRefresh();
  // 10s, not 5: a backgrounded device's radio is asleep, so a cold DNS+TLS
  // handshake on the first request after idle often needs more than 5s.
  static const int _timeout = 10;
  static const int _maxRetries = 3;
  int _retries = 0;

  /// The last transport-level exception (no HTTP response), so a caller logging
  /// a null status can show WHY instead of just "status null". Cleared on a
  /// successful response.
  String? lastError;

  Request.get(
      {required String url, this.headers = const {}, this.body = const {}})
      : url = "https://${EnvironmentOptions.environment.endpoint}/v1$url",
        method = "GET";

  Request.post(
      {required String url, this.headers = const {}, this.body = const {}})
      : url = "https://${EnvironmentOptions.environment.endpoint}/v1$url",
        method = "POST";

  Future<Response?> send(BuildContext? context) async {
    Map<String, String> headers = Map.from(this.headers);
    headers["Content-Type"] = "application/json; charset=UTF-8";
    const storage = FlutterSecureStorage();
    String authenticationToken =
        await storage.read(key: "authentication_token") ?? "";
    if (authenticationToken != "") {
      headers["Authorization"] = "Bearer $authenticationToken";
    }
    var response = await generateResponse(headers);
    return processResponse(context, response, headers);
  }

  Future<Response?> processResponse(
      BuildContext? context, Response? response, Map<String, String> headers) async {
    if (response == null && _retries < _maxRetries) {
      _retries += 1;
      await Future.delayed(Duration(milliseconds: 500 * _retries));
      var retried = await generateResponse(headers);
      return processResponse(context, retried, headers);
    }
    if (response?.statusCode == 403) {
      await RequestReset().reset(context);
      return response;
    }
    if (response?.statusCode == 417) {
      var refreshResult = await _refresh.refresh(context);
      if (refreshResult == true) {
        return await send(context);
      }
      return response;
    }
    return response;
  }

  Future<Response?> generateResponse(Map<String, String> headers) async {
    if (method == "GET") {
      try {
        final response = await get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: _timeout));
        _logRequest(method: method, headers: headers, response: response);
        lastError = null;
        return response;
      } catch (exception) {
        _logRequest(method: method, headers: headers, exception: exception);
        lastError = exception.toString();
        return null;
      }
    } else if (method == "POST") {
      try {
        Map<String, Object> body = Map.from(this.body);
        final response =
            await post(Uri.parse(url), headers: headers, body: jsonEncode(body))
                .timeout(const Duration(seconds: _timeout));
        _logRequest(
            method: method, headers: headers, body: body, response: response);
        lastError = null;
        return response;
      } catch (exception) {
        _logRequest(
            method: method,
            headers: headers,
            body: body,
            exception: exception);
        lastError = exception.toString();
        return null;
      }
    } else {
      throw UnsupportedError("Unsupported HTTP method: $method");
    }
  }

  void _logRequest({
    required String method,
    required Map<String, dynamic> headers,
    Map<String, Object>? body,
    Response? response,
    Object? exception,
  }) {
    if (!kDebugMode) {
      return;
    }
    final sanitizedHeaders = Map<String, dynamic>.from(headers);
    if (sanitizedHeaders.containsKey("Authorization")) {
      sanitizedHeaders["Authorization"] = "Bearer [REDACTED]";
    }
    final buffer = StringBuffer();
    buffer.write("");
    buffer.writeln("┌─────────────────────────────────────────");
    buffer.writeln("│ $method $url");
    buffer.writeln("├─ Headers");
    sanitizedHeaders.forEach((k, v) => buffer.writeln("│   $k: $v"));
    if (body != null && body.isNotEmpty) {
      buffer.writeln("├─ Body");
      buffer.writeln("│   ${jsonEncode(body)}");
    }
    if (exception != null) {
      buffer.writeln("├─ Exception");
      buffer.writeln("│   $exception");
    }
    if (response != null) {
      buffer.writeln("├─ Response [${response.statusCode}]");
      buffer.writeln("│   ${response.body}");
    }
    buffer.writeln("└─────────────────────────────────────────");
    developer.log(buffer.toString(), name: "Request");
  }
}
