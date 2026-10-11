import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/request/sync_ledger.dart';

import '../support/secure_storage_mock.dart';

/// The pulls replace a collection unless a local change was never confirmed:
/// then both sides are kept and the union goes back up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  const ledger = SyncLedger();
  List<String> saved = [];

  Future<bool> adopt(List<String> remote) => ledger.adopt<String>(
    collection: 'meals',
    remote: remote,
    local: () async => ['offline breakfast'],
    save: (items) async => saved = items,
    keyOf: (item) => item,
  );

  test('a clean collection takes the account copy as it is', () async {
    expect(await adopt(['account lunch']), isFalse);
    expect(saved, ['account lunch']);
  });

  test(
    'an unconfirmed collection keeps both sides and asks for a push',
    () async {
      await ledger.mark('meals');
      expect(await adopt(['account lunch', 'offline breakfast']), isTrue);
      expect(saved, ['offline breakfast', 'account lunch']);
    },
  );

  test('a confirmed push clears the mark', () async {
    await ledger.mark('meals');
    await ledger.clear('meals');
    expect(await ledger.isDirty('meals'), isFalse);
  });
}
