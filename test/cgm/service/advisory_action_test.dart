import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/service/advisory_action.dart';

/// The notification payload is the whole hand-off from the pre-warning to the
/// app, and one of the two things it carries decides a dose, so a payload that
/// cannot be read has to come back as nothing rather than as a guess.
void main() {
  test('a carbs tap round-trips through the payload', () {
    final request = AdvisoryRequest.parse(
      advisoryCarbsAction,
      AdvisoryRequest.encode(18, 74),
    );
    expect(request, isNotNull);
    expect(request!.isBolus, isFalse);
    expect(request.amount, 18);
    expect(request.glucoseMgdl, 74);
  });

  test('a bolus tap keeps its fractional units', () {
    final request = AdvisoryRequest.parse(
      advisoryBolusAction,
      AdvisoryRequest.encode(2.4, 214),
    );
    expect(request!.isBolus, isTrue);
    expect(request.amount, closeTo(2.4, 1e-9));
  });

  test('a tap that is not ours is ignored', () {
    expect(AdvisoryRequest.parse('training_confirm', '18.0\n74'), isNull);
    expect(AdvisoryRequest.parse(null, '18.0\n74'), isNull);
  });

  test('an unreadable payload yields nothing, never a guessed dose', () {
    expect(AdvisoryRequest.parse(advisoryBolusAction, null), isNull);
    expect(AdvisoryRequest.parse(advisoryBolusAction, '2.4'), isNull);
    expect(AdvisoryRequest.parse(advisoryBolusAction, 'two\n214'), isNull);
    expect(AdvisoryRequest.parse(advisoryBolusAction, '2.4\nhigh'), isNull);
    expect(AdvisoryRequest.parse(advisoryBolusAction, '0.0\n214'), isNull);
  });
}
