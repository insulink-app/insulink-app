import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/sport_sync.dart';

import '../support/secure_storage_mock.dart';

/// After a reinstall the step state is built BEFORE the account pull writes the
/// history into storage. It must neither overwrite that history with its stale
/// empty copy nor keep hiding it once the app reloads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SportStore();

  DailyActivity day(String dateKey, int steps) =>
      DailyActivity(dateKey: dateKey, steps: steps, distanceKm: 0, calories: 0);

  setUp(installSecureStorageMock);
  tearDown(SportSync.cancelPending);

  Future<SportActivityState> stateBuiltBeforeThePull() async {
    final state = SportActivityState();
    await state.reloadArchive();
    await store.saveActivityArchive([
      day('2026-10-01', 9000),
      day('2026-10-02', 7000),
    ]);
    return state;
  }

  test('a flush keeps the history pulled behind the state', () async {
    final state = await stateBuiltBeforeThePull();

    await state.mergeArchive([day('2026-10-03', 1200)]);

    final keys = [
      for (final entry in await store.loadActivityArchive()) entry.dateKey,
    ];
    expect(keys, ['2026-10-01', '2026-10-02', '2026-10-03']);
  });

  test('a reload shows the pulled history', () async {
    final state = await stateBuiltBeforeThePull();

    await state.reloadArchive();

    expect(state.activityArchive.length, 2);
  });
}
