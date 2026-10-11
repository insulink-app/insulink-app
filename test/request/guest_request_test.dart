import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/request/request.dart';

import '../support/http_mock.dart';
import '../support/secure_storage_mock.dart';

/// Without a session nothing that needs one is sent: its 403 would clear the
/// session and throw a guest back to the sign-in page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  test('an account endpoint is not called without a session', () async {
    final http = FakeHttp({});
    final response = await http.run(
      () => Request.get(url: '/glucose/history/').send(null),
    );
    expect(response, isNull);
    expect(http.sent, isEmpty);
  });

  test('signing in still goes out without a session', () async {
    final http = FakeHttp({
      '/signin/': {'success': false},
    });
    await http.run(
      () => Request.post(url: '/signin/', body: {'name': 'x'}).send(null),
    );
    expect(http.sent.map((request) => request.path), ['/signin/']);
  });
}
