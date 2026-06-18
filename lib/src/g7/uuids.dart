/// Dexcom G7 GATT UUIDs.
///
/// The official app stores these as DexGuard-encrypted strings (the
/// `ProfileDescription` class builds them at runtime from 16-bit IDs via a
/// `uuidConverter`), so they could NOT be lifted statically from the APK.
///
/// The values below are the well-known Dexcom CGM UUIDs used by the open-source
/// community (xDrip+, Juggluco) — the G7 reuses the G6 service base. Treat them
/// as STRONG CANDIDATES and confirm by enumerating services on a real sensor
/// (see BleTransport.discover, which logs everything it finds).
library;

class G7Uuids {
  /// Primary CGM service. (Confirmed against Juggluco's DexGattCallback.)
  static const String cgmService = 'f8083532-849e-531c-c594-30f1f86a4ea5';

  /// Control characteristic (commands + responses, e.g. glucose `0x4E`).
  static const String control = 'f8083534-849e-531c-c594-30f1f86a4ea5';

  /// Authentication characteristic — short opcode handshake runs here.
  static const String authentication = 'f8083535-849e-531c-c594-30f1f86a4ea5';

  /// Backfill characteristic — historical glucose stream.
  static const String backfill = 'f8083536-849e-531c-c594-30f1f86a4ea5';

  /// J-PAKE bulk-data characteristic — the 160-byte EC-JPAKE round payloads and
  /// certificate bytes flow here (written WRITE_NO_RESPONSE, 20-byte chunks).
  static const String jpake = 'f8083538-849e-531c-c594-30f1f86a4ea5';

  /// Standard CCCD descriptor for enabling notifications/indications.
  static const String cccd = '00002902-0000-1000-8000-00805f9b34fb';

  /// 16-bit service advertised by the sensor (used to filter scan results).
  /// CONFIRM: some firmware advertises only the device name (e.g. "DXCMxx").
  static const String advertisedService16 = 'febc';
}
