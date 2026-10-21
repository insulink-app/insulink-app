import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// The account's complete history as the api stores it. The device only keeps
/// a recent window (90 days of glucose, capped meal and sport lists), so a full
/// backup has to read the rest back from the server.
///
/// Every read endpoint returns all of the user's rows, so the archive is each
/// reply body (minus `success`) keyed by its path: a restore can post them
/// straight back through the matching `sync`/`report` endpoint. The settings
/// history is the one read-only part: the server records it on every settings
/// change, so it is exported for the record and never posted back.
class AccountArchive {
  static const paths = [
    '/glucose/history/',
    '/event/history/',
    '/sensor/history/',
    '/pump/history/',
    '/pump/contact/find/',
    '/insulin/delivery/find/',
    '/nutrition/meals/find/',
    '/nutrition/drinks/find/',
    '/nutrition/products/find/',
    '/inventory/items/find/',
    '/sport/measurements/find/',
    '/sport/exercises/find/',
    '/sport/routines/find/',
    '/sport/workouts/find/',
    '/sport/trainings/find/',
    '/health/days/find/',
    '/health/pulse/find/',
    '/health/hba1c/find/',
    '/user/settings/find/',
    '/user/settings/history/',
  ];

  const AccountArchive();

  /// Downloads every path. Throws when one fails, because a backup that
  /// silently misses part of the history is worse than none.
  Future<Map<String, Object>> download() async {
    final archive = <String, Object>{};
    for (final path in paths) {
      archive[path] = await _fetch(path);
    }
    return archive;
  }

  Future<Map<String, dynamic>> _fetch(String path) async {
    final response = await Request.get(url: path).send(null);
    final body = response.jsonObject;
    if (body == null || body['success'] != true) {
      throw StateError('backup: $path failed (${response?.statusCode})');
    }
    return body..remove('success');
  }
}
