/// FreeStyle Libre 3 GATT UUIDs (from DiaBLE's `Libre3.UUID`, matching
/// Juggluco's `Libre3GattCallback` characteristic names). All share the
/// `-EF89-11E9-81B4-2A2AE2DBCCE4` suffix.
class Libre3Uuids {
  static const dataService = '089810CC-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const patchControl = '08981338-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const patchStatus = '08981482-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const oneMinuteReading = '0898177A-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const historicalData = '0898195A-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const clinicalData = '08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const eventLog = '08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const factoryData = '08981D24-EF89-11E9-81B4-2A2AE2DBCCE4';

  static const securityService = '0898203A-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const securityCommands = '08982198-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const challengeData = '089822CE-EF89-11E9-81B4-2A2AE2DBCCE4';
  static const certificateData = '089823FA-EF89-11E9-81B4-2A2AE2DBCCE4';

  /// Channel ids for `intDecrypt` (the AES-CCM data decrypt), from Juggluco.
  static const decryptPatchStatus = 2;
  static const decryptGlucose = 3;
  static const decryptHistoric = 4;
}
