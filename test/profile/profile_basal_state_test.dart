import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;

  setUp(() {
    backing = installSecureStorageMock();
  });

  test('an empty store loads a single default profile', () async {
    final state = await ProfileBasalState.load();

    expect(state.profiles.length, 1);
    expect(state.activeIndex, 0);
    expect(state.active.name, 'Standard');
    expect(state.active.rates.length, 24);
  });

  test('the legacy comma-joined key migrates into one profile', () async {
    backing['basal_profile'] = List.filled(24, '0.85').join(',');

    final state = await ProfileBasalState.load();

    expect(state.profiles.length, 1);
    expect(state.active.rates.first, 0.85);
    expect(state.active.total, closeTo(24 * 0.85, 0.001));
  });

  test('a legacy blob with the wrong length falls back to a fresh profile', () async {
    backing['basal_profile'] = '1.0,2.0,3.0';

    final state = await ProfileBasalState.load();

    expect(state.active.rates, List.filled(24, 1.0));
  });

  test('adding, selecting and deleting profiles keeps the active index valid', () async {
    final state = await ProfileBasalState.load();

    expect(state.addProfile('Night'), 1);
    expect(state.activeIndex, 1);
    expect(state.active.name, 'Night');

    state.selectActive(0);
    expect(state.activeIndex, 0);

    state.selectActive(5);
    expect(state.activeIndex, 0, reason: 'out-of-range selection is ignored');

    state.deleteProfile(0);
    expect(state.profiles.length, 1);
    expect(state.activeIndex, 0);

    state.deleteProfile(0);
    expect(state.profiles.length, 1, reason: 'the last profile is never deleted');
  });

  test('an edit is persisted and read back on the next load', () async {
    final state = await ProfileBasalState.load();
    final edited = state.active.copy()..setHour(3, 1.35);

    state.updateProfile(0, edited);
    state.addProfile('Sport');

    final reloaded = await ProfileBasalState.load();
    expect(reloaded.profiles.length, 2);
    expect(reloaded.activeIndex, 1);
    expect(reloaded.profiles.first.rates[3], 1.35);
  });

  test('a stored blob with no profiles falls back instead of crashing', () async {
    backing['basal_profiles'] = jsonEncode({'active': 3, 'profiles': []});

    final state = await ProfileBasalState.load();

    expect(state.profiles.length, 1);
    expect(state.activeIndex, 0);
  });

  test('an out-of-range stored active index is clamped', () async {
    backing['basal_profiles'] = jsonEncode({
      'active': 9,
      'profiles': [BasalProfile.initial('Standard').toJson()],
    });

    expect((await ProfileBasalState.load()).activeIndex, 0);
  });

  test('loadRaw returns the stored blob, or the default encoded', () async {
    final raw = await ProfileBasalState.loadRaw();
    expect(jsonDecode(raw)['profiles'], hasLength(1));

    final state = await ProfileBasalState.load();
    state.addProfile('Sport');

    expect(jsonDecode(await ProfileBasalState.loadRaw())['profiles'], hasLength(2));
  });

  test('the profile list is unmodifiable from the outside', () async {
    final state = await ProfileBasalState.load();

    expect(
      () => state.profiles.add(BasalProfile.initial('x')),
      throwsUnsupportedError,
    );
  });
}
