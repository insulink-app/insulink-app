import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/request/sync_reload.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  const watched = ['a', 'b'];

  test('reload runs with the changed key when the pull changed it', () async {
    Set<String>? seen;
    await const SyncReload().ifChanged(
      watched,
      () async => const FlutterSecureStorage().write(key: 'a', value: 'v'),
      (changed) async => seen = changed,
    );
    expect(seen, {'a'});
  });

  test('reload is skipped when the pull changed nothing', () async {
    var reloaded = 0;
    await const SyncReload().ifChanged(
      watched,
      () async {},
      (_) async => reloaded++,
    );
    expect(reloaded, 0);
  });

  test('rewriting a watched key with its own value counts as no change',
      () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'a', value: 'v');
    var reloaded = 0;
    await const SyncReload().ifChanged(
      watched,
      () async => storage.write(key: 'a', value: 'v'),
      (_) async => reloaded++,
    );
    expect(reloaded, 0);
  });

  test('a change to an UNwatched key does not trigger reload', () async {
    const storage = FlutterSecureStorage();
    var reloaded = 0;
    await const SyncReload().ifChanged(
      watched,
      // Mimics a glucose write from the service isolate mid-pull.
      () async => storage.write(key: 'g7.hist.42', value: 'lots'),
      (_) async => reloaded++,
    );
    expect(reloaded, 0);
  });

  test('only the keys that changed are reported, not every watched key',
      () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'a', value: 'v');
    await storage.write(key: 'b', value: 'v');
    Set<String>? seen;
    await const SyncReload().ifChanged(
      watched,
      () async => storage.write(key: 'b', value: 'w'),
      (changed) async => seen = changed,
    );
    expect(seen, {'b'});
  });
}
