import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/cgm_store.dart';
import 'package:insulink/src/cgm/glucose_backlog.dart';

import '../support/http_mock.dart';
import '../support/secure_storage_mock.dart';

/// Readings recorded while the account was unreachable reach it later, and the
/// mark only moves past what the account accepted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> storage;
  late CgmStore store;
  final now = DateTime.now();
  final readings = {
    now.subtract(const Duration(days: 3)): 110,
    now.subtract(const Duration(days: 2)): 120,
    now.subtract(const Duration(minutes: 5)): 130,
  };

  setUp(() async {
    storage = installSecureStorageMock()..['authentication_token'] = 'token';
    store = await CgmStore.open();
    await store.archiveAddAll(readings);
  });

  test('the whole unconfirmed archive goes up and the mark follows', () async {
    final http = FakeHttp({
      '/glucose/report/': {'success': true},
    });
    await http.run(() => GlucoseBacklog().drainIfDue(store, (_) {}));
    final entries = http.lastTo('/glucose/report/')!['entries'] as List;
    expect(entries.map((entry) => entry['glucose']), [110, 120, 130]);
    final newest = readings.keys.last.millisecondsSinceEpoch ~/ 60000;
    expect(storage['glucose_sync.uploaded_through'], '$newest');
  });

  test('without an account nothing is sent and the mark stays', () async {
    storage.remove('authentication_token');
    final http = FakeHttp({});
    await http.run(() => GlucoseBacklog().drainIfDue(store, (_) {}));
    expect(http.sent, isEmpty);
    expect(storage.containsKey('glucose_sync.uploaded_through'), isFalse);
  });
}
