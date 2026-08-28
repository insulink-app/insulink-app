import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';

import '../support/secure_storage_mock.dart';

/// A suggestion must never switch anyone's basal by appearing. It lands beside
/// the others as something to look at, and becomes real only when a person picks
/// it in the basal section.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  BasalProfile named(String name, double rate) => BasalProfile(
        name: name,
        rates: List<double>.filled(24, rate),
        peaks: const [],
        dailyTotal: rate * 24,
      );

  ProfileBasalState stateWith() =>
      ProfileBasalState([named('Alltag', 1.0)], 0);

  test('a suggested profile does not become the active one', () {
    final state = stateWith();

    state.addInactiveProfile(named('Vorschlag', 1.4));

    expect(state.profiles, hasLength(2));
    expect(state.activeIndex, 0);
    expect(state.active.name, 'Alltag');
  });

  test('it can then be picked deliberately', () {
    final state = stateWith();
    final index = state.addInactiveProfile(named('Vorschlag', 1.4));

    state.selectActive(index);

    expect(state.active.name, 'Vorschlag');
    expect(state.active.rates.first, 1.4);
  });

  /// Adding a blank profile by hand is the other path and still selects it,
  /// because there the user asked for a new profile to edit.
  test('adding one by hand still selects it', () {
    final state = stateWith();

    final index = state.addProfile('Wochenende');

    expect(state.activeIndex, index);
  });

  test('several suggestions can sit side by side', () {
    final state = stateWith();

    state.addInactiveProfile(named('Vorschlag 7', 1.1));
    state.addInactiveProfile(named('Vorschlag 30', 1.2));

    expect(state.profiles.map((profile) => profile.name),
        ['Alltag', 'Vorschlag 7', 'Vorschlag 30']);
    expect(state.activeIndex, 0);
  });
}
