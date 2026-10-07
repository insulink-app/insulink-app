import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/demo/demo_cardio.dart';
import 'package:insulink/src/demo/demo_live_track.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/training/active_training.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';

void main() {
  const store = SportStore();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<List<TrackPoint>> sampleOnce(ActiveTraining training) async {
    final track = DemoLiveTrack(store: store, active: () => training)..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    track.stop();
    return store.loadLocationLog();
  }

  test('a walk is where its pace has carried it along the route', () async {
    final started = DateTime.now().subtract(const Duration(minutes: 1));
    final walk = ActiveTraining(
      type: CardioType.walk,
      startMs: started.millisecondsSinceEpoch,
    );
    final log = await sampleOnce(walk);
    final metres = 60 * DemoCardio.kilometresPerHour['walk']! / 3.6;
    final (lat, lng) = DemoLiveTrack.routes[CardioType.walk]!.at(metres);
    expect(log, hasLength(1));
    expect(log.single.lat, closeTo(lat, 0.00005));
    expect(log.single.lng, closeTo(lng, 0.00005));
  });

  test('a paused training records nothing', () async {
    final paused = ActiveTraining(
      type: CardioType.jog,
      startMs: DateTime.now().millisecondsSinceEpoch,
    ).pause();
    expect(await sampleOnce(paused), isEmpty);
  });
}
