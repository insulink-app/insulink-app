import 'dart:convert';

import 'package:http/http.dart';
import 'package:insulink/src/config/environment_options.dart';
import 'package:insulink/src/demo/demo_account.dart';

/// Stands in for the Insulink API in the browser demo. Installed with
/// `runWithClient`, so every `get`/`post` the app makes lands here instead of on
/// the network: requests to the API host are answered from [account], anything
/// else (map tiles, the food database) goes out through [network] unchanged.
///
/// Always answers 200: a 403 would log the demo out and a 417 would try to
/// refresh a token that does not exist.
class DemoBackend extends BaseClient {
  DemoBackend({required this.account, required this.network});

  final DemoAccount account;

  /// A client created OUTSIDE the demo zone; one created inside would be this.
  final Client network;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (request.url.host != EnvironmentOptions.environment.endpoint) {
      return network.send(request);
    }
    final body = jsonEncode(account.respond(request.method, request.url.path));
    return StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
