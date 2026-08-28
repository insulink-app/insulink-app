import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A single on/off notification preference, stored in secure storage and read
/// fresh by the service isolate's alarm code (which can't observe a notifier —
/// same constraint as [ProfileSilentState]), so a toggle takes effect without
/// restarting the service.
///
/// ponytail: one shared class for the homogeneous lifecycle-notification
/// toggles instead of a bespoke ProfileXState per setting — they only differ by
/// storage key and label. Default ON: all of these are safety/lifecycle
/// relevant.
class NotificationSetting {
  const NotificationSetting(this.storageKey, this.labelKey);

  final String storageKey;
  final String labelKey;

  static const expiry = NotificationSetting(
    'sensor_expiry_alert',
    'profile.expiry.description',
  );
  static const halftime = NotificationSetting(
    'sensor_halftime_alert',
    'profile.halftime.description',
  );
  static const training = NotificationSetting(
    'training_detected_alert',
    'profile.training.description',
  );
  static const advisory = NotificationSetting(
    'predictive_advisory_alert',
    'profile.advisory.description',
  );

  /// Pod lifetime/reservoir warnings. Their thresholds are the matching
  /// [NotificationThreshold]s. Nothing fires on them yet — no pod is connected;
  /// the pump feature reads both once it is.
  static const podExpiry = NotificationSetting(
    'pod_expiry_alert',
    'profile.pod_expiry.description',
  );
  static const podInsulin = NotificationSetting(
    'pod_insulin_alert',
    'profile.pod_insulin.description',
  );

  /// Whether the POD itself beeps when a bolus finishes.
  ///
  /// Not a phone notification like the rest of these, but the same shape of
  /// preference, so it rides the same plumbing: one key, default ON, read fresh
  /// wherever it is needed. The pod is told about it in the bolus command, so a
  /// change applies to the next dose without touching the pod in between.
  static const podBolusBeep = NotificationSetting(
    'pod_bolus_beep',
    'profile.pod_bolus_beep.description',
  );

  /// Whether the pod beeps when a temporary basal rate is set or cancelled BY
  /// HAND. The automation is silent regardless: it changes the rate every five
  /// minutes, and a confirmation tone that often is not a confirmation.
  static const podTempBasalBeep = NotificationSetting(
    'pod_temp_basal_beep',
    'profile.pod_temp_basal_beep.description',
  );

  Future<bool> load() async =>
      (await const FlutterSecureStorage().read(key: storageKey)) != 'false';

  Future<void> save(bool value) =>
      const FlutterSecureStorage().write(key: storageKey, value: '$value');
}
