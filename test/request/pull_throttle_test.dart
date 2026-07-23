import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/request/pull_throttle.dart';

void main() {
  test('the first run within a fresh window fires', () async {
    const throttle = PullThrottle('a');
    throttle.reset();
    var runs = 0;
    await throttle.run(() async => runs++);
    expect(runs, 1);
  });

  test('a second run inside the window is skipped', () async {
    const throttle = PullThrottle('b');
    throttle.reset();
    var runs = 0;
    await throttle.run(() async => runs++);
    await throttle.run(() async => runs++);
    expect(runs, 1);
  });

  test('an elapsed window runs again', () async {
    const throttle = PullThrottle('c', interval: Duration.zero);
    throttle.reset();
    var runs = 0;
    await throttle.run(() async => runs++);
    await throttle.run(() async => runs++);
    expect(runs, 2);
  });

  test('reset forgets the last run', () async {
    const throttle = PullThrottle('d');
    throttle.reset();
    var runs = 0;
    await throttle.run(() async => runs++);
    throttle.reset();
    await throttle.run(() async => runs++);
    expect(runs, 2);
  });

  test('the stamp is taken before the pull, so overlapping opens fire once',
      () async {
    const throttle = PullThrottle('e');
    throttle.reset();
    var runs = 0;
    Future<void> slow() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      runs++;
    }

    // Two opens racing before the first completes: the second must see the
    // stamp already set and skip.
    await Future.wait([throttle.run(slow), throttle.run(slow)]);
    expect(runs, 1);
  });

  test('keys are independent', () async {
    const first = PullThrottle('f1');
    const second = PullThrottle('f2');
    first.reset();
    second.reset();
    var runs = 0;
    await first.run(() async => runs++);
    await second.run(() async => runs++);
    expect(runs, 2);
  });
}
