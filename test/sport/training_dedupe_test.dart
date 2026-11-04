import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/request/sync_ledger.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

void main() {
  const jog = CardioTraining(
    id: 'auto-1',
    type: CardioType.jog,
    startMs: 0,
    endMs: 60000,
    track: [],
    distanceM: 1000,
    detected: true,
  );

  test(
    'a pull merge keeps the local retype instead of re-adding the old copy',
    () {
      final merged = const SyncLedger().merge(
        [jog.withType(CardioType.bike)],
        [jog],
        (CardioTraining item) => item.id,
      );
      expect(merged.map((training) => training.type), [CardioType.bike]);
    },
  );
}
