/// One device registration as the account holds it, before the list works out
/// when the device came off.
///
/// The backend keeps a row per registration and never deletes one: discarding a
/// sensor or a pod only stamps it, precisely so the row stays the user's device
/// log. So the history needs no second copy on the phone, only this decoding of
/// what is already there.
class DeviceRecord {
  const DeviceRecord({
    required this.deviceKey,
    required this.typeKey,
    required this.start,
    required this.expiresAt,
    required this.registeredAt,
    this.discardedAt,
  });

  /// What identifies the PHYSICAL device across registrations: a sensor's
  /// resolved key, a pod's activation moment. A reinstall restores the running
  /// device and registers it again, so the same hardware can hold several rows.
  final String deviceKey;

  /// Locale key for the product name (`sensor.type.g7`, `pump.type.omnipod_dash`).
  final String typeKey;

  /// When the device itself started, NOT when it was registered. The app POSTs
  /// the registration once the identity is complete, and a restore re-registers
  /// a device that has already been running for hours, so `registeredAt` is no
  /// use as a start. Falls back to it only for a record too old to carry one.
  final DateTime start;

  final DateTime expiresAt;
  final DateTime registeredAt;

  /// When the user said this device is gone, or null while it is still theirs.
  final DateTime? discardedAt;
}
