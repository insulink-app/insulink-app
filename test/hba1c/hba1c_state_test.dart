import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/hba1c/hba1c_entry.dart';
import 'package:insulink/src/hba1c/hba1c_state.dart';

import '../support/secure_storage_mock.dart';

/// The two things the HbA1c history has to get right: the readings stay in
/// chronological order whatever order they were entered in, and a reading is
/// identified by its instant — the server's natural key — so correcting a lab
/// result overwrites it instead of leaving two contradictory values in the list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  DateTime at(int year, int month) => DateTime(year, month, 15, 9, 30);

  test('readings are kept oldest-first however they were entered', () async {
    final state = Hba1cState([]);
    await state.add(7.4, at: at(2026, 3));
    await state.add(6.8, at: at(2025, 9));
    await state.add(7.1, at: at(2025, 12));
    expect(
      [for (final entry in state.entries) entry.percent],
      [6.8, 7.1, 7.4],
    );
    expect(state.latest?.percent, 7.4);
    expect(state.previous?.percent, 7.1);
  });

  test('a corrected result at the same instant replaces it', () async {
    final state = Hba1cState([]);
    await state.add(6.8, at: at(2025, 9));
    await state.add(7.0, at: at(2025, 9));
    expect(state.entries.length, 1);
    expect(state.latest?.percent, 7.0);
  });

  test('editing to a new timestamp moves the reading, leaving one', () async {
    final state = Hba1cState([]);
    await state.add(6.8, at: at(2025, 9));
    await state.edit(state.entries.first, percent: 6.9, at: at(2025, 10));
    expect(state.entries.length, 1);
    expect(state.latest?.percent, 6.9);
    expect(state.latest?.time.month, 10);
  });

  test('a pulled reading merges without dropping a local-only one', () async {
    final state = Hba1cState([]);
    await state.add(7.4, at: at(2026, 3));
    await state.adopt([
      Hba1cEntry(
        atEpochMs: at(2025, 9).millisecondsSinceEpoch,
        percent: 6.8,
      ),
    ]);
    expect([for (final entry in state.entries) entry.percent], [6.8, 7.4]);
  });

  test('the derived lab figures follow the published conversions', () {
    const entry = Hba1cEntry(atEpochMs: 0, percent: 7.0);
    expect(entry.mmolPerMol, closeTo(53.0, 0.5));
    expect(entry.averageGlucoseMgDl, closeTo(154.2, 0.5));
  });

  test('an entry round-trips through its json form', () {
    const entry = Hba1cEntry(atEpochMs: 1700000000000, percent: 6.8);
    final restored = Hba1cEntry.fromJson(entry.toJson());
    expect(restored.atEpochMs, entry.atEpochMs);
    expect(restored.percent, entry.percent);
  });
}
