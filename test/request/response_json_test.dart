import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/request/response_json.dart';

/// A reply is not always JSON, and the cases where it is not are exactly the ones
/// nobody codes for. `jsonDecode` throws on all of them, and from an unawaited
/// sync that becomes an unhandled exception rather than a caught one, which is
/// how an empty body took the app down mid-activation.
void main() {
  Response reply(String body) => Response(body, 200);

  group('reading an API reply that may not be JSON', () {
    test('a JSON object is read', () {
      expect(reply('{"success":true,"n":2}').jsonObject, {
        'success': true,
        'n': 2,
      });
    });

    test('an empty body reads as nothing, not as a crash', () {
      expect(reply('').jsonObject, isNull);
      expect(reply('').isApiSuccess, isFalse);
    });

    test('a missing response reads as nothing', () {
      expect(null.jsonObject, isNull);
      expect(null.isApiSuccess, isFalse);
    });

    /// A proxy's error page is the realistic shape of this: HTML where JSON was
    /// promised.
    test('an HTML error page reads as nothing', () {
      expect(reply('<html><body>502</body></html>').jsonObject, isNull);
    });

    test('JSON that is not an object reads as nothing', () {
      expect(reply('[1,2,3]').jsonObject, isNull);
      expect(reply('"text"').jsonObject, isNull);
      expect(reply('null').jsonObject, isNull);
    });

    /// Anything unreadable must not count as success: a caller that cannot tell
    /// has to assume it did not work.
    test('success is only true when the reply says so', () {
      expect(reply('{"success":true}').isApiSuccess, isTrue);
      expect(reply('{"success":false}').isApiSuccess, isFalse);
      expect(reply('{}').isApiSuccess, isFalse);
      expect(reply('not json').isApiSuccess, isFalse);
    });
  });
}
