import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/request/request.dart';

import '../support/secure_storage_mock.dart';

/// A meal photo the user called off must not be sent again: every retry would
/// start the model on the server once more.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => installSecureStorageMock()['authentication_token'] = 'token');

  test('an aborted request answers nothing and is not retried', () async {
    final request = Request.post(
      url: '/nutrition/estimate/',
      body: {'run_id': 'abc'},
      abortTrigger: Future<void>.value(),
    );
    final started = DateTime.now();

    final response = await request.send(null);

    expect(response, isNull);
    expect(request.lastError, contains('abort'));
    expect(
      DateTime.now().difference(started),
      lessThan(Duration(milliseconds: 500)),
    );
  });
}
