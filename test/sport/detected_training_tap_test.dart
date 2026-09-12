import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sport/training/detected_training_tap.dart';

/// The tap arrives as the notification's payload, "id\nwritablePath" — the same
/// payload the Confirm/Reject buttons carry, so only the id half is ours.
void main() {
  setUp(() => DetectedTrainingTap.requested.value = null);

  test('takes the training id out of the payload', () {
    DetectedTrainingTap.record('t-42\n/tmp/insulink_training_decisions');
    expect(DetectedTrainingTap.requested.value, 't-42');
  });

  test('ignores a payload with nothing to open', () {
    DetectedTrainingTap.record(null);
    DetectedTrainingTap.record('');
    DetectedTrainingTap.record('\n/tmp/whatever');
    expect(DetectedTrainingTap.requested.value, isNull);
  });
}
