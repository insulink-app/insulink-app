import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/backup/data_backup.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'backup carries the account history and every stored entry but the tokens',
    () async {
      final storage = installSecureStorageMock()
        ..addAll({
          'g7.serial': 'ABC123',
          'sport.sessions': '[]',
          'authentication_token': 'secret',
          'refresh_token': 'secret',
        });
      final created = DateTime.fromMillisecondsSinceEpoch(1760000000000);
      final backup = await const DataBackup().collect(created, {
        '/glucose/history/': {'entries': []},
      });
      expect(backup['format'], 'insulink_backup');
      expect(backup['version'], DataBackup.formatVersion);
      expect(backup['created_at'], 1760000000000);
      expect(backup['account'], {
        '/glucose/history/': {'entries': []},
      });
      expect(backup['device'], {'g7.serial': 'ABC123', 'sport.sessions': '[]'});
      expect(storage, contains('refresh_token'));
    },
  );
}
