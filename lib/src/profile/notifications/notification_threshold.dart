import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The number behind a notification setting — the "x" in "warn me x hours before
/// the pod expires" and "warn me below x units left".
///
/// Mirrors [NotificationSetting] (const instances keyed by storage key, read
/// fresh on use so a change needs no service restart); it just carries an int
/// plus its editor bounds instead of a flag.
///
/// ponytail: one shared class for the homogeneous numeric thresholds instead of
/// a bespoke ProfileXState each — they only differ by key, label and bounds.
class NotificationThreshold {
  const NotificationThreshold({
    required this.storageKey,
    required this.labelKey,
    required this.valueKey,
    required this.defaultValue,
    required this.min,
    required this.max,
    this.step = 1,
  });

  final String storageKey;
  final String labelKey;
  final String valueKey;
  final int defaultValue;
  final int min;
  final int max;
  final int step;

  /// Hours before the pod runs out at which to warn.
  static const podExpiry = NotificationThreshold(
    storageKey: 'pod_expiry_hours',
    labelKey: 'profile.pod_expiry.threshold',
    valueKey: 'profile.pod_expiry.threshold.value',
    defaultValue: 4,
    min: 1,
    max: 24,
  );

  /// Units left in the pod below which to warn.
  static const podInsulin = NotificationThreshold(
    storageKey: 'pod_insulin_units',
    labelKey: 'profile.pod_insulin.threshold',
    valueKey: 'profile.pod_insulin.threshold.value',
    defaultValue: 10,
    min: 5,
    max: 50,
  );

  Future<int> load() async {
    final raw = await const FlutterSecureStorage().read(key: storageKey);
    final value = int.tryParse(raw ?? '') ?? defaultValue;
    return value.clamp(min, max);
  }

  Future<void> save(int value) => const FlutterSecureStorage().write(
    key: storageKey,
    value: '${value.clamp(min, max)}',
  );
}
