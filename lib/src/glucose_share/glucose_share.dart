import 'package:insulink/src/config/environment_options.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// A link that shows the user's glucose, and nothing else, to whoever holds it
/// (`insulink-api` `docs/GLUCOSE_SHARE.md`). [id] is the secret in the link,
/// [name] says whom it was given to.
class GlucoseShare {
  const GlucoseShare({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  factory GlucoseShare.fromJson(Map<String, dynamic> json) => GlucoseShare(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
  );

  /// The panel's public page this link opens.
  String get url => 'https://${EnvironmentOptions.environment.panel}/share/$id';
}

/// The account's share links on the server: list, create, delete. Each call
/// answers null or false when the request failed (no account, no network).
class GlucoseShareClient {
  const GlucoseShareClient();

  Future<List<GlucoseShare>?> find() async {
    final body = (await Request.get(
      url: '/glucose/share/find/',
    ).send(null))?.jsonObject;
    if (body == null || body['success'] != true || body['shares'] is! List) {
      return null;
    }
    return [
      for (final share in body['shares'] as List)
        GlucoseShare.fromJson(share as Map<String, dynamic>),
    ];
  }

  Future<bool> create(String name) =>
      _post('/glucose/share/create/', {'name': name});

  Future<bool> delete(GlucoseShare share) =>
      _post('/glucose/share/delete/', {'share_id': share.id});

  Future<bool> _post(String url, Map<String, Object> body) async {
    final response = await Request.post(url: url, body: body).send(null);
    return response?.isApiSuccess ?? false;
  }
}
