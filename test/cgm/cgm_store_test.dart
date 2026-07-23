import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_store.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> backing;
  late CgmStore store;

  setUp(() async {
    backing = installSecureStorageMock();
    store = await CgmStore.open();
  });

  test('an empty store reports nothing paired and defaults to the G7', () {
    expect(store.serial, isNull);
    expect(store.pairingCode, isNull);
    expect(store.resolvedKey, isNull);
    expect(store.sensorType, SensorType.dexcomG7);
  });

  test('the identity and sensor type survive a write', () async {
    await store.saveIdentity(serial: 'DX1234', pairingCode: '1234');
    await store.saveResolvedKey('DX1234');
    await store.saveSensorType(SensorType.abbottLibre3);

    expect(store.serial, 'DX1234');
    expect(store.pairingCode, '1234');
    expect(store.resolvedKey, 'DX1234');
    expect(store.sensorType, SensorType.abbottLibre3);
  });

  test('the session key round-trips through its hex form', () async {
    final key = Uint8List.fromList(List.generate(16, (index) => index));

    await store.saveSessionKey('DX1234', key);

    expect(store.sessionKey('DX1234'), key);
    expect(store.sessionKeyHex('DX1234'), '000102030405060708090a0b0c0d0e0f');
    expect(store.sessionKey('OTHER'), isNull);
  });

  test('a truncated stored session key is rejected instead of half-decoded', () async {
    await store.saveSessionKeyHex('DX1234', 'aabb');

    expect(store.sessionKey('DX1234'), isNull);
  });

  test('clearing the session key leaves the rest of the pairing alone', () async {
    await store.saveIdentity(serial: 'DX1234', pairingCode: '1234');
    await store.saveSessionKeyHex('DX1234', '00' * 16);

    await store.clearSessionKey('DX1234');

    expect(store.sessionKey('DX1234'), isNull);
    expect(store.serial, 'DX1234');
  });

  test('the Libre secrets are keyed per resolved sensor', () async {
    final pin = Uint8List.fromList([1, 2, 3, 4]);
    final auth = Uint8List.fromList(List.filled(16, 0xAB));

    await store.saveLibreMac('S1', 'AA:BB:CC:DD:EE:FF');
    await store.saveLibrePin('S1', pin);
    await store.saveLibreAuthKey('S1', auth);

    expect(store.libreMac('S1'), 'AA:BB:CC:DD:EE:FF');
    expect(store.librePin('S1'), pin);
    expect(store.librePinHex('S1'), '01020304');
    expect(store.libreAuthKey('S1'), auth);
    expect(store.libreMac('S2'), isNull);

    await store.clearLibreAuthKey('S1');
    expect(store.libreAuthKey('S1'), isNull);
    expect(store.librePin('S1'), pin);
  });

  test('the backend sync bookkeeping is kept per sensor', () async {
    await store.saveBackendSensorId('S1', 'uuid-1');
    await store.saveBackendSyncedData('S1', '{"serial":"S1"}');
    await store.setRestoreDismissed('uuid-1');

    expect(store.backendSensorId('S1'), 'uuid-1');
    expect(store.backendSyncedData('S1'), '{"serial":"S1"}');
    expect(store.backendSensorId('S2'), isNull);
    expect(store.restoreDismissedId, 'uuid-1');
  });

  test('clearSensor forgets the pairing but keeps the chosen sensor type', () async {
    await store.saveSensorType(SensorType.abbottLibre3);
    await store.saveIdentity(serial: 'S1', pairingCode: '1234');
    await store.saveResolvedKey('S1');
    await store.saveSessionKeyHex('S1', '00' * 16);
    await store.saveLibreMac('S1', 'AA:BB:CC:DD:EE:FF');

    await store.clearSensor('S1');

    expect(store.serial, isNull);
    expect(store.pairingCode, isNull);
    expect(store.resolvedKey, isNull);
    expect(store.sessionKey('S1'), isNull);
    expect(store.libreMac('S1'), isNull);
    expect(store.sensorType, SensorType.abbottLibre3);
  });

  test('reload picks up a write made by the other isolate', () async {
    backing['g7.serial'] = 'FROM-SERVICE';
    expect(store.serial, isNull);

    await store.reload();

    expect(store.serial, 'FROM-SERVICE');
  });
}
