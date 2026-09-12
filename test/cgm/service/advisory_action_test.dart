import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';

File get _requestFile =>
    File('${Directory.systemTemp.path}/insulink_advisory_requests');

/// The hand-off between the bare notification-action isolate and the service
/// isolate is a plain text file, so its one line is the whole contract: a
/// malformed line must be dropped rather than deliver something, and a request
/// the service only finds much later must not be carried out at all.
void main() {
  setUp(() {
    if (_requestFile.existsSync()) {
      _requestFile.deleteSync();
    }
  });

  test('round-trips recorded requests through the file, in order', () async {
    const store = AdvisoryActionStore();
    store.record('bolus', 2.5, 214);
    store.record('carbs', 18.0, 74);
    final drained = await store.drain();

    expect(drained.map((request) => request.isBolus), [true, false]);
    expect(drained.map((request) => request.amount), [2.5, 18.0]);
    expect(drained.map((request) => request.glucoseMgdl), [214, 74]);
    expect(drained.every((request) => !request.isStale), isTrue);
  });

  test(
    'a drain clears the file, so a tap cannot be carried out twice',
    () async {
      const store = AdvisoryActionStore();
      store.record('bolus', 2.5, 214);
      expect(await store.drain(), hasLength(1));
      expect(await store.drain(), isEmpty);
    },
  );

  test('drops a malformed line instead of guessing at it', () {
    expect(AdvisoryRequest.parse('bolus:2.5:214'), isNull);
    expect(AdvisoryRequest.parse('bolus:two:214:1'), isNull);
    expect(AdvisoryRequest.parse('bolus:2.5:high:1'), isNull);
    expect(AdvisoryRequest.parse(''), isNull);
  });

  test('drops a dose of nothing rather than sending a zero bolus', () {
    expect(AdvisoryRequest.parse('bolus:0.0:214:1'), isNull);
    expect(AdvisoryRequest.parse('bolus:-1.0:214:1'), isNull);
  });

  test('the offer time is what ages, not the moment of the tap', () async {
    const store = AdvisoryActionStore();
    final offered = DateTime.now().subtract(AdvisoryRequest.validFor * 2);
    store.record(
      'bolus',
      2.5,
      214,
      offeredAtMs: offered.millisecondsSinceEpoch,
    );
    final drained = await store.drain();
    expect(drained.single.isStale, isTrue);
  });

  test('treats a request older than its window as stale', () {
    final old = AdvisoryRequest(
      isBolus: true,
      amount: 2.5,
      glucoseMgdl: 214,
      at: DateTime.now().subtract(AdvisoryRequest.validFor * 2),
    );
    expect(old.isStale, isTrue);
  });
}
