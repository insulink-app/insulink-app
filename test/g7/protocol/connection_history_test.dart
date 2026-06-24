import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/g7/protocol/connection.dart';
import 'package:insulink/src/g7/store.dart';

import '../../support/secure_storage_mock.dart';

/// Guards the refill bug: a backfill record older than the live point (after a
/// long outage) must NOT be mistaken for a new-sensor session and wipe history.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  Future<G7Connection> connection() async {
    final store = await G7Store.open();
    return G7Connection(store: store, serial: 's', pairingCode: '0000');
  }

  test('backfill after a long outage keeps pre-gap history', () async {
    final conn = await connection();
    // An hour of history, then a 3h outage, then a fresh live EGV at "now".
    for (var secs = 36000; secs <= 39600; secs += 300) {
      conn.ingestLive(secs, 100);
    }
    const now = 39600 + 3 * 3600;
    conn.ingestLive(now, 120);
    // The gap backfill streams in oldest-first — the oldest is >1h behind now.
    for (var secs = 39900; secs < now; secs += 300) {
      conn.ingestBackfill(secs, 110);
    }
    expect(conn.history.containsKey(36000), isTrue, reason: 'old data kept');
    expect(conn.history[now], 120);
    expect(conn.history.length, (now - 36000) ~/ 300 + 1);
  });

  test('a live EGV with a reset clock (new sensor) does drop old history', () async {
    final conn = await connection();
    conn.ingestLive(691200, 100); // ~8 days into the old session
    conn.ingestLive(120, 95); // new sensor: clock back near zero
    expect(conn.history.containsKey(691200), isFalse);
    expect(conn.history, {120: 95});
  });
}
