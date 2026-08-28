import 'dart:convert';
import 'package:http/http.dart' show Response;

/// Reading an API reply as JSON without trusting that it is any.
///
/// A reply is not always JSON, and the cases where it is not are exactly the ones
/// nobody codes for: an empty body, a proxy's HTML error page, a 500 from a
/// server that fell over mid-request. `jsonDecode` throws on all of them, and
/// from an unawaited sync that becomes an unhandled exception that takes the
/// isolate's error handler rather than the caller's `if`.
extension ApiResponseJson on Response? {
  /// The body as a JSON object, or null when the reply is missing, empty, not
  /// JSON, or JSON that is not an object.
  Map<String, dynamic>? get jsonObject {
    final body = this?.body;
    if (body == null || body.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether the API reported success. False for anything unreadable, which is
  /// the safe reading: a caller that cannot tell must not assume it worked.
  bool get isApiSuccess => jsonObject?['success'] == true;
}
