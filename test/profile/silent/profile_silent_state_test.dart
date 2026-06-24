import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/profile/silent/profile_silent_state.dart';

import '../../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('defaults to off when nothing is stored', () async {
    expect(await ProfileSilentState.load(), isFalse);
  });

  test('setSilent persists and load reads it back', () async {
    final state = ProfileSilentState(false);
    await state.setSilent(true);
    expect(state.silent, isTrue);
    expect(await ProfileSilentState.load(), isTrue);
  });

  test('setSilent is a no-op when the value is unchanged', () async {
    final state = ProfileSilentState(false);
    await state.setSilent(false);
    expect(await ProfileSilentState.load(), isFalse);
  });
}
