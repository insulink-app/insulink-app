import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/store.dart';

import '../support/secure_storage_mock.dart';

/// Guards the disappearing-data fix: the overview chart sources its history from
/// the durable archive, not the lossy per-session cache. This verifies the
/// arithmetic the controller's `byTime` getter uses to convert archive
/// epoch-minutes back to session-relative seconds — and that a point archived
/// once survives a session-cache wipe (the failure that dropped chart data).
SplayTreeMap<int, int> chartFromArchive(
  G7Store store,
  DateTime sensorStart,
  DateTime now,
) {
  final startSecs = sensorStart.millisecondsSinceEpoch ~/ 1000;
  final dayAgo = now.subtract(const Duration(hours: 24));
  final out = SplayTreeMap<int, int>();
  store
      .archiveRange(sensorStart.isAfter(dayAgo) ? sensorStart : dayAgo, now)
      .forEach((epochMin, mgdl) {
        final secs = epochMin * 60 - startSecs;
        if (secs >= 0) {
          out[secs] = mgdl;
        }
      });
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  test('archived readings round-trip to session-seconds and survive a wipe',
      () async {
    final store = await G7Store.open();
    final start = DateTime(2024, 1, 1, 8, 0);
    // Three readings 5 min apart, as the service archives them (wall-clock).
    for (var step = 0; step < 3; step++) {
      final secs = step * 300;
      await store.archiveAdd(start.add(Duration(seconds: secs)), 100 + step);
    }
    // A session-cache wipe (clearSensor / _resetIfNewSession) leaves the chart
    // source untouched because it reads the archive, not the cache.
    await store.clearSensor('whatever');

    final now = start.add(const Duration(minutes: 20));
    final chart = chartFromArchive(store, start, now);
    expect(chart, {0: 100, 300: 101, 600: 102});
  });
}
